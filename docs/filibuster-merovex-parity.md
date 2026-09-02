# Filibuster ↔ Merovex Press — Parity Gap Analysis

**Date:** 2026-07-31
**Status:** Active — findings + open questions; requirements confirmed by owner are marked. Theme deltas shipped 2026-07-31 are recorded in §5.

*Comparison of the live Rails public views (`../app/views/{pages,blog,books,authors}`, `layouts/public.html.erb`, the `press-*.css` family) against what the `filibuster` theme (kindred-quill repo) renders. Question: what must change so the current merovex.press public theme is captured by (or at least representable in) filibuster before the Phase 2 cut-over.*

Related: [hugo-build-pipeline.md](hugo-build-pipeline.md) (the pipeline + §4 JSON contract + §6.1 design axes), [phase-2-static-serving.md](phase-2-static-serving.md) (delivery plan + §2.6 semantic-diff cut-over), [site-designer.md](site-designer.md) (the SiteDesigner + foundation pass; ADR 0022), [[merovex-press-public-site]] (the Rails public front-of-house as built).

---

## 0. The framing decision (open)

Phase 2's exit criterion is a **semantic** diff — text, links, meta — not pixels. Two legitimate targets:

1. **Pixel-faithful:** merovex.press looks identical after cut-over → the press design becomes new axis options + a "Merovex" preset in filibuster.
2. **Content parity, new design:** merovex adopts an existing filibuster permutation; only content/URLs must survive.

Owner has not yet chosen. Everything in §1 exists only under target 1; §2–§4 apply under either target.

**Guardrail either way:** merovex-specific additions must be genuine *permutations* other tenants could pick (a palette, a hero variant, a section type) — not a `data-palette="merovex"` special case — or filibuster stops being a permutation engine.

## 1. Design-language gaps (the look itself)

- **Palette.** Merovex is pine (muted teal) + mountain-mist neutrals as `light-dark()` pairs with a **reader-facing light/dark/auto toggle** (`press_theme` cookie, default dark, resolved via `color-scheme`). All five filibuster palettes are single-mode; readers get no toggle. Needs a new palette **and** a structural decision: is dual-mode a property of certain palettes, or an orthogonal capability of every palette? The toggle is static-compatible (pure client-side cookie + attribute swap) but would be the **first JS filibuster ships in a reader build** — breaking the current "readers get zero JS" property. Deliberate call required.
- **Typography.** Archivo Narrow display + Merriweather body, **self-hosted variable fonts** — not among the 13 Google-Fonts pairings. Needs a new pairing plus a policy decision: filibuster loads Google Fonts; merovex deliberately self-hosts (perf + privacy). Related: the temporary `press_hfont` audition toggle should be resolved (winner picked, toggle deleted) before the pairing is frozen.
- **Hero.** Merovex: split copy + circular-ring author portrait over a full-bleed *photographic* backdrop with attribution credit, plus real LCP engineering (AVIF srcset 500w/1000w, preload, fetchpriority). Filibuster's seven hero variants derive backdrops from avatar/covers only — no custom backdrop image, no credit, no ring. Needs a new hero variant + contract fields (hero image, credit).
- **Home sections.** Merovex home = hero → cover **overflow scroller** → **genre cards** (one per pen name: kicker/heading/blurb). Filibuster's slot engine has hero/books/posts/bio/newsletter — no scroller, no genre/author cards. Genre cards naturally generalize to "one card per author" (ties to §2 multi-author).
- **Chrome.** Nav CTA links a real `/newsletter` page (filibuster: mailto); footer carries logo mark + conditional Privacy/Terms + RSS links; site logo is an upload with SVG-mark fallback — the contract has **no logo field**. Merovex ships Turbo Drive + a page fade; static sites probably drop Turbo (CSS-only fade or nothing).

## 2. Structural / page-inventory gaps

- **Multiple authors — REQUIRED (owner, 2026-07-31).** Merovex Press is a *press*: two pen names, per-author public pages (`/authors/:slug`: bio, their books, their posts, Person JSON-LD), bylines on posts, per-author home cards. The contract's `author.json` is singular ("the active pen-name persona"); filibuster renders one author everywhere **including JSON-LD on every page type**. This is a contract-version change: authors as a list, author attribution on books/posts, an authors content adapter, and rework of every single-author assumption (hero, bio, newsletter band, home/book/series JSON-LD).
- **Books index — REQUIRED (owner, 2026-07-31); shipped, §5.** `/books` ("The Library"): grouped by series with blurbs + a Standalone group.
- **Series index + show — REQUIRED (owner, 2026-07-31); shipped, §5.** Series show already existed (`series/page.html`); the index was a generic-fallback stub.
- **Posts vs blog URLs.** Merovex: `/blog`, `/blog/:id` (id-first slugs, ADR 0010), `/blog/feed`. Filibuster: `/posts/`. Owner: books/series pages are required *"whether it's 'posts' or blog"* — i.e. the naming question itself is still open. Inbound links, SEO, and **links in already-sent newsletters** argue for byte-equal URL parity (contract-driven section path) with Worker redirects only as a safety net.
- **Newsletter + contact form pages.** `GET /newsletter` and `GET /contact` are **not** in the Phase 2 dynamic-island allowlist — only their POSTs and token links are. The form pages must become static theme pages POSTing to the proxied islands → contract needs form-action config, and the honeypot (invisible_captcha, server-rendered today) needs a static-compatible answer.
- **Proxied-page styling seam.** sent/confirmed/unsubscribed/kept/invalid-token pages stay Rails-rendered through the proxy — they will render in the old Rails press layout inside a filibuster-styled site. Decide: neutral/brand-matched minimal layout, or accept the seam.
- **Legal pages.** `/privacy`, `/terms` render Site rich texts, footer-linked conditionally. Contract carries only `description_html`.
- **SEO surfaces.** Feed/sitemap/robots parity: Hugo's built-ins emit `index.xml`/`sitemap.xml` at different paths with different shapes than `/blog/feed`, `/sitemap`, `/robots.txt`. Per-page detail: Article JSON-LD + byline links + meta descriptions on posts; OG image from author avatar on author pages.
- **Buy links.** Parity argues for keeping `/buy/:id` (it's what's indexed) — which would settle [hugo-build-pipeline.md](hugo-build-pipeline.md) §11's open `/out/:track_id` question and drop `track_id` from the contract.

## 3. The Rails-side prerequisite (easily missed)

Much of merovex.press's identity is **hardcoded in ERB and `app/assets`, not in the database**: the hero headline ("Worlds break. People don't."), the lede, both genre-card blurbs, the headshot images, the Unsplash backdrop + credit, the blog/books index headings and ledes. The exporter can only export what `Site`/`Author` records hold. Capturing the theme therefore requires a Rails content-migration step first: grow Site (and Author) + the admin settings UI to hold hero copy/imagery, section copy, and legal text, then move the hardcoded content in. Without it the theme work has nothing to render.

This also forces **[hugo-build-pipeline.md](hugo-build-pipeline.md) Open Question 4 (image pipeline)**: the hero's LCP treatment and the scroller need responsive AVIF variants; someone (Rails variants or Hugo) must produce them.

## 4. Open questions (the running list)

1. Fidelity target: pixel-faithful vs content-parity redesign (§0).
2. ~~Dual-mode palettes / reader theme toggle~~ **Resolved 2026-07-31** ([site-designer.md](site-designer.md) §4): `mode` becomes the eighth axis (`light | dark | auto`) with all palette tokens as `light-dark()` pairs; `auto` resolves the visitor's OS preference via `color-scheme` with **zero shipped JS**. A visitor-facing toggle *button* is not shipped (deferred indefinitely). Counterpart-mode palette design deferred until the palette vocabulary settles (palettes declared provisional, owner 2026-07-31).
3. Fonts: self-hosted in the theme vs Google Fonts; which pairing wins the `press_hfont` audition?
4. Section path naming: `/posts/` vs `/blog/` — contract-driven? URL parity vs redirects.
5. Static form pages: honeypot mechanism; form-action config in the contract.
6. Proxied Rails pages: style-match story.
7. Image pipeline (pipeline doc Open Q4) — forced by hero/scroller parity.
8. `/buy/:id` vs `/out/:track_id` (pipeline doc §11) — parity favors `/buy/:id`.
9. Contract shape for multiple authors: `authors.json` list + `author_slug` on books/posts? What replaces the singular `author.json` consumers (hero, bio, newsletter, JSON-LD)?
10. Section copy ("The Library", index ledes, genre-card text): contract fields vs theme defaults — the semantic diff will flag every difference, and merovex's hero copy *must* travel as data or it's lost.
11. Logo: contract field + fallback behavior.

## 5. Theme deltas shipped (kindred-quill repo, 2026-07-31)

- **`/books/` library page** (`layouts/books/section.html`): cover grids grouped by series in `series.json` order (linked series title + blurb excerpt), then a **Standalone** group (publication-date desc) for books whose `series_slug` is empty or unresolvable. Replaces the generic flat title-list fallback.
- **`/series/` index** (`layouts/series/section.html`): one series card per series — same `series-card` partial as the home books section, so the `cards` axis applies. Previously a branch inside the shared `section.html` (now posts + generic fallback only).
- **Nav + breadcrumbs point at the real pages:** header "Books" → `/books/` (aria-current on books *and* series sections); series-page breadcrumb `/#books` → `/books/`; standalone books crumb through `/books/` — fixing a latent bug where BreadcrumbList JSON-LD emitted a broken `/series//` URL for series-less books. Home hero's `/#books` anchor unchanged (same-page anchor).
- **CSS:** new `.fk-library-*` / `.fk-cover-grid` block in `site.css` (axis-neutral base component, composes with all palettes).
- Verified: reader + preview builds render both pages; standalone grouping and breadcrumbs exercised in a temp workspace (dev payload has no standalone books). Theme README's "What renders where" table updated.
- **Not done, deliberately:** multi-author support (contract change, §2/§4 Q9), everything in §1, and the remaining §2 items — deferred per owner ("we'll come back to some of the other information later").
