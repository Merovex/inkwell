// Plain-node checks for the Worker's request routing (no test framework in
// edge/). Run: `node test/worker.test.mjs` from edge/. Mocks the R2 bucket and
// KV so fetch() can be driven end to end.
import assert from "node:assert/strict";
import worker from "../src/index.js";

const htmlObject = (body) => ({
  body,
  httpEtag: '"etag"',
  writeHttpMetadata(h) {
    h.set("content-type", "text/html; charset=utf-8");
  },
});

// Slug resolves to MEROVEXPRESS (no handle alias in KV → segment upcased).
const cssObject = (body) => ({
  body,
  httpEtag: '"etag"',
  writeHttpMetadata(h) {
    h.set("content-type", "text/css");
  },
});

const SHA = "0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9";
const store = {
  "sites/MEROVEXPRESS/pointer.json": { json: async () => ({ build_id: "PROD1" }) },
  [`sites/MEROVEXPRESS/builds/PROD1/css/06-sections.${SHA}.css`]: cssObject(".fk{}"),
  "sites/MEROVEXPRESS/builds/PROD1/css/legacy.css": cssObject(".old{}"),
  "sites/MEROVEXPRESS/preview/pointer.json": { json: async () => ({ build_id: "PREV1" }) },
  "sites/MEROVEXPRESS/builds/PROD1/index.html": htmlObject("<html>production</html>"),
  "sites/MEROVEXPRESS/preview/builds/PREV1/index.html": htmlObject("<html>draft preview</html>"),
};

const env = {
  SITES: { get: async (k) => store[k] || null, head: async (k) => store[k] || null },
  HOSTNAMES: { get: async () => null },
};

const call = (url, method = "GET") =>
  worker.fetch(new Request(url, { method }), env);

let passed = 0;
async function check(name, fn) {
  await fn();
  passed++;
  console.log("ok -", name);
}

await check("preview host redirects a slugged path to its trailing slash", async () => {
  const res = await call("https://preview.kindredquill.com/merovexpress");
  assert.equal(res.status, 301);
  assert.ok(res.headers.get("location").endsWith("/merovexpress/"));
});

await check("preview host serves the draft build with noindex", async () => {
  const res = await call("https://preview.kindredquill.com/merovexpress/");
  assert.equal(res.status, 200);
  assert.match(await res.text(), /draft preview/);
  assert.equal(res.headers.get("x-robots-tag"), "noindex");
});

await check("platform host serves production and is NOT noindexed", async () => {
  const res = await call("https://sites.kindredquill.com/merovexpress/");
  assert.equal(res.status, 200);
  assert.match(await res.text(), /production/);
  assert.equal(res.headers.get("x-robots-tag"), null);
});

await check("fingerprinted theme assets are immutable; unfingerprinted ones keep the day+SWR policy", async () => {
  const fp = await call(`https://sites.kindredquill.com/merovexpress/css/06-sections.${SHA}.css`);
  assert.equal(fp.status, 200);
  assert.equal(fp.headers.get("cache-control"), "public, max-age=31536000, immutable");
  const plain = await call("https://sites.kindredquill.com/merovexpress/css/legacy.css");
  assert.equal(plain.status, 200);
  assert.equal(plain.headers.get("cache-control"), "public, max-age=86400, stale-while-revalidate=604800");
  const html = await call("https://sites.kindredquill.com/merovexpress/");
  assert.equal(html.headers.get("cache-control"), "public, max-age=0, must-revalidate");
});

await check("preview host still trailing-slash redirects deep directories", async () => {
  const res = await call("https://preview.kindredquill.com/merovexpress/books");
  assert.equal(res.status, 301);
  assert.ok(res.headers.get("location").endsWith("/merovexpress/books/"));
});

// ---- dynamic islands ---------------------------------------------------
// Proxy tests capture the origin fetch instead of performing it.
const islandEnv = {
  ...env,
  RAILS_ORIGIN: "https://app.kindredquill.com",
  ISLAND_AUTH: "sekrit",
  HOSTNAMES: { get: async (k) => (k === "merovex.press" ? "MEROVEXPRESS" : null) },
};

let proxied;
const realFetch = globalThis.fetch;
globalThis.fetch = async (target, init) => {
  proxied = { url: String(target), init };
  return new Response("proxied", { status: 200 });
};

const island = (url, method = "GET") =>
  worker.fetch(new Request(url, { method }), islandEnv);

await check("platform-host island proxies the ORIGINAL prefixed path, not slash-mangled", async () => {
  proxied = undefined;
  const res = await island("https://sites.kindredquill.com/merovexpress/newsletter/confirm/tok123");
  assert.equal(res.status, 200); // proxied, NOT the trailing-slash 301
  assert.equal(proxied.url, "https://app.kindredquill.com/merovexpress/newsletter/confirm/tok123");
  assert.equal(proxied.init.headers.get("x-island-host"), "sites.kindredquill.com");
  assert.equal(proxied.init.headers.get("x-island-auth"), "sekrit");
});

await check("platform-host signup POST proxies with the prefix", async () => {
  proxied = undefined;
  await island("https://sites.kindredquill.com/merovexpress/newsletter", "POST");
  assert.equal(proxied.url, "https://app.kindredquill.com/merovexpress/newsletter");
});

await check("custom-domain island still proxies its own host and bare path", async () => {
  proxied = undefined;
  await island("https://merovex.press/newsletter", "POST");
  assert.equal(proxied.url, "https://app.kindredquill.com/newsletter");
  assert.equal(proxied.init.headers.get("x-island-host"), "merovex.press");
});

await check("buy-link click counter proxies to Rails' GET /buy/:id on a custom domain", async () => {
  proxied = undefined;
  const res = await island("https://merovex.press/buy/7");
  assert.equal(res.status, 200); // proxied, NOT an R2 404
  assert.equal(proxied.url, "https://app.kindredquill.com/buy/7");
  assert.equal(proxied.init.headers.get("x-island-host"), "merovex.press");
  assert.equal(proxied.init.redirect, "manual"); // the store 302 passes through untouched
});

await check("buy-link click counter proxies the prefixed path on the platform host", async () => {
  proxied = undefined;
  await island("https://sites.kindredquill.com/merovexpress/buy/7");
  assert.equal(proxied.url, "https://app.kindredquill.com/merovexpress/buy/7");
});

await check("buy island is GET-only and numeric-only — /buy/abc and POST fall through to static", async () => {
  proxied = undefined;
  await island("https://merovex.press/buy/abc");
  assert.equal(proxied, undefined);
  await island("https://merovex.press/buy/7", "POST");
  assert.equal(proxied, undefined);
});

await check("claim page proxies tokened GETs, bare /claim included, never slash-mangled", async () => {
  proxied = undefined;
  const res = await island("https://merovex.press/claim/tok123");
  assert.equal(res.status, 200); // proxied, NOT an R2 404
  assert.equal(proxied.url, "https://app.kindredquill.com/claim/tok123");

  proxied = undefined;
  await island("https://merovex.press/claim"); // stripped token → branded expired page
  assert.equal(proxied.url, "https://app.kindredquill.com/claim");
});

await check("claim download POST proxies, and its 302 to R2 passes through untouched", async () => {
  proxied = undefined;
  await island("https://merovex.press/claim/tok123/downloads", "POST");
  assert.equal(proxied.url, "https://app.kindredquill.com/claim/tok123/downloads");
  assert.equal(proxied.init.redirect, "manual"); // the presigned-URL 302 goes to the browser

  proxied = undefined;
  await island("https://merovex.press/claim/tok123/downloads"); // GET spends nothing → static
  assert.equal(proxied, undefined);
});

await check("claim renewal form POST and its sent page proxy, prefixed on the platform host", async () => {
  proxied = undefined;
  await island("https://merovex.press/claim_renewal", "POST");
  assert.equal(proxied.url, "https://app.kindredquill.com/claim_renewal");

  proxied = undefined;
  await island("https://sites.kindredquill.com/merovexpress/claim_renewal/sent");
  assert.equal(proxied.url, "https://app.kindredquill.com/merovexpress/claim_renewal/sent");
});

await check("preview host stays static-only — islands never proxy drafts", async () => {
  proxied = undefined;
  const res = await island("https://preview.kindredquill.com/merovexpress/newsletter", "POST");
  assert.equal(proxied, undefined);
  assert.notEqual(res.status, 200);
});

await check("docs subdomain passes through to Pages, path and query intact", async () => {
  proxied = undefined;
  await island("https://docs.kindredquill.com/guides/newsletter?q=1");
  assert.equal(proxied.url, "https://inkwell-support.pages.dev/guides/newsletter?q=1");
});

globalThis.fetch = realFetch;

// ---- apex tail ---------------------------------------------------------
await check("old apex newsletter links 301 to the sites host, path intact", async () => {
  const res = await call("https://kindredquill.com/MEROVEXPRESS/newsletter/unsubscribe/tok?b=7");
  assert.equal(res.status, 301);
  assert.equal(
    res.headers.get("location"),
    "https://sites.kindredquill.com/MEROVEXPRESS/newsletter/unsubscribe/tok?b=7",
  );
});

await check("other apex paths are the static site's business — plain 404 here", async () => {
  const res = await call("https://kindredquill.com/anything-else");
  assert.equal(res.status, 404);
});

console.log(`\n${passed} passed`);
