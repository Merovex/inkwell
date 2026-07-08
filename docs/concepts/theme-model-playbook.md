---
type: concept
title: Theme model playbook
status: active
tags: [ui, theming, playbook, dark-mode, tint, accent, stimulus]
created: 2026-07-04
updated: 2026-07-04
sources: [concepts/theme-background-colors.md]
---

# Theme model playbook

Operating manual for Alcovo's runtime appearance system: how the pieces fit,
and the exact steps to change each one. For the *why* behind the color values
(OKLCH derivations, Tailwind mapping, tint history) see
[[theme-background-colors]]; this page is the *how-to*.

## Mental model — three independent axes

Appearance is **three orthogonal axes**, all resolved to CSS custom properties
in one file (`../../app/assets/stylesheets/01-tokens.css`) and all steered by two
`<html>` attributes:

| Axis | What it controls | Attribute | Values | Rotates? | Persisted as | Driven by |
|------|------------------|-----------|--------|----------|--------------|-----------|
| **Mode** | light vs dark (structural neutrals) | `data-theme` | `light`, `dark`, `auto` | cycles 3-way | cookie `theme` | `theme_controller.js` |
| **Tint** | the outer page background color | `data-tint` | `olive`, `taupe`, `mauve`, `mist`, `zinc` | **yes — the rotating one** | cookie `tint` | `tint_controller.js` |
| **Accent / brand** | interactive color (buttons, links, focus) | — | fixed teal ramp | **no** | n/a (CSS constant) | `01-tokens.css` |

Key point of vocabulary: the request's **"rotating accent color" is the rotating
`--tint`** (the site background), *not* the accent. The **accent is
deliberately fixed** — the same teal in every tint and both modes. The
**primary color = the fixed teal brand** (`--brand` → `--accent`).

```
cookie ──► ApplicationController helper ──► <html data-theme/data-tint> ──► CSS resolves --tokens ──► components
  ▲                                                    │
  └──────────── Stimulus writes cookie + attr ◄────────┘  (user clicks toggle)
```

Because the attributes are **server-rendered from the cookie on first paint,
there is no flash** — the correct mode and tint are on `<html>` before CSS runs.

## Where each piece lives

| Concern | File |
|---------|------|
| Token definitions (all colors, all axes) | `../../app/assets/stylesheets/01-tokens.css` |
| Cookie → `<html>` attributes (sanitized) | `../../app/controllers/application_controller.rb:29` |
| Attributes rendered on `<html>` | `../../app/views/layouts/application.html.erb:2`, `../../app/views/layouts/auth.html.erb:2` |
| Mode toggle (light/dark/auto) | `../../app/javascript/controllers/theme_controller.js` |
| Tint rotator | `../../app/javascript/controllers/tint_controller.js` |
| Both toggles in the user menu | `../../app/views/layouts/_header.html.erb:18` |
| Styleguide / swatches | `../../app/views/static/theme.html.erb` |

## How each axis works

### Mode (`data-theme`) — light / dark / auto
- `theme_controller.js` cycles `light → dark → auto` on click (`MODES`, line 3),
  writes `document.documentElement.dataset.theme`, sets a 1-year `theme` cookie
  (`samesite=lax`), and mirrors the mode as `data-mode` (drives which icon
  shows) plus a label.
- CSS: `[data-theme="dark"]` (`01-tokens.css:100`) overrides the structural
  neutrals and **pins `--site-bg` to near-black, ignoring the tint**. `auto`
  falls through to `@media (prefers-color-scheme: dark)` (`:127`).
- **Ordering matters:** the dark rules sit *after* the tint rules so that at
  equal specificity dark wins — an element carrying both `data-tint` and
  `data-theme="dark"` gets the dark background. Don't reorder these.
- Allowed values are whitelisted server-side (`ALLOWED_THEMES`, default
  `"light"`).

### Tint (`data-tint`) — the rotating background
- `tint_controller.js` reads its list from `data-tint-tints-value` (a JSON
  array on the button), steps to the next entry modulo length, writes
  `<html data-tint>`, sets a 1-year `tint` cookie, and capitalizes the label.
- CSS: each `[data-tint="…"]` sets `--tint` to an OKLCH `-200` shade
  (`01-tokens.css:74`), then `[data-tint] { --site-bg: var(--tint); }` (`:87`)
  re-resolves the background on whichever element carries the tint.
- **The recipe: Tailwind v4 `-200` level, desaturated by 15%** — keep the
  Tailwind lightness and hue, scale chroma ×0.85. Shipped values
  (`01-tokens.css:74–79`):

  ```css
  /* Tailwind v4 -200 shades, chroma ×0.85 (−15% desaturation) */
  [data-tint="olive"] { --tint: oklch(93%   0.007 106.5);   } /* olive-200 */
  [data-tint="taupe"] { --tint: oklch(92.2% 0.005  34.3);   } /* taupe-200 */
  [data-tint="mauve"] { --tint: oklch(92.2% 0.005 325.62);  } /* mauve-200 */
  [data-tint="mist"]  { --tint: oklch(92.5% 0.005 214.3);   } /* mist-200 */
  [data-tint="zinc"]  { --tint: oklch(92%   0.004 286.32);  } /* zinc-200 */
  ```
- Default/fallback tint is `zinc` (`current_tint`, and the label default in the
  header). The controller list and the CSS rules must stay in sync (see below).
- Sanitized server-side against `/\A[a-z]+(-[a-z0-9]+)?\z/` since it renders
  straight into an HTML attribute.

### Accent / brand — fixed
- Defined once as a teal ramp: `--brand-deep/-strong/-muted/--brand`
  (`01-tokens.css:47`), with `--accent: var(--brand)` and
  `--accent-ink: var(--brand-deep)`. Components read `--accent*`, never the raw
  teal. It does **not** vary by tint; in dark mode only the *soft* variants
  shift (`--accent-soft` → teal-900, etc.).
- Same desaturation rule as the tints — Tailwind v4 teal, chroma ×0.85
  (−15%), levels picked by role lightness. Shipped values:

  ```css
  --brand-deep:   oklch(27.7% 0.039 192.524); /* teal-950 −15%C — deep bg, strong text */
  --brand-strong: oklch(43.7% 0.066 188.216); /* teal-800 −15%C — solid fill for white text (AAA) */
  --brand-muted:  oklch(51.1% 0.082 186.391); /* teal-700 −15%C — secondary borders, inactive */
  --brand:        oklch(70.4% 0.119 182.503); /* teal-500 −15%C — buttons, progress, focus */
  --accent-soft:  oklch(95.3% 0.043 180.801); /* teal-100 −15%C — hover/selected (teal-900 −15%C in dark) */
  ```

## Playbook — common changes

### ▸ Add a new tint (e.g. `slate`)
1. **CSS** — add a rule in `01-tokens.css` in the tint block (`:74–79`),
   following the recipe: take the Tailwind v4 `-200` OKLCH value, keep L and H,
   multiply chroma by 0.85. E.g. slate-200 is `oklch(0.929 0.013 255.508)`, so:
   ```css
   [data-tint="slate"] { --tint: oklch(92.9% 0.011 255.508); } /* slate-200 −15%C */
   ```
2. **Toggle list** — add `"slate"` to `data-tint-tints-value` in
   `_header.html.erb:27`. Order defines rotation order.
3. **Styleguide** — add `slate` to the `%w[olive taupe mauve mist zinc]` array
   in `static/theme.html.erb` so it shows in the swatches.
4. No controller or Ruby change needed — the sanitizer already accepts any
   lowercase word, and the controller is data-driven.

### ▸ Remove / reorder tints
- Edit the `data-tint-tints-value` array (`_header.html.erb:27`) — that alone
  changes rotation order and membership. Leave the CSS rule in place (harmless)
  or delete it too for tidiness. If you remove the **default** (`zinc`), also
  update the fallback in `current_tint` (`application_controller.rb:36`) and the
  label default in the header (`:30`).

### ▸ Change the default tint or mode
- **Tint:** change the `"zinc"` fallback in `current_tint` *and* the
  `<span data-tint-target="label">Zinc</span>` default (`_header.html.erb:30`).
- **Mode:** change the `"light"` fallback in `current_theme` and, if desired,
  `data-mode="light"` / the label default in the header. Note the layout ships
  `data-theme="light"` explicitly, so the OS `prefers-color-scheme` fallback
  only kicks in for `auto` or if that attribute is removed.

### ▸ Change the accent / brand color
- Edit only the `--brand*` values in `01-tokens.css:47–51` (and the dark-mode
  `--accent-soft`/`--menu-context-*`/`--link` block at `:117`). Because
  everything reads `--accent`/`--brand`, nothing else needs touching. Keep the
  AAA-contrast intent noted in the comments.

### ▸ Add a themeable color token
- Add it to `:root` in `01-tokens.css`, and if it must differ in dark mode add
  the override in **both** the `[data-theme="dark"]` block (`:100`) *and* the
  `@media (prefers-color-scheme: dark)` block (`:127`) — the two are duplicated
  on purpose to keep the OS fallback clean. Components reference `var(--token)`;
  never bake a literal color into a component (see the standing rule).

### ▸ Wire the toggles into a new page
- Any layout that renders `<html>` must set both attributes:
  `<html data-theme="<%= current_theme %>" data-tint="<%= current_tint %>">`
  (as in `application.html.erb`/`auth.html.erb`). The helper methods are exposed
  via `helper_method` (`application_controller.rb:17`), so they're available in
  any view.

## Gotchas
- **Accent doesn't rotate.** If asked to "rotate the accent," confirm intent —
  the rotating axis is the tint/background; the accent is a fixed brand constant
  by design.
- **Two dark blocks.** Dark-mode overrides are duplicated (explicit +
  media-query). Change both or `auto` drifts from `dark`.
- **Cascade order is load-bearing.** Tint rules before dark rules → dark wins on
  `data-theme="dark"`. Don't reorder.
- **`--accent-pale` is doc-only.** [[theme-background-colors]] references an
  `--accent-pale` primary-button fill that is **not** defined in
  `01-tokens.css`. Aspirational; add the token before relying on it.
- **List/CSS drift.** A tint in the controller list with no matching
  `[data-tint="…"]` rule falls back to `--neutral-bg` (zinc) silently. Keep the
  two in sync.
- **Cookie, not DB.** Theme and tint are per-browser cookie prefs, not stored on
  any model — clearing cookies resets to `light` / `zinc`.
</content>
</invoke>
