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
const store = {
  "sites/MEROVEXPRESS/pointer.json": { json: async () => ({ build_id: "PROD1" }) },
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

await check("preview host still trailing-slash redirects deep directories", async () => {
  const res = await call("https://preview.kindredquill.com/merovexpress/books");
  assert.equal(res.status, 301);
  assert.ok(res.headers.get("location").endsWith("/merovexpress/books/"));
});

console.log(`\n${passed} passed`);
