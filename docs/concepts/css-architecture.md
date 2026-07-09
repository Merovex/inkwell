---
type: concept
title: CSS architecture — CUBE/BEM hybrid
status: active
tags: [ui, css, cube, bem, cascade-layers, propshaft, open-props]
created: 2026-07-04
updated: 2026-07-04
sources: [../app/assets/stylesheets/application.css]
---

# CSS architecture — CUBE/BEM hybrid

Inkwell's CSS is a **CUBE methodology skeleton with BEM naming inside the
blocks**: CUBE decides *what kind of rule something is* (composition, utility,
block, exception) and where it lives in the cascade; BEM decides *what a
block's internals are called*. No build step, no Tailwind, no Sass — plain
CSS files served by Propshaft, ordered by native cascade layers.

## Delivery: many small files, alphabetical, layered

`stylesheet_link_tag :app` emits **one `<link>` per file** in
`app/assets/stylesheets/`, in alphabetical filename order (this is intentional
— never "fix" it into a single import). Source order is therefore meaningless,
so cascade precedence is pinned by `@layer` instead:

```
00-layers.css    @layer base, components, utilities;   ← the single source of truth
01-tokens.css    design tokens (unlayered — variables, no conflicts)
02-base.css      reset + bare element defaults          @layer base
open-props.css   vendored non-color tokens (spacing/radii/shadows/type)
u-*.css          one utility or composition per file    @layer utilities
<component>.css  one block per file                     @layer components
```

Later layer wins: `base < components < utilities`. Unlayered rules (the token
files) beat all layers, which is fine — they only set custom properties.
Adding styles means **adding a new small file**, not growing an existing one;
`application.css` holds no rules, only this contract.

## The four CUBE buckets, as we do them

### C — Composition (layout primitives)

Generic "shape of the page" classes that arrange *any* children and know
nothing about content. Ours live in the `u-` namespace alongside utilities
(one deviation from canonical CUBE, which separates them):

- `.u-flow` — vertical rhythm via the owl selector (`> * + *`), tuned
  per-instance with `--u-flow-space`
- `.u-stack` — flex column with a uniform gap
- `.u-cluster` — wrapping row (button rows, toolbars, byline chips)
- `.u-center` / `.u-center-narrow` — measure-constrained centering

Each exposes a custom property (`--u-cluster-gap`, `--u-stack-gap`) so
instances tune spacing **without new classes** — configuration over
proliferation.

### U — Utility (single-purpose overrides)

One job, one file, `u-` prefix, `@layer utilities` so they beat components:
`.u-pad`, `.u-margin-block-end`, `.u-text-muted`, `.u-text-strong`,
`.u-full-width`, `.u-gap`. Spacing utilities derive from the `--u-pad` unit
(halves/doubles as modifier classes, e.g. `.u-flow-half`), not from an
arbitrary scale.

### B — Block (BEM components)

Standard components, one per file, classic BEM inside:

```css
.list          {}                 /* block */
.list__item    {}                 /* element */
.list__avatar  {}
.menu--context {}                 /* modifier */
.chat__line--own {}
```

Two house rules on top of BEM:

1. **Components are STANDARD, never bespoke.** There is a `.card`, `.button`,
   `.list`, `.menu`, `.comment` — there is deliberately no `.message-card` or
   `.forum-list`. A new feature composes existing blocks (the forum reuses
   `.list`, `.composer`, `.comment` wholesale); a genuinely new block earns a
   new file and an entry in the styleguide (`/theme`).
2. **Structure is documented in the file header.** Each component file opens
   with a comment naming its BEM structure (e.g. ``form.composer >
   .composer__title [+ .composer__category] + lexxy-editor``) so the
   expected DOM shape is readable without hunting through ERB.

### E — Exception (state, not new classes)

Deviations from a block's default are expressed as **modifiers or attribute
selectors**, never forked blocks:

- BEM modifiers for stable variants: `.button--primary`, `.button--ghost`,
  `.menu--context`, `.comment--composer`, `.chat__line--own`
- Data attributes for **runtime state**, styled with attribute selectors:
  `[data-theme="dark"]`, `[data-tint="olive"]`, `[popover]`, Stimulus
  targets/controllers — see [[theme-model-playbook]] for the appearance axes
- Structural pseudo-selectors where the DOM already encodes the state:
  `.list__item:has(.list__action)`, `:not([data-theme="light"])`

## Tokens: two sources, one rule

- **Non-color tokens** (spacing, radii, shadows, font scale, easing) come from
  vendored **Open Props** (`open-props.css`): `var(--font-size-3)`,
  `var(--radius-round)`, `var(--ease-3)`, plus our own `--u-pad` spacing unit.
- **Color tokens are ours**, defined once in `01-tokens.css` as semantic names
  (`--ink`, `--canvas`, `--site-bg`, `--line`, `--accent`, `--brand-*`) and
  derived from Tailwind v4 values desaturated by 15% (see
  [[theme-background-colors]] for the recipe and values).

The standing rule follows from this: **components reference `var(--token)`
only — never a literal color.** Dark mode and the tint rotation work entirely
by re-resolving tokens on `<html>` attributes; component files never mention
dark mode.

## How to add styles (decision ladder)

1. Can existing blocks + compositions express it? Compose in the ERB; write
   no CSS.
2. Is it a one-property nudge? Reach for a `u-` utility (or add one — new
   file, `@layer utilities`).
3. Is it a variant of an existing block? Add a `--modifier` (or a data
   attribute if it's runtime state).
4. Only then: a new standard block — new file, `@layer components`, BEM
   structure comment at the top, demo it in the styleguide at `/theme`.

## Gotchas

- **Never wrap tokens in a layer.** `01-tokens.css` and `open-props.css` are
  unlayered on purpose; layering them would drop them below components.
- **File order is alphabetical, not semantic.** The `00-`/`01-`/`02-`
  prefixes exist only so those files sort first; everything else relies on
  layers, so renaming a component file is cascade-safe.
- **Utilities beating components is by design.** If a utility "mysteriously"
  overrides your component rule, that's the layer order working — don't
  escalate specificity to fight it.
- **ERB comments in views are single-line** and icons are real SVG files
  rendered via `inline_svg_tag` — adjacent standing rules that pair with this
  one when building components.
