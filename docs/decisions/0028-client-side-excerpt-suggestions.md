---
type: decision
title: Client-side ML — excerpt suggestions run in the browser
status: accepted
tags: [composer, seo, ml, transformers-js, privacy]
created: 2026-09-02
updated: 2026-09-02
sources: [./0007-versioned-recordables.md]
---

# 0028. Client-side ML — excerpt suggestions run in the browser

## Context

Excerpts (`posts.excerpt`, ≤160 chars) are the SEO summary: meta description,
`og:`/`twitter:` descriptions, Article JSON-LD, and the Hugo export's
`.Params.excerpt`, all through `Post#summary`. Writing them is a chore authors
skip, so the field usually falls back to a blunt body truncation. We wanted a
model to draft one from the article — but production is a single box where
Solid Queue already shares CPU with Puma, posts are immutable versioned rows
the server should never write to on an author's behalf (ADR 0007), and draft
text leaving the browser is a privacy cost with no offsetting benefit.

## Decision

"Suggest excerpt" runs **Xenova/distilbart-cnn-6-6** (quantized ONNX, ~150 MB)
**in the author's browser** via transformers.js, inside a module Web Worker so
generation never blocks typing. The feature is optional and opt-in per
browser: the first click shows a consent row spelling out the one-time
download, that everything runs locally, and that the author can always write
the excerpt by hand; the choice is remembered in `localStorage`
(`alcovo/excerpt_suggest/consent`). Model weights cache once via the browser's
Cache API from huggingface.co.

transformers.js itself loads from a version-pinned jsdelivr URL rather than
`bin/importmap pin`: import maps don't reach workers, and vendoring the JS
would not remove the runtime wasm/weight fetches anyway. The pin must stay on
the 3.x line (currently 3.8.1) until the model's ONNX export is refreshed —
4.x bundles an onnxruntime-web whose QDQ→MatMulNBits transform rejects the
older quantized weights at session creation. The worker lives in
`public/` (served undigested; a `?v=` query on the worker URL is the cache
buster). The suggestion only fills the form field — the author reviews and
saves normally. **No routes, no migrations, no gems, no server state.**

## Consequences

- Draft text never leaves the browser; there is no inference infrastructure
  to provision, meter, or protect.
- Two runtime CDN dependencies (cdn.jsdelivr.net, huggingface.co). When either
  is unreachable the feature degrades to a status message and "write it by
  hand" — the composer itself is unaffected.
- Quality is capped at what a 150 MB summarizer can do: serviceable lead-biased
  meta descriptions, not prose. The output is a starting point behind a review
  step, never an automatic write.
- Precedent set: browser-cached models in a worker are the house pattern for
  small assistive ML.
