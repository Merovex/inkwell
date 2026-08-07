const POINTER_TTL_MS = 30_000;
const pointerCache = new Map(); // slug -> { buildId, expires }

const TYPES = {
  html: "text/html; charset=utf-8",
  css: "text/css; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  json: "application/json; charset=utf-8",
  xml: "application/xml; charset=utf-8",
  txt: "text/plain; charset=utf-8",
  svg: "image/svg+xml",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  avif: "image/avif",
  ico: "image/x-icon",
  woff: "font/woff",
  woff2: "font/woff2",
  pdf: "application/pdf",
};

// The standard KindredQuill location: on these hosts the first path segment
// is the account slug (docs/phase-2-static-serving.md §2.5 "apex slug
// paths") — every site is servable here with no KV entry and no DNS.
// Custom domains still resolve through the HOSTNAMES KV.
const PLATFORM_HOSTS = new Set(["sites.kindredquill.com"]);
const SLUG = /^\/([A-Za-z0-9_-]{1,32})(\/.*)?$/;

// Dynamic islands — the enumerated allowlist of Rails-backed paths the
// Worker proxies to the origin (docs/phase-2-static-serving.md §2.5,
// enumerated from routes.rb). Newsletter only so far; contact/buy/ahoy join
// as their own hardening passes land (the contact controller still carries
// session-backed spam traps that would discard every static submit —
// docs/newsletter-bot-protection-plan.md). Everything else is static bytes.
const ISLANDS = [
  { method: "POST", pattern: /^\/newsletter$/ },
  { method: "GET", pattern: /^\/newsletter\/(sent|rejected)$/ },
  { method: "GET", pattern: /^\/newsletter\/(confirm|unsubscribe|keep)(\/[^/]*)?$/ },
];

function isIsland(method, pathname) {
  return ISLANDS.some((i) => i.method === method && i.pattern.test(pathname));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const host = (request.headers.get("host") || url.hostname)
      .split(":")[0]
      .toLowerCase();

    let slug;
    let pathname = url.pathname;
    if (PLATFORM_HOSTS.has(host)) {
      const m = pathname.match(SLUG);
      if (!m) return plain404("Sites live at /<site-code>/ on this host.");
      // The segment is a claimed handle (KV alias "handle:<name>" → slug,
      // written by the app's HandleRouteJob) or the raw slug — handle checked
      // first, so a handle that happens to be slug-shaped still resolves.
      slug =
        (await env.HOSTNAMES.get(`handle:${m[1].toLowerCase()}`, { cacheTtl: 300 })) ||
        m[1].toUpperCase();
      pathname = m[2] || "/";
    } else {
      slug = await env.HOSTNAMES.get(host, { cacheTtl: 300 });
      if (!slug) return plain404("No site is configured for this domain.");
    }

    // Dynamic islands proxy to Rails (custom-domain hosts only for now:
    // Rails resolves the tenant from the forwarded Host, and the platform
    // host has no Rails-side hostname mapping yet). With RAILS_ORIGIN unset
    // islands stay off and the path falls through to static handling.
    if (isIsland(request.method, pathname) && !PLATFORM_HOSTS.has(host) && env.RAILS_ORIGIN) {
      return proxyIsland(request, env, host, pathname, url);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const buildId = await buildIdFor(slug, env);
    if (!buildId) return plain404("This site has not been published yet.");

    const key = keyForPath(pathname);
    if (!key) return plain404("Not found.");

    const prefix = `sites/${slug}/builds/${buildId}/`;

    if (request.method === "HEAD") {
      const head = await env.SITES.head(prefix + key);
      if (!head) return missing(env, prefix, buildId);
      return new Response(null, { headers: headersFor(head, key, buildId) });
    }

    const object = await env.SITES.get(prefix + key, {
      onlyIf: request.headers,
    });
    if (!object) return missing(env, prefix, buildId);

    const headers = headersFor(object, key, buildId);
    if (!("body" in object) || object.body === null) {
      return new Response(null, { status: 304, headers });
    }
    return new Response(object.body, { headers });
  },
};

// Proxy a dynamic island to the Rails origin (phase-2 §2.5; bot-protection
// plan §2/§2a): forward the tenant host so AccountHost resolves the account,
// the CF-validated client IP so rate limits and the consent log see the
// visitor rather than this Worker, and the island-auth secret so the origin
// can refuse traffic that didn't come through here. redirect:"manual" hands
// Rails' redirects (→ /newsletter/sent on the tenant host) straight back to
// the browser, which re-enters this Worker for the next island.
async function proxyIsland(request, env, host, pathname, url) {
  const target = new URL(pathname + url.search, env.RAILS_ORIGIN);
  const headers = new Headers(request.headers);
  headers.set("x-forwarded-host", host);
  headers.set("x-forwarded-proto", "https");
  const clientIP = request.headers.get("cf-connecting-ip");
  if (clientIP) headers.set("x-forwarded-for", clientIP);
  if (env.ISLAND_AUTH) headers.set("x-island-auth", env.ISLAND_AUTH);
  return fetch(target, {
    method: request.method,
    headers,
    body: request.body,
    redirect: "manual",
  });
}

async function buildIdFor(slug, env) {
  const now = Date.now();
  const hit = pointerCache.get(slug);
  if (hit && hit.expires > now) return hit.buildId;

  const obj = await env.SITES.get(`sites/${slug}/pointer.json`);
  if (!obj) return null;

  let pointer;
  try {
    pointer = await obj.json();
  } catch {
    return null;
  }

  const buildId = pointer.build_id;
  if (!buildId) return null;

  pointerCache.set(slug, { buildId, expires: now + POINTER_TTL_MS });
  return buildId;
}

function keyForPath(pathname) {
  let p;
  try {
    p = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  p = p.replace(/^\/+/, "");
  if (p.includes("\0")) return null;
  if (p.split("/").some((seg) => seg === "..")) return null;
  if (p === "") return "index.html";
  if (p.endsWith("/")) return p + "index.html";
  const last = p.slice(p.lastIndexOf("/") + 1);
  if (!last.includes(".")) return p + "/index.html";
  return p;
}

function extOf(key) {
  const i = key.lastIndexOf(".");
  return i === -1 ? "" : key.slice(i + 1).toLowerCase();
}

function headersFor(object, key, buildId) {
  const h = new Headers();
  object.writeHttpMetadata?.(h);
  if (!h.has("content-type")) {
    h.set("content-type", TYPES[extOf(key)] || "application/octet-stream");
  }
  h.set("etag", object.httpEtag);
  h.set("x-kq-build", buildId);
  // Assets live at STABLE urls whose bytes change when a build publishes, so
  // no `immutable` — a day of freshness plus a week of serve-stale-while-
  // revalidating keeps repeat visits fast without freezing rebuilds out.
  h.set(
    "cache-control",
    extOf(key) === "html"
      ? "public, max-age=0, must-revalidate"
      : "public, max-age=86400, stale-while-revalidate=604800",
  );
  return h;
}

async function missing(env, prefix, buildId) {
  const custom = await env.SITES.get(prefix + "404.html");
  if (!custom) return plain404("Not found.");
  const h = new Headers();
  h.set("content-type", "text/html; charset=utf-8");
  h.set("cache-control", "no-store");
  h.set("x-kq-build", buildId);
  return new Response(custom.body, { status: 404, headers: h });
}

function plain404(message) {
  return new Response(message, {
    status: 404,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
