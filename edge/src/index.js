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

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const url = new URL(request.url);
    const host = (request.headers.get("host") || url.hostname)
      .split(":")[0]
      .toLowerCase();

    const slug = await env.HOSTNAMES.get(host, { cacheTtl: 300 });
    if (!slug) return plain404("No site is configured for this domain.");

    const buildId = await buildIdFor(slug, env);
    if (!buildId) return plain404("This site has not been published yet.");

    const key = keyForPath(url.pathname);
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
  h.set(
    "cache-control",
    extOf(key) === "html"
      ? "public, max-age=0, must-revalidate"
      : "public, max-age=3600",
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
