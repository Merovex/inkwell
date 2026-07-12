---
type: concept
title: Merovex Press public site (front-of-house)
status: active
tags: [public-site, hotwire, css, routing]
created: 2026-07-08
updated: 2026-07-12
sources: [../decisions/0010-id-first-public-slugs.md]
---

# Merovex Press public site (front-of-house)

## Summary
The app wears two faces on one codebase: **Inkwell** (the authenticated admin
at `/admin/*`) and **Merovex Press** (the anonymous public site at `/`). The
public side has its own layout, controllers, and stylesheet, sharing only the
color-token scales with the admin.

## Details
- **Controllers** — `PublicController` (base): `allow_unauthenticated_access`,
  `layout "public"`, and a public-styled `render_not_found`. Subclasses:
  `PagesController#home`, `BlogController` (index + `/blog/:id-slug` article),
  `BooksController` (index grouped by series + `/books/:id-slug` detail with
  distributor buy buttons). See `../../app/controllers/public_controller.rb`.
- **Layout** — `layouts/public.html.erb`: nav (Merovex mark + Home/Books/Blog/
  About + newsletter CTA) and footer, loading only `01-tokens.css` + `press.css`
  (not the admin `:app` bundle).
- **Styling** — `press.css`, everything scoped under a `.press` body class.
  Propshaft's `:app` globs `app/assets/**/*.css`, so `press.css` also loads on
  admin pages; the `.press` scope keeps it inert there. Public semantic tokens
  (`--surface-*`, `--text-*`, `--link-color`, serif/sans fonts) live on `.press`,
  mapping to the shared syō-ro / mountain-mist scales in `01-tokens.css`
  (see [[theme-background-colors]]). Repeated looks (page shells, display type,
  text roles, card surfaces) are composable classes in `press-utilities.css` —
  views compose these instead of minting per-page `__` classes; component files
  keep only real behavior.
- **Fonts** — all self-hosted woff2 (`app/assets/fonts/`): Source Serif 4 /
  Source Sans 3 (body), **Archivo Narrow** (variable 400–700; headings + nav,
  chosen by a July 2026 audition — the harness is parked in `press-hfont.css`),
  and **Federo** (single-weight 400; the `.wordmark` brand utility — 800 is
  synthesized).
- **Theme** — the public site cycles light → dark → auto via its own
  `press_theme` cookie (default **dark**), independent of the admin `theme`
  cookie. The layout renders `<html data-theme>` server-side (no flash); the
  cycler is event-delegated in `public.js` so it survives Turbo body swaps.
- **URLs** — id-first slugs, see [0010](../decisions/0010-id-first-public-slugs.md).
- **Error pages** — branded, self-contained static files `public/*.html`
  (400/403/404/406/422/500/503), since a real error means the app/asset pipeline
  may be down.

## Gotchas / open questions
- A **new** asset dir (e.g. `app/assets/fonts/`) needs a dev-server restart
  before Propshaft registers it and rewrites `url()`s.
- The `<%# locals: (...) %>` strict-locals magic comment can't carry trailing
  prose on the signature line — it breaks parsing (put prose on the next line).
- Public author/series pages are still stubbed (newsletter + About shipped
  2026-07-09).
- Book detail ends with a cached "More in <series>" section per published
  series (other published books only); the series list joins the `fresh_when`
  etag.
