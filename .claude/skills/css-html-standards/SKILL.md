---
name: css-html-standards
description: Enforce Inkwell's CSS and HTML standards — design tokens over raw values, curated compositional utilities over one-off CSS, BEM only for real components, semantic HTML, and hard a11y requirements. Use whenever writing, refactoring, or reviewing stylesheets or view markup.
---

# CSS & HTML Standards

These rules are objective and authoritative. Existing code that violates them is
wrong, not precedent — judge code against the rules, never derive rules from code.

## 1. Tokens first — no hard-coded design values

Every design value in author CSS must be a `var()` reference: colors, spacing,
radii, shadows, font sizes/weights/families, line heights on the scale, easings,
borders widths above the hairline, z-indexes, animation timings.

Sources, in preference order:

1. **Semantic local tokens** (defined in `01-tokens.css` `:root`) when the value
   has meaning — e.g. a surface color, a border color, the base pad unit.
2. **Open Props scales** (`open-props.css`, vendored, immutable) for raw scale
   steps — `--size-*`, `--font-size-*`, `--radius-*`, `--shadow-*`, `--ease-*`,
   `--gray-*` and friends.

Never introduce a third source. If a needed value has no token, add a semantic
token to `01-tokens.css` that references an Open Props step — don't inline it.

**Sanctioned raw values** — these, and only these, may appear literally:

- `0` (any property)
- `1px` hairline borders/outlines/offsets
- Geometry percentages: `50%`, `100%`, and friends used for shape/position
  (e.g. `border-radius: 50%`, `width: 100%`, transforms)
- Unitless numbers where the unit is the point: `line-height: 1.4`, `flex: 1`,
  `opacity`, `scale`, counts
- Content-driven measures: `ch`-based widths (`max-width: 60ch`)
- Font-relative (`em`) micro-spacing and `vertical-align` nudges on inline
  text-flow chips and icons (`.mention` padding, an inline lucide's baseline
  nudge) — scaling with the surrounding text is the point. Not a loophole for
  layout spacing: block/flex/grid gaps and paddings stay on the token scale.
- `currentColor`, `transparent`, `inherit` and other CSS keywords
- **Breakpoint literals in `@media` conditions only** — CSS cannot read
  custom properties there. The house stops are `48em` (`--breakpoint-md`,
  768px) and `64em` (`--breakpoint-lg`, 1024px), declared as documentation
  constants in `01-tokens.css`; every media query repeats the literal with a
  `/* --breakpoint-md */`-style comment. No other breakpoint values exist —
  em units so boundaries scale with user font size (px spec ÷ 16).

Anything else literal — a hex/oklch/rgb color, a `px`/`rem`/`em` length, a raw
`cubic-bezier`, a raw shadow — is a violation. Snap to the nearest token; if the
design genuinely needs an off-scale value, that's a design conversation, not an
inline exception.

**Mechanical check** (excluding vendored files — `open-props.css` and
`jsvectormap.css` are vendored and NEVER touched — plus unlayered vendor
counter-rules noted in CLAUDE.md, and token *definitions* themselves):

```sh
grep -rnE '#[0-9a-fA-F]{3,8}\b|\b[0-9]+(\.[0-9]+)?(px|rem|em)\b' app/assets/stylesheets --include='*.css' | grep -v -e open-props.css -e jsvectormap.css
# then hand-filter the sanctioned list (0, 1px, ch, geometry %)
```

## 2. Utilities: a curated compositional vocabulary

The utility set is small, deliberate, and compositional (CUBE-CSS style) — each
utility expresses one *intent* (stack, cluster, flow, pad, surface, microcaps),
not one property-value pair. This is explicitly **not** Tailwind: no generated
atomic classes, no `u-mt-2`-style property soup.

- Prefix `u-`, one file per utility (`u-stack.css`), wrapped in
  `@layer utilities`.
- Utilities are configured through custom properties with token defaults, and
  variants set the custom property rather than restating declarations:

  ```css
  @layer utilities {
    .u-stack { display: flex; flex-direction: column; gap: var(--u-stack-gap, var(--u-pad)); }
    .u-stack-half { --u-stack-gap: calc(var(--u-pad) / 2); }
  }
  ```

- **The recurrence rule:** before writing new CSS for a view, check whether an
  existing utility (or composition of utilities) expresses the intent. If you're
  about to write a declaration block *similar* to one that already exists
  anywhere in author CSS, extract or extend a utility instead — similar CSS in
  two places is the trigger, don't wait for a third.
- New utilities are added deliberately: one intent, one file, named for what it
  *does* for the reader, not how it's implemented.
- One-off page styling that doesn't merit a utility still uses tokens and lives
  with the smallest possible footprint — never a new BEM block (see §3).

## 3. BEM is earned, not assumed

A `block__element` component may exist only if **all three** hold:

1. **Named** — it's a domain concept with a real name (`canvas`, `badge`,
   `avatar`, `list`), not a description of a page ("settings card").
2. **Structured** — it has internal parts that need co-naming (`__head`,
   `__body`, `__item`). A single class with no `__elements` is not a BEM block;
   it's either a utility or a one-liner component class.
3. **Reused** — it renders through a shared partial (`app/views/shared/`), is
   documented in the living style guide (`/admin/theme`,
   `app/views/admin/static/theme.html.erb`), or is singleton app chrome
   rendered from exactly one `app/views/layouts/` partial (header, subnav,
   switcher, toasts) — single-sourced markup satisfies the rule's intent.

Fail any one → use utilities, or bring the component up to standard (document
it in the style guide, or extract the shared partial). Exceptions are not
blessed — there should be few if any; refactor toward the standard instead.
Pass all three → the component gets its own CSS
file in `@layer components`, its markup lives in exactly one shared partial
(extend the partial with locals; never fork its markup — see CLAUDE.md on
`shared/list_item`), and it appears in the style guide.

Inside an earned component, tokens still rule (§1), and don't restate what a
utility already provides — a component partial may compose utilities in its
markup.

## 4. Semantic HTML

Element choice carries meaning; `<div>`/`<span>` are what's left when no
semantic element fits.

- Landmarks: one `<main>` per page; `<nav>` for navigation clusters;
  `<header>`/`<footer>` for intro/outro content of page or article.
- `<article>` for self-contained items (posts, comments, list rows — the
  `shared/list_item` row is an `<article>` by contract); `<section>` only with a
  heading that names it.
- Headings are a real outline: one `<h1>`, no skipped levels, never chosen for
  font size (style with utilities/tokens instead).
- `<ul>`/`<ol>` only for things that are semantically lists (and note the house
  `.list` component intentionally does *not* use them — see CLAUDE.md).
- `<button>` acts, `<a>` navigates. Never a click handler on a `div`/`span`.
- `<time datetime=…>` for dates, `<kbd>` for keys, `<dl>` for label/value pairs.

## 5. Accessibility — hard requirements, all of them

These are gates. Markup or CSS that fails one does not ship.

**Structure**
- Landmarks and heading order as in §4.
- Every page sets a distinct `<title>`.
- A skip link precedes the navigation.

**Interaction**
- Every interactive control is a natively focusable element, reachable and
  operable by keyboard, with visible `:focus-visible` styling (token-based).
- Every form input has an associated `<label>` (or `aria-label` where a visible
  label is genuinely impossible).
- ARIA only when no native element/attribute can do the job (first rule of
  ARIA); prefer fixing the element choice over adding roles.

**Perception & motion**
- Color-pair choices come from tokens and meet WCAG AA contrast; check both
  themes if a token differs by scheme.
- Color is never the only signal — pair with text, icon, or shape.
- Every `<img>` has `alt` (empty `alt=""` for decorative).
- Any animation or non-trivial transition is wrapped in or overridden by
  `@media (prefers-reduced-motion: reduce)`.

**Screen-reader affordances**
- Async UI updates (toasts, turbo-stream inserts) announce via `aria-live`
  regions.
- Icon-only buttons carry visually-hidden text or `aria-label`.

## 6. Cascade mechanics (house facts)

- Layer order is fixed by `00-layers.css`: `base < components < utilities`.
  All author CSS is wrapped in its layer; only token definitions and the
  documented vendor counter-rules live outside layers.
- Sheets load alphabetically via `stylesheet_link_tag :app`; unlayered vendor
  CSS (`lexxy.css`) beats every layered rule — see CLAUDE.md "CSS cascade
  hazards" for the known traps (lexxy, `.avatar` em-sizing, inline-flex
  baselines).

## Review procedure

When reviewing or cleaning existing CSS/markup, work through the rules in
order — tokens (§1), then duplicate-CSS → utilities (§2), then unearned BEM
(§3), then markup semantics (§4) and a11y (§5). Cite the rule number in
findings. The mechanical grep in §1 and a scan for `block__element` selectors
against the §3 three-part test cover most of it objectively.
