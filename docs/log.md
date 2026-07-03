# Work Log

Append-only. Newest first. Format defined in [[CLAUDE]] (`CLAUDE.md`).

## [2026-07-02] tweak | --brand-text token (teal, 7:1) for the list byline
- Added mode-aware `--brand-text` (teal-tinted body text, 7:1 on the canvas: dark teal light / light teal dark). List byline (name · date) now uses it instead of neutral --ink-muted.
- refs: 01-tokens.css, list.css

## [2026-07-02] tweak | List view gets the standard canvas head too
- Added `shared/canvas_head` (breadcrumb Alcovo / Message Board + ⋯) atop list-view with board-level menu items (Subscribe / Manage categories / Board settings). Both list + item views now use the standard head.
- refs: static/list_view.html.erb

## [2026-07-02] refactor | Standard canvas head (breadcrumb + context menu) as a partial
- Extracted the theme's inline `.canvas__head` into `shared/_canvas_head` (breadcrumb from a `crumbs` local + ⋯ popover shell that YIELDS the menu items — structure standard, contents context-specific). Theme + item-view both render it; deleted the old `shared/_context_menu`. Item-view wraps head + perma-header in the `editable` controller so the menu's Rename (and clicking the title) drive the editable title; removed the perma-header's separate ⋯ menu.
- pages touched: [[app-shell]]
- refs: shared/_canvas_head.html.erb, static/theme.html.erb, static/item_view.html.erb

## [2026-07-02] build | perma-header + list-view/item-view composition pages
- Added `.perma-header` (page title + toolbar), adapted from Basecamp's MessageBoardHeader to Alcovo tokens (teal not blue, reuses our button/popover/menu). Supporting components: `button-group.css` (segmented control), `filter-by-text.css` (overlapping label + kbd via :placeholder-shown), `kbd.css`, `editable.css` + `editable_controller.js` (click-to-edit title). Category/sort dropdowns reuse the `.menu` popover; taught `anchored-popover` a `placement` value (below | top) so dropdowns open below the trigger while the canvas ⋯ keeps top; added `.menu__check` for single-select.
- New pages: `static#list_view` (/list-view) = perma-header toolbar + `.list` of messages; `static#item_view` (/item-view) = editable title (click or context-menu Rename) + content. Routes + StaticController actions added.
- Static-checked (routes syntax, braces, no baked colors, files present); interactive bits (dropdown placement, editable, tabs) not server-run per request — need a browser click.
- pages touched: [[app-shell]]
- refs: perma-header.css, button-group.css, filter-by-text.css, kbd.css, editable.css, menu.css, editable_controller.js, anchored_popover_controller.js, shared/_context_menu.html.erb, static_controller.rb, config/routes.rb, static/list_view.html.erb, static/item_view.html.erb

## [2026-07-02] build | Tier 1 components + Tabs (forms, modal, pagination, empty)
- Forms: expanded `field.css` (select w/ chevron, textarea, input-group affixes, sizes, disabled, `--required`, `field__error`; fixed its baked danger reds → `--danger-ink`); added `choice.css` (checkbox/radio via accent-color), `switch.css` (toggle), `error-summary.css` + `shared/_error_summary` partial (Rails model.errors).
- `modal.css` + `dialog_controller.js` — native <dialog> modal (Esc + backdrop-click close, animated). Added `--scrim` token; repointed the menu bottom-sheet backdrop to it. `pagination.css` (current page = teal-800/white AAA). `empty.css` (blank slate). `tabs.css` + `tabs_controller.js` (ARIA tabs, click + arrow-key).
- Also tokenized toast.css border colors (removed last baked component colors; only vendored open-props remains). Added all to the styleguide. Static-checked (braces, tokens exist, no baked colors, icons/controllers present); not server-run per request — the JS bits (dialog, tabs) use standard Stimulus wiring.
- pages touched: [[app-shell]]
- refs: field.css, choice.css, switch.css, error-summary.css, modal.css, pagination.css, empty.css, tabs.css, dialog_controller.js, tabs_controller.js, toast.css, 01-tokens.css, shared/_error_summary.html.erb, static/theme.html.erb

## [2026-07-02] build | u-gap utilities + u-margin styleguide demo
- Added `u-gap.css` (gap/half/double/0 + row/col single-axis, --u-pad scale). Added a `.u-margin` family demo to the styleguide Spacing section (bordered flow-root container so margin space is visible and doesn't collapse). Pad utilities left unchanged per request.
- pages touched: [[app-shell]]
- refs: u-gap.css, static/theme.html.erb

## [2026-07-02] fix | Primary button → solid teal-800 + white (AAA at rest)
- Reverted the AA-at-rest teal-500 + dark-text primary (read as low-contrast, same-hue). Now solid teal-800 (`--brand-strong`) + white = 7.6:1 AAA at rest, darken-on-hover. (Note: white on the light teal-500 was only 2.49:1 — white needs the darker teal.)
- refs: button.css

## [2026-07-02] tweak | Primary button AA→AAA-on-hover; u-margin utilities
- Primary button is now a vibrant teal-500 fill + teal-950 text (5.97:1, AA) at rest, deepening to teal-800 + white (7.6:1, AAA) on hover — a deliberate AA-at-rest exception for the CTA (WCAG judges the resting state; hover enhances). Removed the now-unused --accent-pale token.
- Added `u-margin.css`: margin utilities mirroring u-pad (all/block/inline, half/double/0) plus single logical edges (block-start/-end, inline-start/-end each half/double) and auto variants (u-margin-inline-auto etc.).
- pages touched: [[app-shell]]
- refs: button.css, 01-tokens.css, u-margin.css

## [2026-07-02] a11y | Component labels to AAA 7:1 (token-driven, never baked)
- Audited every text/fill pair (both modes) and raised component labels to ≥7:1, all via new tokens in 01-tokens.css (no baked values): `--link` (mode-aware dark/light teal; links now underlined since dark), `--ink-on-soft` (avatar initials + accent badge, mode-aware, replaces --badge-accent-ink/--avatar-ink), `--menu-context-bg` retuned (teal-800 light / teal-400 dark), and semantic `--success/warning/danger-surface` + `-ink` + `--danger-solid`. Badge/alert/button-danger now reference these; danger button became a soft-fill (light-red, AAA in both modes) like the primary. Brand link neutralized to --ink (no underline). Muted metadata (byline/placeholder/table-head) intentionally left at AA — 7:1 defeats "muted". Solved OKLCH lightnesses numerically; re-audited: all pairs 7.09–7.60 in light + dark. HTTP 200, tokens served.
- pages touched: [[theme-background-colors]]
- refs: 01-tokens.css, badge.css, alert.css, button.css, avatar.css, list.css, 02-base.css, bar.css

## [2026-07-02] tweak | List: white count text + whole-row click-through (verified)
- Count bubble now teal-700 (`--brand-muted`) + white text (5.48:1; white on the old teal-500 was ~2.5:1). Whole row clicks through via a stretched-link `.list__body::after` (item is position:relative) plus `pointer-events:none` on the count so it doesn't capture its own clicks. Verified headless: avatar/title/excerpt/count all resolve to the row link.
- pages touched: [[app-shell]]
- refs: list.css

## [2026-07-02] build | Generic .list / .list__item (summary rows), verified
- Added a generic list component (Basecamp's article-list, adapted to Alcovo tokens/BEM — not React/Tailwind). `list.css`: avatar + linked title/meta + optional trailing count; single hairline dividers (row border-top + list border-bottom, no doubling); title ellipsis, meta 2-line clamp; reuses `.avatar` (56px) and `.badge--warning` (eye icon) for the "client visible" pill; count bubble uses `--accent`/`--accent-ink` (teal, not Basecamp blue). Partial `shared/_list_item` with strict locals (href/title/author/date/excerpt/avatar_src/avatar_alt/client_visible/comment_count). Added a List section to the styleguide. Verified headless: title truncates, count sits OUTSIDE the anchor, client badge renders.
- pages touched: [[app-shell]]
- refs: list.css, shared/_list_item.html.erb, static/theme.html.erb

- The theme and tint Stimulus controllers now write a year-long cookie (`theme`, `tint`; path=/, samesite=lax) on change. ApplicationController exposes `current_theme` (whitelisted) and `current_tint` (sanitized) helpers; the layout renders `<html data-theme data-tint>` from them, so the persisted appearance is applied server-side on first paint (no FOUC — chosen over localStorage for that reason). Verified headless: set dark/olive → full reload → server renders dark/olive, labels sync.
- pages touched: [[app-shell]]
- refs: application_controller.rb, application.html.erb, theme_controller.js, tint_controller.js

## [2026-07-02] fix | Canvas max-width was 1.6× too wide (rem/px unit mismatch); remove stone
- The canvas dims were authored as if 1rem=10px (comments said 1088px/48px/40px) but the app uses a 16px root, so max-width:108.8rem was actually 1740px — hence "too wide" on big monitors. Corrected to the intended px: max-width 68rem (1088px), gutter calc(100% - 3rem), padding-inline 2.5rem, and the head's mirrored margin-inline -2.5rem. Verified: 1088px cap on a 2560px viewport.
- Removed the `stone` tint (redundant with taupe — ΔE 0.0024, ~8× below JND) from tokens, cycler, styleguide, and doc.
- pages touched: [[app-shell]], [[theme-background-colors]]
- refs: canvas.css, menu.css, 01-tokens.css, _header.html.erb, static/theme.html.erb

## [2026-07-02] decision | Tints promoted to -200 (the -100 vs -200 test picked -200)
- The styleguide A/B confirmed -200 reads better than -100, so the six base tint names (olive/taupe/mauve/mist/zinc/stone) now hold the Tailwind -200 values; removed the separate `*-200` experiment tokens, the styleguide's second swatch row, and the -200 cycler entries. `--neutral-bg` fallback → zinc-200. Doc updated.
- pages touched: [[theme-background-colors]], [[app-shell]]
- refs: 01-tokens.css, _header.html.erb, static/theme.html.erb

## [2026-07-02] build | User-menu theme+tint row; mode-aware badge/avatar; stone; -200 test
- User menu: theme (light/dark/auto) and tint (color) toggles now share a `.menu__row` (flexbox + gap) above Sign out; the tint control moved out of the fixed bottom-right dropper into the menu (tint controller now updates a title-cased label, flash removed). Removed the styleguide's floating dropper + its CSS.
- Accent badge fg is now mode-aware `--badge-accent-ink` (teal-600 light 3.33:1 / teal-400 dark 4.97:1) since the soft fill flips light↔dark; the dark-mode avatar uses the same value (`--avatar-ink`), matching the badge (4.97:1). Light avatar stays teal-700.
- Added `stone` tint (stone-100) to the tints, cycler, and styleguide.
- Added a `-200` test set for all six tints (tokens + a second styleguide swatch row + appended to the cycler) to judge whether more color is too much.
- pages touched: [[app-shell]], [[theme-background-colors]]
- refs: 01-tokens.css, menu.css, badge.css, avatar.css, tint_controller.js, theme_controller.js, _header.html.erb, static/theme.html.erb

## [2026-07-02] tweak | Context menu dark-mode bg up a level (teal-400 → teal-500)
- Dark-mode `--menu-context-bg` bumped one level darker to teal-500 (= var(--brand)). Text stays teal-950; contrast 5.83:1 (AA). Light mode unchanged (teal-700).
- pages touched: [[app-shell]]
- refs: 01-tokens.css

## [2026-07-02] build | Light/dark/auto toggle in the user menu (verified)
- Added a cycling theme control as a `.menu__item` above Sign out in the user menu. `theme_controller.js` cycles `<html data-theme>` light → dark → auto on click; label + sun/moon/monitor icon reflect the mode (icon swap via `.theme-toggle[data-mode]` in theme-toggle.css). "auto" falls through to the existing prefers-color-scheme query. No persistence yet (resets to light on reload, like the tint dropper). Verified headless: cycles correctly, label/icon track, menu stays open.
- pages touched: [[app-shell]]
- refs: theme_controller.js, theme-toggle.css, app/views/layouts/_header.html.erb

## [2026-07-02] tweak | Context menu reveals from the canvas right edge (not page)
- The `translate: 100%` slide dragged the panel in from off-screen through the canvas→viewport gutter, reading as "from page right." Swapped to a `clip-path: inset(0 0 0 100%)` → `inset(0)` reveal (added clip-path to the .menu transition), so it wipes in from its own right edge while pinned at the canvas edge. Verified headless: opens fully revealed (clip-path inset(0px)), flush right, closes.
- pages touched: [[app-shell]]
- refs: menu.css

## [2026-07-02] tweak | Context menu goes dark teal (teal-700 light / teal-400 dark)
- Deliberately-odd: `.menu--context` background is teal-700 (light mode, near-white text) inverting to teal-400 (dark mode, teal-950 text) via `--menu-context-bg/-ink` tokens. Close/items/hover/separator recolor to stay legible. Contrast checked: 5.20:1 light, 7.59:1 dark (both pass AA).
- pages touched: [[app-shell]]
- refs: 01-tokens.css, menu.css

## [2026-07-02] tweak | Context menu: trim top pad; track toggle on scroll (verified)
- Reduced `.menu--context` padding-block-start 3rem → 2.5rem (item still clears the close, 2px gap). The anchored-popover controller now re-aligns the open menu to the toggle on scroll/resize, so it tracks the sticky header instead of detaching. Verified headless: pre-scroll menuTop=toggleTop=70; post-900px-scroll menuTop=toggleTop=headTop=0.
- pages touched: [[app-shell]]
- refs: menu.css, anchored_popover_controller.js

## [2026-07-02] build | Context menu: internal close, flush-right, sticky head (verified)
- Reworked the context menu: close (X) moved INSIDE the popover (same top layer, so z-index lifts it above the items — an external button can't beat the top layer), same `button--icon button--ghost` shape as the ⋯ toggle, menu padded down to clear it. Menu now sits at the top of the canvas, flush to the right edge (controller aligns popover top/right to the toggle). Menu font dropped to `--font-size-0` (matches breadcrumb). Made `.canvas__head` `position: sticky; top: 0` (removed the canvas `overflow: clip` that would have disabled sticky; head gets a background + matching top radius). Moved `.menu--context` into menu.css so it loads after the base `.menu` (a cascade bug where the base padding shorthand overrode the modifier). Verified headless: item-clears-close ✓, same shape (38×38) ✓, flush right (1227=1227) ✓, sticky after 900px scroll (top=0) ✓, X closes ✓.
- pages touched: [[app-shell]]
- refs: menu.css, canvas.css, anchored_popover_controller.js, shared/_context_menu.html.erb, app/views/static/theme.html.erb

## [2026-07-02] fix | Context menu positioned below toggle (verified headless)
- A top-layer popover can't be z-indexed under the toggle, so the menu must sit below it. First attempt (CSS anchor positioning) silently failed in-browser — popover fell to top-left, and the `@supports not(anchor-name)` fallback didn't trigger because `anchor-name` parses. Replaced with an `anchored-popover` Stimulus controller that sets the popover inset from the toggle's rect on `beforetoggle` (uses `documentElement.clientWidth` to avoid a scrollbar over-offset). Verified via headless Chromium: opens below the toggle, right edges aligned (719=719), ⋯→X swap shows, second click closes.
- pages touched: [[app-shell]]
- refs: canvas.css, anchored_popover_controller.js, shared/_context_menu.html.erb

## [2026-07-02] build | Context toggle X-swap; soft-teal primary; avatar contrast
- Context-menu toggle now sits flush right and swaps ⋯ → X (via `:has(~ .menu--context:popover-open)`) so the same button (pixel-identical) opens/closes without moving the mouse; still native Popover API. Primary button is now a soft fill: `--accent-pale` (brand teal at teal-50 brightness) with teal-500 border + teal-950 text. Avatars bumped their initials to `--brand-muted` (teal-700) for contrast on the soft fill.
- pages touched: [[theme-background-colors]]
- refs: canvas.css, button.css, avatar.css, 01-tokens.css, app/views/static/theme.html.erb

## [2026-07-02] build | Data table component; canvas head hugs border; side context menu
- Added a `.table` data-table component (table.css, +zebra, right-align cells, scroll wrapper) and a Data tables section in the theme. Made `.canvas__head` full-bleed hugging the top border (canvas gets `overflow: clip`; head has no block padding, 2rem inline). Extracted the context menu to a stub partial `shared/_context_menu` and reworked it to slide in from the canvas's right side — still native Popover API (no JS). Moved the tint drip earlier to a small fixed bottom-right widget.
- pages touched: [[app-shell]]
- refs: table.css, canvas.css, menu.css, shared/_context_menu.html.erb, app/views/static/theme.html.erb

## [2026-07-02] build | Canvas head (breadcrumb + context menu); drip floats bottom-right
- Renamed `.main-content` → `.canvas` (canvas.css) and dropped its roundness one level (radius-3 → radius-2). Added `.canvas__head` — a thin top strip with a `.breadcrumb` (new breadcrumb.css) left and a `.menu--context` (⋯) popover right, positioned via CSS anchor positioning with a fixed fallback. Moved the styleguide tint drip to a smaller, fixed, floating bottom-right widget. Added to the theme page.
- pages touched: [[app-shell]]
- refs: canvas.css, breadcrumb.css, 02-base.css, app/views/static/theme.html.erb, app/views/layouts/application.html.erb

## [2026-07-02] build | App-shell chrome — header top-right, PWA, toasts, Native gate
- Implemented ADR 0004/0005: moved the user-menu avatar + a notification bell to the header top-right and removed the footer; made the `.menu` popover responsive (desktop dropdown / mobile bottom-sheet at 48rem breakpoint); enabled the PWA (manifest link, `pwa` routes, SW registration, real manifest colors); added `hotwire_native?` + `hotwire-native` body-class gate (`hotwire-native.css` hides `.app-header`/`.app-tabbar`); added a `.toasts` aria-live region rendering flash with a `toast` auto-dismiss controller. Bell is a stub; bottom tab bar still deferred (no nav destinations). Not server-verified per request (Ruby syntax + manifest JSON checked).
- pages touched: [[app-shell]]
- refs: _header.html.erb, _toasts.html.erb, application.html.erb, menu.css, toast.css, hotwire-native.css, toast_controller.js, application_controller.rb, config/routes.rb, app/views/pwa/manifest.json.erb

## [2026-07-02] decision | Mobile — Hotwire Native target, PWA in development
- Resolved ADR 0004's open mobile sub-decision: production target is Hotwire Native (native tab bar/nav), but development assumes a responsive PWA. So we DO build responsive mobile web chrome, gated under a `hotwire-native` body class so native nav takes over in the wrapper. Content responsive on all surfaces. Near-term task: enable the disabled PWA scaffolding.
- pages touched: [[0005-mobile-hotwire-native-pwa-dev]], [[0004-top-bar-app-shell]], [[app-shell]], [[index]]
- refs: app/views/pwa/manifest.json.erb, app/views/pwa/service-worker.js

## [2026-07-02] decision | Top-bar app shell; mobile nav fork left open
- Chose a top-bar app shell with profile + notification bell top-right (retiring the bottom-left footer avatar), over a left-sidebar shell. Documented desktop/mobile placement, notifications (bell top-right / slim mobile header), and toasts (bottom-right desktop / top banner mobile). Flagged the open sub-decision: responsive-web mobile chrome vs Hotwire Native (native tab bar) — web stays responsive either way. Documentation only; no UI built yet.
- pages touched: [[0004-top-bar-app-shell]], [[app-shell]], [[index]]
- refs: app/views/layouts/_header.html.erb, _footer.html.erb

## [2026-07-02] note | Theme background colors
- Documented site/canvas backgrounds (light + dark) and the rotating light-mode account tints, each mapped to its best-fit Tailwind class. Green and orange deliberately diverge from the nearest-distance class to preserve hue intent. Dark-mode canvas pinned (`gray-800`); light-mode canvas left as an open question.
- Added precise OKLCH tint tokens (two forms: Tailwind-v4 relative-color-syntax, and raw OKLCH). Alcovo ships the raw OKLCH form since there's no Tailwind. Green needs a 62% chroma cut; the rest are rounding errors.
- pages touched: [[theme-background-colors]], [[index]]
- refs: concepts/theme-background-colors.md

## [2026-07-01] decision | Collapse wiki into docs/
- Merged the `wiki/` machinery into `docs/` as the single documentation folder; kept the CLAUDE.md contract, index, log, decisions, templates, and raw/. Registered the design docs in the index. Retired the `wiki/` folder.
- pages touched: [[0003-collapse-wiki-into-docs]], [[0001-adopt-work-tracking-wiki]], [[index]], [[overview]], [[CLAUDE]]
- refs: docs/

## [2026-07-01] refactor | Reconcile docs to Person / User / Account
- Swept the design docs to the new vocabulary (ADR 0002): rewrote data-model.md, schema.rb, and account-creation-concern.md (renamed from group-creation-concern.md); fixed the Alcovo-facing mapping tables/prose in both Fizzy docs (verbatim Fizzy source left intact). Renamed placeholder "Writer Group" → "Alcovo" throughout.
- pages touched: [[0002-domain-vocabulary-person-user-account]]
- refs: data-model.md, schema.rb, account-creation-concern.md, fizzy-authentication.md, fizzy-user-account-model.md

## [2026-07-01] decision | Domain vocabulary: Person / User / Account
- Chose plain names for the three core models: keep Fizzy's `User`/`Account`, rename `Identity` → `Person`. Retired `Membership`, `Group`, `bucket`.
- pages touched: [[0002-domain-vocabulary-person-user-account]], [[domain-vocabulary]], [[index]], [[overview]]
- refs: data-model.md, fizzy-authentication.md

## [2026-07-01] note | Executive summary of docs research
- Alcovo is a multi-tenant "writer group" app modeled on Basecamp's Fizzy — delegated-type content spine, passwordless identity-centric auth, shared-DB row-level tenancy, Lexxy/Action Text rich text, MariaDB+HA for SaaS. Key open decision: shared multi-tenant SaaS vs. per-customer self-hosted.
- refs: (all reference docs)

## [2026-07-01] decision | Adopt a work-tracking wiki
- Established a Karpathy-style, LLM-maintained work log + knowledge base (initially in `wiki/`; later merged into `docs/` — see [[0003-collapse-wiki-into-docs]]).
- pages touched: [[0001-adopt-work-tracking-wiki]], [[index]], [[overview]]
- refs: CLAUDE.md
