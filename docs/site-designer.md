# SiteDesigner — Design Plan

**Date:** 2026-07-31 (drafted; revised same day: schema-lab-first order, Hugo pinned, frame v1 built)
**Status:** Active design doc; decisions ratified in [ADR 0022](decisions/0022-sitedesigner-design-json-sovereignty.md). Informed by a full teardown of a competitor's website designer (owner exploration, 2026-07-31). **Frame v1 is built** (§6).

*The SiteDesigner is the Rails admin surface where an author designs their
public site. It edits the Site draft, produces the design block
(`design.json`), and shows a live preview that is a real filibuster build in
an iframe. Build order agreed with owner; work proceeds top-to-bottom,
section by section, against the real (production-copy) database.*

Related: [hugo-build-pipeline.md](hugo-build-pipeline.md) (pipeline + contract + §6.1 axes), [filibuster-merovex-parity.md](filibuster-merovex-parity.md) (theme gap analysis), ADR 0021 (Hugo), ADR 0022 (design.json sovereignty).

---

## 1. Governing principles (owner rulings, 2026-07-31)

- **design.json is the single source of design truth.** Baked into `<html>`
  at build time, every build. No client-side design mutation; the switcher is
  deleted (ADR 0022). Readers never change layout.
- **One renderer.** Rails never renders site markup. The only live preview is
  a Hugo build of filibuster in an iframe. "Designer elements identical to
  Hugo's" is achieved by never duplicating them.
- **One CSS file** (`filibuster/static/assets/css/site.css`) covers all
  permutations and is shared automatically — the preview iframe *is* theme
  output. Rail chrome uses Inkwell admin CSS; `site.css` appears only inside
  the iframe.
- **The hero is the hero** (competitor's "spotlight" concept maps to it).
- **SiteDesigner** is the canonical name.
- **The five palettes are provisional** — expected to change as the designer
  takes shape. Mechanism work (mode pairs, tokens) proceeds now; polishing
  palette-mode renditions waits for the vocabulary to settle.

## 2. Architecture

### 2.1 The sync mechanism: manifest-driven everything

`theme.json` (the theme manifest) is the meeting point. The designer renders
its rail *from* the manifest; the exporter validates *against* it; the theme
renders *by* it. Adding a variant to filibuster (partial + manifest entry +
wireframe) surfaces it in the designer with zero Rails changes. Manifest v2
adds per-option metadata:

- `wireframe` — path to an abstract gray-box SVG shipped in the theme
  (`static/assets/wireframes/<axis>/<option>.svg`). Wireframes for layout
  variants (evergreen); rendered screenshots only for whole-page choices
  (hero variants, presets).
- `group` — facet for large galleries (hero: one-book / multi-book /
  image-text; presets: genre/vibe/focus tags).
- `tier` — free/pro. The theme is tier-blind (renders any validated JSON);
  Rails enforces at save. Pickers badge from this field.
- `needs` — per-option required/accepted content fields (e.g. a hero variant
  `needs: [image]`). Three consumers: exporter validation (fail loudly at
  export), designer field-reveal (show exactly the relevant subset per
  variant — the competitor's "superset of fields, reveal per-variant"
  pattern, driven from data), and partial documentation.
- Picker display metadata where the rail needs it: palette swatch colors,
  font family names (so font cards render in their typefaces). Accepted
  duplication with CSS truth; CSS renders, manifest describes. Lint later.

**Sync gate:** CI runs the exporter against the dev DB and builds with the
pinned theme. Designer-side changes that emit JSON the theme rejects (or
vice versa) fail CI. Sync by gate, not vigilance.

### 2.2 Save semantics: localStorage now, a JSON TEXT field on Save later

*(Revised 2026-07-31, owner direction: schema-lab first.)* While the
design.json schema is being discovered, the working design lives in
**localStorage — explicitly scaffolding**, per-browser, invisible to the
exporter, deleted when Save exists. Nothing persists server-side; the
preview endpoint is stateless (§2.3).

When the schema settles, **Save** writes the localStorage JSON to a TEXT
column holding the design JSON. Owner suggested the account profile;
recommendation on the table: put it on the **Site recordable** instead —
design changes then ride the existing draft/publish spine (Discard = drop
draft changes, Save/Publish = the publish transition that already enqueues
builds, history for free). Decide at graduation; the rail, manifest, and
build loop are unchanged by the choice.

### 2.3 The preview loop: a Hugo build in an iframe, no deployment

- Edit → Site draft updated → debounced preview build: exporter serializes
  **draft design + current published content**, Hugo renders to a local
  preview directory (sub-second).
- Rails serves the directory statically on an **authenticated admin route**;
  the iframe points there. Same host as admin: no CORS, no frame-ancestors
  issues. The generated `hugo.toml` sets `baseURL` to the preview mount path
  so in-iframe navigation and assets resolve — the author can click through
  their whole site.
- Iframe reloads on build completion (Turbo Stream ping; rides the planned
  build-status UI). Desktop/mobile toggle = iframe width. Mobile width is
  the **default** preview state (mobile-first discipline, §4).
- Requires none of the unbuilt Phase 2 tail (R2/Worker/Publisher): exporter +
  Hugo + a static-serving route. The designer becomes the daily proving
  ground for the exporter and theme ahead of cut-over.
- UX latency target: edit → refreshed iframe ≤ ~3s including debounce.
- Draft-*content* preview is a later, separate feature; design preview uses
  the database's published content ("the data that's in the database").
- Design-only rebuilds skip asset/image sync (nothing but HTML changes) —
  the designer loop is faster than a content publish.

### 2.4 The rail (the Rails UI proper)

Two-pane shell: left ~2/3 preview iframe (scaled), right rail. From the
teardown, the parts worth copying directly:

- **Pane navigation without routes:** nested collapse targets with explicit
  back buttons (competitor did it in two Stimulus controllers; that is the
  right scale).
- **`design_option_card`** — one component: hidden radio + label-as-card +
  wireframe + optional pro badge; selection styled off `:checked`.
- **One dirty-tracked form** wrapping the whole rail; global Save/Discard
  disabled until dirty (maps to the Site draft, §2.2).
- **Canvas ↔ rail linking:** preview-build-only module anchors
  (`id="<key>-module"`) for rail→canvas scroll; later, preview-only edit
  tabs on each module postMessage rail-pane jumps (canvas→rail). Both gated
  on `params.preview` — which after ADR 0022 exists *only* for these
  affordances.
- Rail blocks (teardown-mapped): Hero (customize + change gallery), Site
  Styles (nav/header, font, palette, **mode**), Page Sections (per-section
  presentation + visibility + content fields), Section Order (up/down over
  `home.sections` order).

### 2.5 Contract implications (batch as ONE bump with multi-author)

- `design` splits into its own file: **`data/design.json`** (cleaner diffs;
  design-only rebuild detection).
- `home.sections` becomes objects: `{ key, presentation, visible }` (order
  UI needs hidden-but-present sections; presentations become per-section).
- Hero content block (all optional; derivations remain the defaults):
  headline, body_html, image + credit, featured_book / featured_series,
  book_count, standardize_covers.
- Nav block (links: label/visible/order; optional CTA button), logo/banner
  fields; newsletter fields (image source, headline/body, confirmation
  copy). Per [filibuster-merovex-parity.md](filibuster-merovex-parity.md)
  §2/§4.
- `mode` axis (§4). Multi-author (parity REQUIRED item) rides the same bump.

## 3. Element inventory (teardown-derived targets)

What "done" looks like per module, scaled to filibuster's axis system.
Competitor counts in parens as ambition markers, not commitments:

| Module | Filibuster today | Target mechanism |
|---|---|---|
| Hero (23 variants, faceted gallery, per-variant content fields) | 7 CSS variants, derived content | Partial-per-variant dispatch (`hero/<option>.html`), `group` facets, `needs`-driven fields |
| Books section (5) | cards axis, 5 | Same pattern; carousel variant raises the reader-JS policy question |
| Biography (11, structural) | avatar shape (4) × side (2) | Add a `bio` *structure* axis; keep shape/side factored beneath it |
| Email collection (7 + copy/image editors) | newsletter axis, 2 | Grow options + contract fields |
| Header/nav (4 + links editor + CTA) | hardcoded | New `nav` axis + nav content block |
| Font (22 pairings + custom) | 13 pairings | Same mechanism; custom = closed-vocab escape hatch, deferred |
| Palette (15 three-token themes + custom) | 5 rich-token palettes (provisional) | Keep rich tokens; custom via seed-tokens + color-mix derivation, deferred |
| Updates/Blog presentation (2 each) | posts only | Per-section `presentation`; updates-vs-blog is an open content-type question |
| Section order/visibility | `home.sections` list | Section objects (§2.5) |
| Templates (faceted, screenshot cards) | 5 presets, derived | Presets + `group` facets in manifest; stay derived-not-stored |

## 4. Filibuster foundation pass (before section-by-section work)

1. **Switcher removal** — DONE 2026-07-31 (ADR 0022): partial, JS, cookie
   bootstrap, CSS block deleted; READMEs and dev workspace updated.
2. **CSS restructure into cascade layers**, one shipped file, mirroring the
   admin's layer philosophy: `reset` → `tokens` (font pairings + palettes +
   mode, all custom-property definitions keyed off `data-*`) → `base`
   (element defaults) → `components` (one block per element, each component's
   axis-conditional rules adjacent to it) → thin `utilities` tail.
3. **Mode axis**: `mode: light | dark | auto` as the eighth axis
   (`data-mode`). Tokens become `light-dark()` pairs; `light`/`dark` pin
   `color-scheme`; `auto` = `color-scheme: light dark` — visitor's OS
   preference resolves natively, **zero JS shipped**. Rules: every palette
   token defined once as a pair; no raw color below the tokens layer;
   `--hero-bg` gradients and shadows carry per-mode stops. Real cost is
   design: each palette needs a designed counterpart mode + per-mode WCAG
   re-verification — **deferred until the palette vocabulary settles**
   (palettes are provisional); the mechanism lands now with provisional
   counterpart values.
4. **Mobile-first audit**: base styles target narrow viewport; `min-width`
   queries layer up; prefer intrinsic layouts (auto-fill grids, flex-wrap,
   clamp scales) over breakpoints; the 2–3 surviving breakpoints become
   named tokens. Process hooks: mobile iframe width is the designer's
   default preview; hero variants' `needs` review includes narrow-viewport
   behavior explicitly.
5. **Manifest v2** (§2.1) + the contract bump (§2.5).

## 5. Build order  *(revised 2026-07-31 — schema-lab first, per owner)*

1. Switcher removal (done) + docs (done).
2. **SiteDesigner frame as the schema lab** (done — §6): two-pane shell,
   localStorage design state, debounced stateless preview builds, rail
   generated from today's manifest. The designer is the instrument that
   *discovers* the design.json schema; the manifest evolves in lockstep
   with every schema experiment (guardrail §1).
3. **Section-by-section, top of page downward** (header/nav → hero → books →
   bio → newsletter → footer), each iteration: vocabulary in manifest →
   partial(s) + axis CSS → designer pane fields per `needs` → verify in
   preview against real data. The filibuster foundation pass (§4: layers,
   mode axis, mobile audit) lands early in this loop since every section
   builds on tokens.
4. **Contract bump after schema convergence** (was step 2): design.json
   split, section objects, fed-hero/nav/newsletter fields, multi-author —
   one batched break, formalized from what the lab settled on.
5. **Save graduation**: localStorage → the design TEXT field (§2.2),
   deleting the scaffolding.

**Toolchain pin (2026-07-31):** Hugo **0.164.0 extended**, pinned in both
places — mise (`~/Work/.mise.toml`, was `latest`) and the Dockerfile
(ARG + sha256, installed into the base stage; verified in-image). An
upgrade is a deliberate two-pin diff.

## 6. As built — frame v1 (2026-07-31)

Rails side (all green: 398 tests, rubocop clean):

- **Toolchain**: Hugo 0.164.0 in the Docker base stage (checksummed tarball;
  `ruby:slim` already ships the libstdc++ Hugo extended needs — verified
  in-image); `config/initializers/hugo.rb` (`HUGO_BIN` from env, PATH
  fallback for dev; `THEME_PATH` defaulting to the sibling filibuster
  checkout). `BUILDS_PATH` defaults to `tmp/builds` outside production.
- **`Theme`** (`app/models/theme.rb`): the manifest PORO — axes, presets,
  per-axis defaults, and `permit!` (slices unknown keys, raises
  `InvalidDesign` on unknown values — the §6.1 export gate, live).
- **`Exporter`** now assembles the *whole* workspace: data JSON + generated
  `hugo.toml` (baseURL/title/theme/params, the one place Rails writes
  Hugo-facing config) + theme symlink; takes `design:` (validated,
  merged over manifest defaults — `DESIGN_DEFAULTS` deleted), `base_url:`,
  `preview:`.
- **`Renderer`** (`app/models/renderer.rb`): the §5.2 invocation as
  designed — Open3, `nice -n 10`, `--minify --panicOnWarning`, **no
  `--quiet`** (stderr is the failure reason), 30s timeout,
  `--cleanDestinationDir` option for the rebuilt-in-place preview.
- **Routes/controllers**: `/admin/designer` (`Admin::DesignersController`),
  `POST /admin/designer/preview` + `GET /admin/designer/preview/(*path)`
  (`Admin::Designers::PreviewsController`) — stateless build-from-payload,
  ephemeral workspaces, traversal-guarded file serving.
- **View + rail**: generated entirely from `Theme#axes`/`#presets` (option
  chips as hidden-radio cards, preset buttons, derived preset label,
  reset); mobile-width iframe is the default preview state;
  `designer_controller.js` (Stimulus) owns localStorage, 500ms debounce,
  build status line, in-situ iframe reload. `designer.css` in the admin's
  layer system.
- **Round-trip proven in tests**: POST a design → real export → real Hugo
  build → served HTML carries the posted axes baked into `<html>` (~0.6s
  including the full suite's share).

Theme side (kindred-quill repo), forced by the preview and latent in
production: **filibuster was not baseURL-safe** — ~38 hardcoded
root-relative URLs (`href="/books/…"`, CSS link, covers) plus
leading-slash `absURL` calls would have broken not just the preview iframe
but the planned **apex slug serving** (`kindredquill.com/{SLUG}/…`). All
converted to `site.Home.RelPermalink`/`relURL`; verified zero unprefixed
theme URLs under a prefixed build (authored links inside `body_html`
content are the author's own and correctly untouched). Also fixed while
exposed by fixture data: nil tagline rendered `%!s(<nil>)` in `<title>`;
missing author avatar rendered an empty-src portrait.

**CI caveat**: exporter/designer tests need the filibuster checkout beside
the app, and preview tests need Hugo; designer tests skip gracefully when
absent, but exporter tests now require the theme. Wiring CI to check out
kindred-quill + install the pinned Hugo *is* the §2.1 sync gate — do it
before relying on green CI.

### 6.1 Section-by-section status (2026-07-31 end of day)

The top-to-bottom loop (§5.3) has completed FOUR sections; the log carries
the blow-by-blow. The designer's control vocabulary settled into three
generic, manifest-driven types: **chips** (visual options; wireframe or
font-specimen or swatch cards when options carry metadata), **switches**
(boolean-ish axes, `toggle_labels` in the view), **sliders** (ordered
scales, currently `corners`). The theme is at TWELVE axes / ~47M
combinations (see filibuster README).

- **Header — done**: `nav` axis (4 layouts, wireframe cards), data-driven
  links + CTA button (three states) via modal editors, logo upload
  (drag-drop, title-as-alt or visible-lockup) persisting to the Site
  attachment, `site.json` gains `nav` + `logo`.
- **Palette — done**: 15 dual-mode palettes (generator-derived
  `light-dark()` pairs; Pine = the merovex look, a parity milestone),
  `mode` axis living INSIDE the palette pane, genre-grouped swatch cards,
  and the custom escape valve: color-wheel (spectral outer ring, muted
  inner ring) + free hex, resolved by `PaletteColor`'s OKLCH lightness
  policy (authors pick hue; WE drive L per role/mode — a11y structural).
- **Fonts — done**: 21 pairings as specimen cards grouped by genre;
  custom escape valve via `font_picker` typeahead over the vendored
  Google Fonts list (`GoogleFonts` allowlist guards the theme `<head>`).
- **Books — done**: 7 card layouts (dossier removed) with hand-drawn
  wireframes, `catalog` (series/books scope) + `alternate` (row flip) as
  switches, `corners` cover-rounding slider (Open Props stops), carousel
  with scroll-driven edge fade + drag-to-scroll (the one reader-JS
  island, resolving §7.1), fan with superset multi-cover markup.
- **Remaining down the page**: Hero (dispatch + gallery + fed content —
  the big one), Biography, Newsletter; then Blog presentation and
  home.sections ordering (contract work).

Working-state schema as of today (localStorage / preview POST):
`{ design: {12 axes}, nav: {links[], button, title_as_alt}, fonts:
{display?, body?}, colors: {bg, accent, ink — hexes} }` — plus the Site's
logo attachment server-side. This is the draft contract the §5.4 bump
formalizes.

## 7. Open questions

1. ~~Reader-build JS policy~~ **Resolved 2026-07-31** with the carousel's
   drag-to-scroll: reader builds may ship **per-feature, dependency-free,
   conditional** scripts — included only when the design actually uses the
   feature (carousel.js ships solely under `design.cards == "carousel"`;
   every other design remains zero-JS). Mode's `auto` needs none.
2. Flat enums vs factored axes — rule of thumb adopted: factored where
   independent (avatar shape/side), flat where structural (hero, bio, nav);
   make explicit in the manifest doc.
3. Updates vs Blog as distinct content types (ties to `/posts/` vs `/blog/`).
4. Custom palette/fonts escape hatches vs closed-vocabulary validation
   (contract-version events; deferred).
5. Preview-serving auth story (draft content behind it) and whether the
   preview build directory lives under BUILDS_PATH or tmp.
6. Palette vocabulary itself — five current palettes provisional; revisit
   once SiteDesigner makes exploration cheap.
7. CI sync gate wiring (now urgent — §6 caveat): check out kindred-quill
   beside the app and install the pinned Hugo in `bin/ci`, so exporter and
   designer tests run everywhere and theme/exporter drift fails CI.
8. **Brand/wordmark font axis** (decided 2026-07-31, deferred as its own
   pass): typography stays a two-tier heading+body pairing (three
   independent slots is the competitor's failure mode — 16 of their 22
   groups collapsed onto one header face); the brand ladder is pairing
   display (default) → optional wordmark font styling only `.fk-brand`
   (`--font-brand` falling back to `--font-display`, ~8–10 curated
   logotype faces) → logo image (shipped). User-facing rationale in
   [site-designer-user-guide.md](site-designer-user-guide.md).
