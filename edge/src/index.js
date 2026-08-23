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
// The staging host: same first-segment-is-the-slug routing, but it serves a
// site's DRAFT design from the preview build channel and is kept out of
// search (noindex). A draft deploys here for a second opinion before it's
// promoted to production.
const PREVIEW_HOSTS = new Set(["preview.kindredquill.com"]);
const SLUG = /^\/([A-Za-z0-9_-]{1,32})(\/.*)?$/;

// The bare apex is the static marketing site — the app never serves it. The
// one thing this Worker owes it is the in-flight-link tail: tokened
// newsletter/contact links minted before the sites.* cutover carry
// kindredquill.com/<SLUG>/… and must keep working (unsubscribe tokens never
// expire). Raw slugs resolve on the sites host with no KV entry, so the
// redirect is purely mechanical. Route only these path patterns here; the
// static site serves everything else on the apex.
const APEX_HOSTS = new Set(["kindredquill.com", "www.kindredquill.com"]);
const APEX_TAIL = /^\/[A-Za-z0-9_-]{1,32}\/(?:newsletter|contact)(\/|$)/;

// Platform subdomains that aren't tenant sites: hosted elsewhere and proxied
// straight through, so they never fall into the unknown-hostname 404. The
// zone-wide Worker route catches them (that's how docs hit "No site is
// configured"); this map hands them to their real home.
const PASSTHROUGH_HOSTS = new Map([
  ["docs.kindredquill.com", "https://inkwell-support.pages.dev"],
]);

// Where a site's builds and pointer live in the bucket, per channel: preview
// (the staging host) sits one level deeper than production.
function siteRoot(slug, preview) {
  return preview ? `sites/${slug}/preview/` : `sites/${slug}/`;
}

// Dynamic islands — the enumerated allowlist of Rails-backed paths the
// Worker proxies to the origin (docs/phase-2-static-serving.md §2.5,
// enumerated from routes.rb). Newsletter and the buy-link click counter so
// far; contact/ahoy join as their own hardening passes land (the contact
// controller still carries session-backed spam traps that would discard every
// static submit — docs/newsletter-bot-protection-plan.md). Everything else is
// static bytes.
const ISLANDS = [
  { method: "POST", pattern: /^\/newsletter$/ },
  { method: "GET", pattern: /^\/newsletter\/(sent|rejected)$/ },
  { method: "GET", pattern: /^\/newsletter\/(confirm|unsubscribe|keep)(\/[^/]*)?$/ },
  // Buy links: the theme's dist-url partial emits buy/<distributor id>; Rails
  // counts the click and 302s to the store (redirect:"manual" below hands
  // that off-site Location straight back to the browser).
  { method: "GET", pattern: /^\/buy\/\d+$/ },
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

    // Non-tenant platform subdomains (docs, …) proxy to their real home,
    // path and method intact.
    const passthrough = PASSTHROUGH_HOSTS.get(host);
    if (passthrough) {
      return fetch(new URL(url.pathname + url.search, passthrough), request);
    }

    // Old apex links (kindredquill.com/<SLUG>/newsletter/…) 301 to the same
    // path on the sites host; anything else that reaches us on the apex is a
    // routing mistake — the static marketing site owns it.
    if (APEX_HOSTS.has(host)) {
      if (APEX_TAIL.test(url.pathname)) {
        return Response.redirect(
          "https://sites.kindredquill.com" + url.pathname + url.search, 301);
      }
      return plain404("Not found.");
    }

    // The platform and preview hosts both take the account slug from the first
    // path segment; custom domains resolve through KV.
    const preview = PREVIEW_HOSTS.has(host);
    const pathHost = PLATFORM_HOSTS.has(host) || preview;

    let slug;
    let pathname = url.pathname;
    if (pathHost) {
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

    // Dynamic islands proxy to Rails. A custom domain forwards its own host
    // (Rails resolves the tenant by domain); the platform host forwards the
    // ORIGINAL prefixed path — Rails' sites-host branch resolves the handle/
    // slug segment and mounts it, so redirects come back prefixed. Preview
    // stays static-only (drafts don't collect subscribers). Checked BEFORE
    // the trailing-slash canonicalization below, so tokened island GETs
    // (confirm/unsubscribe) are never slash-mangled. With RAILS_ORIGIN unset
    // islands stay off and the path falls through to static handling.
    if (isIsland(request.method, pathname) && !preview && env.RAILS_ORIGIN) {
      return proxyIsland(request, env, host, pathHost ? url.pathname : pathname, url);
    }

    // Canonical trailing slash for directory URLs on the path hosts. The
    // build's asset/nav URLs are page-relative (Exporter sets Hugo's
    // relativeURLs so one build serves at both the domain root and the
    // <host>/<handle>/ path prefix). A directory URL without its trailing
    // slash makes the browser resolve "./asset" against the PARENT, so every
    // asset 404s. Custom domains sit at the root, where the missing slash
    // clamps back to "/" and resolves anyway — so this is scoped to the path
    // hosts. GET/HEAD only, after the island proxy has claimed its paths.
    // Stable relationship, safe to cache as 301.
    if (
      pathHost &&
      (request.method === "GET" || request.method === "HEAD") &&
      !url.pathname.endsWith("/") &&
      keyForPath(url.pathname)?.endsWith("/index.html")
    ) {
      return Response.redirect(url.origin + url.pathname + "/" + url.search, 301);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const root = siteRoot(slug, preview);
    const buildId = await buildIdFor(root, env);
    if (!buildId) return plain404("This site has not been published yet.");

    const key = keyForPath(pathname);
    if (!key) return plain404("Not found.");

    const prefix = `${root}builds/${buildId}/`;

    if (request.method === "HEAD") {
      const head = await env.SITES.head(prefix + key);
      if (!head) return missing(env, prefix, buildId, preview);
      return new Response(null, { headers: headersFor(head, key, buildId, preview) });
    }

    const object = await env.SITES.get(prefix + key, {
      onlyIf: request.headers,
    });
    if (!object) return missing(env, prefix, buildId, preview);

    const headers = headersFor(object, key, buildId, preview);
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
  // X-Forwarded-Host doesn't survive the proxy hops in front of Rails (they
  // rewrite it from the Host header), so the tenant host also rides a header
  // nothing else touches; Rails' IslandHost::Rewriter restores it, gated on
  // the island-auth secret.
  headers.set("x-island-host", host);
  headers.set("x-forwarded-proto", "https");
  // Same story for the client IP: X-Forwarded-For gets rewritten by the
  // proxy hops, so the CF-validated client IP also rides an island header
  // (rate limits and the consent log need the visitor, not an egress IP).
  const clientIP = request.headers.get("cf-connecting-ip");
  if (clientIP) {
    headers.set("x-forwarded-for", clientIP);
    headers.set("x-island-ip", clientIP);
  }
  if (env.ISLAND_AUTH) headers.set("x-island-auth", env.ISLAND_AUTH);
  return fetch(target, {
    method: request.method,
    headers,
    body: request.body,
    redirect: "manual",
  });
}

// root is the channel's home (sites/<slug>/ or sites/<slug>/preview/); it also
// keys the pointer cache, so a site's production and preview builds never
// shadow each other.
async function buildIdFor(root, env) {
  const now = Date.now();
  const hit = pointerCache.get(root);
  if (hit && hit.expires > now) return hit.buildId;

  const obj = await env.SITES.get(`${root}pointer.json`);
  if (!obj) return null;

  let pointer;
  try {
    pointer = await obj.json();
  } catch {
    return null;
  }

  const buildId = pointer.build_id;
  if (!buildId) return null;

  pointerCache.set(root, { buildId, expires: now + POINTER_TTL_MS });
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

function headersFor(object, key, buildId, preview = false) {
  const h = new Headers();
  object.writeHttpMetadata?.(h);
  if (!h.has("content-type")) {
    h.set("content-type", TYPES[extOf(key)] || "application/octet-stream");
  }
  h.set("etag", object.httpEtag);
  h.set("x-kq-build", buildId);
  // The staging host serves unpublished drafts — keep it out of search.
  if (preview) h.set("x-robots-tag", "noindex");
  // Theme CSS/JS (and the font sheet) are FINGERPRINTED by the Hugo build —
  // the content hash rides in the filename (css/06-sections.<sha256>.css), so a
  // changed file is a new URL and these can be cached forever: a rebuild
  // reaches every reader on their next page load. Everything else lives at
  // a STABLE url whose bytes change when a build publishes (covers, feeds,
  // font files), so no `immutable` there — a day of freshness plus a week of
  // serve-stale-while-revalidating keeps repeat visits fast without
  // freezing rebuilds out.
  h.set("cache-control", cacheControlFor(key));
  return h;
}

const FINGERPRINTED = /\.[0-9a-f]{16,}\.(css|js)$/;

function cacheControlFor(key) {
  if (extOf(key) === "html") return "public, max-age=0, must-revalidate";
  if (FINGERPRINTED.test(key)) return "public, max-age=31536000, immutable";
  return "public, max-age=86400, stale-while-revalidate=604800";
}

async function missing(env, prefix, buildId, preview = false) {
  const custom = await env.SITES.get(prefix + "404.html");
  if (!custom) return plain404("Not found.");
  const h = new Headers();
  h.set("content-type", "text/html; charset=utf-8");
  h.set("cache-control", "no-store");
  h.set("x-kq-build", buildId);
  if (preview) h.set("x-robots-tag", "noindex");
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
