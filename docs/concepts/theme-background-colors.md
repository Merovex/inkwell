---
type: concept
title: Theme background colors
status: active
tags: [ui, theming, tailwind, colors, dark-mode]
created: 2026-07-02
updated: 2026-07-08
sources: []
---

# Theme background colors

## Update (2026-07-08) — retheme to the Merovex palette
The palette below (teal brand + Tailwind-derived tints) was **replaced** by the
Merovex Press palette to converge admin (Inkwell) and public sites. Current state
in `../../app/assets/stylesheets/01-tokens.css`:
- **Accent/brand** → the **syō-ro** teal family (not the old teal ramp): `--brand`
  = syō-ro-500, `--brand-strong` = syō-ro-800 (AAA button fill), `--link` /
  `--brand-text` = syō-ro-700, dark-mode accent lifts to syō-ro-300.
- **Structural neutrals** → the **mountain-mist** family: light `--site-bg`
  = mountain-mist-200, `--canvas` = white, `--ink` = mountain-mist-900; dark
  `--site-bg` = mountain-mist-950, `--canvas` = mountain-mist-800.
- **Rotating tints** → the custom **olive / taupe / mauve / mist / zinc** scales
  at the `-100` level (subtle) — see the `[data-tint]` block.
Both scales are ported from `~/Work/merovex.press`. The public site reuses them
via [[merovex-press-public-site]]. The mechanism (two `<html>` attributes, cookie
→ helper → token → component) is unchanged; only the values below are stale.

## Summary
Inkwell's chrome uses two background layers — the **site background** (the outer
page) and the **article/canvas** (the content surface) — each with a light and
dark variant. In light mode the site background **rotates** through a set of pale
tints (mirrored on Basecamp's account tints). This page pins the chosen Tailwind
class for every tint and for the structural surfaces, so the mapping stays
consistent across the app.

## Rotating light-mode tints

Best Tailwind fit for each Basecamp tint. Where the nearest class by raw color
distance "looks off," the corrected pick preserves the *hue intent* instead:

| # | Tint | Basecamp hex | Tailwind class | Notes |
|---|------|--------------|----------------|-------|
| 1 | green | `#F5FAF6` | `bg-green-50` | `stone-50` wins on pure distance but reads as warm-gray, not green. `green-50` preserves the hue intent. |
| 2 | purple | `#FCF7FF` | `bg-purple-50` | Near-perfect match (distance 2.8), no issue. |
| 3 | orange | `#FFF9F5` | `bg-amber-50` | `orange-50` (`#FFF7ED`) is too warm/saturated for a 98%-lightness tint. `amber-50` (`#FFFBEB`) is closer in temperature and nearly as pale. |
| 4 | blue | `#F5F9FF` | `bg-slate-50` | `slate-50` is the right cool-blue character. `blue-50` is slightly more saturated than needed. |
| 5 | red | `#FEF3F3` | `bg-red-50` | Near-perfect match (distance 1.4), no issue. |
| 6 | neutral | `#F6F6F6` | `bg-zinc-50` | `gray-50` / `neutral-50` / `zinc-50` are all equally close. `zinc-50` is the most achromatic — best for a deliberately colorless neutral. |

### Tints as OKLCH tokens

The Tailwind class names above are the *nearest-name* shorthand. The precise
values Inkwell ships are OKLCH, with chroma scaled down to match Basecamp's actual
(low) saturation. Two equivalent forms:

**Relative color syntax against Tailwind v4 `--color-*`** (preferred *if on
Tailwind v4* — stays tethered to the palette, so tints track any Tailwind color
update):

```css
--tint-green:   oklch(from var(--color-green-50)  l calc(c * 0.379) h); /* 62% chroma reduction */
--tint-purple:  var(--color-purple-50);
--tint-orange:  oklch(from var(--color-amber-50)  l calc(c * 0.940) h);
--tint-blue:    var(--color-blue-50);
--tint-red:     oklch(from var(--color-red-50)    l calc(c * 0.957) h);
--tint-neutral: var(--color-zinc-50);
```

**Raw OKLCH** (use when *not* on Tailwind v4 — this is Inkwell's case: Propshaft +
Open Props, no Tailwind, so `--color-*` don't exist and we ship these literals):

```css
--tint-green:   oklch(0.971 0.018 145.2);
--tint-purple:  oklch(0.977 0.014 308.3);
--tint-orange:  oklch(0.987 0.021  95.3);
--tint-blue:    oklch(0.970 0.014 254.6);
--tint-red:     oklch(0.971 0.012  17.4);
--tint-neutral: oklch(0.985 0      0);
```

Green is the only tint doing heavy lifting (`c * 0.379`); every other correction
is a rounding error from the original Basecamp hex. These OKLCH literals are what
`app/assets/stylesheets/01-tokens.css` actually defines (as `[data-tint="…"]`).

### Editorial / earthy tint palette (Tailwind v4)

An alternative, softer palette — warmer and more paper-like, aimed at long-form
editorial reading rather than the Basecamp account tints above.

```css
/* -------------------------------------------------------------
   The New Earthy / Editorial Tints (Tailwind v4)
   ------------------------------------------------------------- */

/* Soft, organic linen with a hint of warm green */
--tint-olive: oklch(98.8% 0.003 106.5);

/* Classic warm parchment/cream; unparalleled for long-form text */
--tint-taupe: oklch(98.6% 0.002 67.8);

/* Warm, sophisticated off-white with a whisper of violet */
--tint-mauve: oklch(98.5% 0.003 325.6);

/* Crisp, cool, coastal frost with a faint teal undertone */
--tint-mist: oklch(98.7% 0.002 197.1);


/* -------------------------------------------------------------
   The Standard Technical Tint
   ------------------------------------------------------------- */

/* Pure, clean, architectural off-white; completely temperature-neutral */
--tint-zinc: oklch(98.5% 0 0);
```

These are much lower chroma than the Basecamp-derived tints (0.002–0.003 vs.
0.012–0.021) — nearly-white papers rather than perceptible color washes.

**Decision (2026-07-02):** Inkwell ships **this editorial set** as the wired
tints — `olive`, `taupe`, `mauve`, `mist`, `zinc` — defined as
`[data-tint="…"]` in `app/assets/stylesheets/01-tokens.css`. The Basecamp-derived
set above is kept as reference/history, not wired. Default theme is **light**
(`<html data-theme="light">` in the layout), so the OS `prefers-color-scheme`
fallback only applies if that attribute is removed.

The very-light values above (`~98.x%` L) read as too pale. We first shipped the
Tailwind `-100` shades, then A/B'd `-100` vs `-200` in the styleguide and chose
**`-200`** (more color, not too much). Shipped values (real Tailwind v4 families):

```css
[data-tint="olive"] { --tint: oklch(93%   0.007 106.5);   } /* olive-200 */
[data-tint="taupe"] { --tint: oklch(92.2% 0.005  34.3);   } /* taupe-200 */
[data-tint="mauve"] { --tint: oklch(92.2% 0.005 325.62);  } /* mauve-200 */
[data-tint="mist"]  { --tint: oklch(92.5% 0.005 214.3);   } /* mist-200 */
[data-tint="zinc"]  { --tint: oklch(92%   0.004 286.32);  } /* zinc-200 */
```

### Brand color (accent)

Interactive UI (buttons, links, progress, focus) is driven by **Tailwind v4's
teal palette**, exposed as `--brand*` tokens and read via `--accent`. Levels were
chosen to match the original role lightnesses (deep ≈ L25, muted ≈ L55, brand ≈ L68),
then **chroma scaled ×0.85 (−15% desaturated)** throughout:

```css
--brand-deep:  oklch(27.7% 0.039 192.524); /* teal-950 −15%C — deep bg, sidebars, strong text */
--brand-muted: oklch(51.1% 0.082 186.391); /* teal-700 −15%C — secondary borders, inactive states */
--brand:       oklch(70.4% 0.119 182.503); /* teal-500 −15%C — key interactive: buttons, progress */
```

`--accent-soft` is teal-100 (−15%C) in light mode, teal-900 (−15%C) in dark.
`--accent-pale` is the brand teal at **teal-50 brightness** — the soft fill for the
**primary button** (pale teal fill, teal-500 border, teal-950 text). Avatars use
`--brand-muted` (teal-700) for their initials — one level up from `--accent` for
contrast on the soft fill.

`--accent: var(--brand)` and `--accent-ink: var(--brand-deep)` (dark teal text on
the lighter brand fill). `--brand-muted` is available for secondary borders /
inactive states but isn't wired into a component yet.

## Structural backgrounds

| Role | Dark mode | Light mode |
|------|-----------|------------|
| Site background | `bg-gray-950` * | `bg-[tint]` — per the tint table above |
| Article / canvas | `bg-gray-800` | _(unspecified — see open questions)_ |

\* `gray-950` is the near-black outer page in dark mode; the canvas (`gray-800`)
sits one step lighter on top of it for content.

## Gotchas / open questions
- **Distance vs. intent.** Four of six tints use the nearest Tailwind class; two
  (green, orange) are deliberately *not* the closest by color distance because
  the closest one shifts the perceived hue. Don't "correct" these back.
- **Light-mode canvas is unspecified.** Only the dark-mode canvas (`gray-800`)
  was pinned. Light-mode article/canvas still needs a decision — likely `white`
  or `gray-50` sitting on the rotating tint.
- These are Tailwind v3/v4 default palette values; if the Tailwind version or a
  custom palette changes, re-verify the hexes.
