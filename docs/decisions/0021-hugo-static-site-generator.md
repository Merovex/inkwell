---
type: decision
title: Hugo renders the public sites — templates leave Rails
status: accepted
tags: [static-serving, hugo, phase-2, themes, r2]
created: 2026-07-29
updated: 2026-07-29
sources: [hugo-build-pipeline.md, phase-2-static-serving.md]
---

# 0021. Hugo renders the public sites — templates leave Rails

## Context

Phase 2 makes the public sites static files on R2 served by a Worker. The
phase-2 draft (§2.1–2.2 as originally written) planned to get there by
**extracting the existing Rails public views into plain ERB**, rendered
outside the request cycle by a Rails-side `SiteRenderer` — the fastest path,
reusing working templates and enabling a near-free byte-level HTML diff at
cut-over.

But per-tenant themes are a product feature of the SaaS, not a nicety: each
account references a theme name + version, theme upgrades are cohort
migrations, and presentation knobs are per-site data. An ERB v1 keeps
presentation inside Rails (every theme change is a deploy) and guarantees a
second template rewrite later — performed while live tenants are serving.
The engine question had to be settled before theme work started, because
templates are being pre-built (owner-authored, separate repo) in parallel
with the Rails pipeline work.

## Decision

**Hugo renders the public sites.** Rails exports each tenant's published
records as a versioned JSON contract into a per-build workspace; a pinned,
vendored Hugo binary (extended build, ≥ 0.126 for content adapters) renders
it against a pre-baked, versioned theme; the output syncs to an immutable
per-build R2 prefix and goes live via a pointer flip. Full design:
[[hugo-build-pipeline]].

The load-bearing properties:

- **Templates fully outside Rails.** Themes live in their own repo,
  versioned by tag; Rails knows nothing about presentation, Hugo nothing
  about the database. The JSON contract (`contract_version`) is the only
  coupling.
- **Content adapters, not stubs.** Themes materialize pages from the JSON
  (`_content.gotmpl`); Rails emits no markdown and no per-page files —
  structural knowledge stays out of Rails.
- **Bodies pre-rendered in Rails.** Rich-text bodies cross as sanitized
  `body_html` fragments, so admin preview and published fragment share one
  renderer and Hugo needs no sanitizer.
- **Author-authored templates stay a non-goal.** Go templates are not a
  sandbox; themes are first-party and pre-baked. If author templates ever
  become a requirement, that is a new design (and a different engine).

## Consequences

- **Easier:** theme versioning and cohort migration per account;
  deterministic builds (same JSON + theme = byte-identical output); no
  second template rewrite under live tenants; sub-second renders keep
  full-rebuild-per-publish trivially cheap at any plausible scale.
- **Harder:** the cut-over byte-diff against Rails-rendered HTML is dead —
  replaced by a semantic diff (text, links, meta, feeds) over the full
  sitemap ([[hugo-build-pipeline]] §11). Layout-level preview requires the
  pipeline (only the `body_html` fragment is shared with the admin).
  Go templates are less familiar than ERB. A vendored binary (pinned by
  checksum) joins the deploy. Contract changes require versioning
  discipline on both sides.
- **Amendments:** phase-2 §2.1–2.2 (ERB extraction → Hugo theme + pipeline)
  and §2.3–2.4 (manifest-last → pointer-flip) amended in place with markers.
  Phase 2 likely runs longer than the ERB path would have; accepted — the
  invariant ("no tenant #2 before static serving ships") holds regardless
  of engine.

## Alternatives considered

- **ERB extraction (the phase-2 draft)** — fastest to the invariant lift and
  a free byte-diff cut-over check, but presentation stays a Rails deploy
  concern and the Hugo migration happens later, under live tenants. Rejected
  because themes-per-tenant is core product, not speculation.
- **Jekyll** — Liquid's sandbox only matters for author-authored templates
  (a non-goal); brings a Ruby gem environment onto the build path and
  10–50× slower builds.
- **Zola** — no content-adapter equivalent, so Rails would emit per-page
  stubs, moving structure back into Rails; Tera's niceness doesn't pay for
  that coupling.
- **Cloudflare Pages builds** — repo-per-project model and quotas collapse
  at multi-tenant scale; Cloudflare stays the serving layer only.

## Links

Related: [[hugo-build-pipeline]] · [[phase-2-static-serving]] ·
[[merovex-press-public-site]] · [[public-image-handling]] ·
Supersedes: — (amends phase-2-static-serving.md §2.1–2.4) · Superseded by: —
