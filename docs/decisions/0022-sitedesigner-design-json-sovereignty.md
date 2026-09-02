---
type: decision
title: SiteDesigner + design.json sovereignty — the switcher is retired
status: accepted
tags: [phase-2, hugo, theme, design, sitedesigner]
created: 2026-07-31
updated: 2026-07-31
sources: [../filibuster-merovex-parity.md, ../site-designer.md]
---

# 0022. SiteDesigner + design.json sovereignty — the switcher is retired

## Context

Filibuster shipped with a preview-only, in-page "design switcher" (FAB +
cookie + pre-paint bootstrap) that let a viewer cycle axes client-side. It was
built for exploration. A teardown of a competitor's website designer
(2026-07-31, [[site-designer]]) established what the real authoring surface
looks like: a Rails-side editor with a live preview iframe, option cards, and
per-module panes. The owner ruled: the switcher must never be the mechanism;
readers never mutate design; the author designs in the admin and the result is
a static, immutable site rebuilt on every design or content change.

## Decision

1. **The design block (`design.json`) is the single source of design truth.**
   Every build — preview or reader — bakes the design into `<html>` at build
   time. No client-side design mutation exists in any build mode. The
   switcher (switcher.html, switcher.js, `fk_prefs` cookie, pre-paint
   bootstrap) is deleted from filibuster, not gated off.
2. **The authoring surface is the SiteDesigner** (canonical name), a Rails
   admin editor that edits the Site draft and writes the design block. Its
   architecture is specced in [[site-designer]].
3. **One renderer, ever.** Rails never renders site markup — not previews,
   not partial mockups. The designer's live preview is a real Hugo build of
   filibuster served in an iframe from a local build directory (no
   deployment). Rail pickers use static wireframe SVGs and manifest metadata,
   never re-implemented markup.
4. **`params.preview` is reserved** for designer-facing affordances in the
   preview iframe (module anchors, edit affordances) — it never varies the
   design.
5. **The hero keeps its name** ("hero", not "spotlight"), and grows by
   partial-per-variant dispatch; every build renders exactly one hero partial.

## Consequences

- The preview/reader dual-build machinery collapses: no cookie, no bootstrap
  script, no switcher bytes anywhere; reader builds ship zero design JS.
- "Instant preview" is replaced by the debounced rebuild loop — the use case
  the sub-second-build invariant was bought for. Design-only rebuilds are the
  cheapest builds in the system.
- The theme ↔ designer sync problem reduces to one artifact: the JSON
  contract + `theme.json` manifest, enforceable by a CI gate (exporter output
  must build against the pinned theme), not by keeping two markup
  implementations aligned.
- The hugo-build-pipeline §6.2 preview/switcher design (cookie source,
  postMessage save path) is superseded; the pipeline doc is amended.
- The SiteDesigner needs draft-design semantics; the Site recordable's
  existing draft/publish spine supplies Save/Discard for free.

## Alternatives considered

- **Keep the switcher as the designer's preview mechanism** (client-side axis
  flipping for instant feedback) — rejected: it forces superset markup for
  every variant forever, ships a second design-application code path, and
  contradicts design.json sovereignty. Rebuild-on-change is fast enough.
- **Rails-rendered preview components** (designer renders its own element
  previews) — rejected: two renderers drift; sync becomes a permanent chore.

## Links

Related: [[site-designer]] · [[filibuster-merovex-parity]] ·
[[0021-hugo-static-site-generator]] · Supersedes: the §6.2 switcher design in
[hugo-build-pipeline.md](../hugo-build-pipeline.md) · Superseded by: —
