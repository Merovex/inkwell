---
type: concept
title: App shell & responsive navigation
status: active
tags: [ui, layout, navigation, responsive, hotwire-native, mobile]
created: 2026-07-02
updated: 2026-07-02
sources: [decisions/0004-top-bar-app-shell.md]
---

# App shell & responsive navigation

## Summary
Inkwell uses a **top-bar app shell** (decided in [[0004-top-bar-app-shell]]):
brand top-left, **user menu + notification bell top-right**, content in a
centered canvas panel. This page is the living spec for how that chrome adapts
across desktop and mobile — and the still-open question of whether mobile
navigation chrome is **responsive web** or **native** (Hotwire Native).

## Current build
- **Header** (`_header.html.erb`, `.bar.app-header`, transparent) — brand
  top-left; **notification bell + user-menu avatar top-right**. The avatar opens
  the `.menu` popover: a **dropdown** on desktop, a **bottom-sheet** on mobile.
  Hidden under `.hotwire-native`.
- **Canvas** — `.canvas` (was `.main-content`; `canvas.css`), a centered content
  panel (max ~1088px, 2.4rem gutters, roundness one level below cards). Its
  `.canvas__head` is a **full-bleed strip hugging the top border** (breadcrumb
  left, context-menu ⋯ right) that is **`position: sticky` (top: 0)** so it stays
  put when scrolling long content. The context menu is a **Popover-API** panel
  (`.menu--context`, stubbed in `shared/_context_menu`), positioned at the **top
  of the canvas, flush to the right edge** by the `anchored-popover` Stimulus
  controller (from the toggle's rect; CSS anchor positioning proved unreliable
  cross-browser). It has an internal **close (X)** — same `button--icon
  button--ghost` shape as the ⋯ toggle, z-indexed above the items (both in the
  top layer) with the menu padded down to clear it. Slides in from the right.
- **Toasts** (`_toasts.html.erb`, `.toasts`) — an `aria-live` region rendering
  `flash`; bottom-right on desktop, top banner on mobile; auto-dismissed by the
  `toast` Stimulus controller.
- **Footer removed** — the avatar moved to the header (ADR 0004).
- **PWA enabled** (ADR 0005) — manifest linked, `pwa` routes on, service worker
  registered in `application.js`.
- **Hotwire Native gate** — `ApplicationController#hotwire_native?` sets a
  `hotwire-native` body class; `hotwire-native.css` hides `.app-header` /
  `.app-tabbar` under it.

**Breakpoint:** the mobile ↔ desktop switch is **48rem (768px)**, used by
`menu.css` and `toast.css`. (CSS media queries can't read custom properties, so
this literal is repeated where needed.)

## Target placement

| Element | Desktop | Mobile (web) | Mobile (Hotwire Native) |
|---|---|---|---|
| Brand | header, left | slim header, left | native title / web header |
| User menu (avatar) | header top-right, **dropdown** popover | header top-right, **bottom-sheet** popover | avatar in web header, or a native "Profile/More" screen |
| Notification bell | header top-right, left of avatar | slim sticky top header | native bar item, or web header |
| Primary nav | header (when it exists) | **bottom tab bar (CSS)**, Profile = far-right | **native tab bar** (path config) |
| Toasts | slide in **bottom-right** | **top banner**, auto-dismiss | native or web top banner |

Rules of thumb:
- Profile/account is **top-right** on desktop (universal convention) — never
  bottom-left in a footer strip (unconventional on desktop, collides with the
  mobile bottom-nav Home slot).
- On a mobile tab bar the **far-left slot is Home/Dashboard**; Profile/Menu goes
  **far-right**.
- Notifications are not Inkwell's engagement loop, so the bell stays in the header
  rather than taking a scarce bottom-tab slot.
- Toasts are an `aria-live` region so they're announced to assistive tech.

## Mobile delivery: Hotwire Native target, PWA in dev
Decided in [[0005-mobile-hotwire-native-pwa-dev]]:

- **Production target — Hotwire Native** (formerly Turbo Native): a thin native
  iOS/Android shell renders our web views inside native screens; the app-level
  **tab bar + navigation are native** (path-configuration JSON, bridge components).
- **Development assumption — PWA**: the web app is an installable, responsive PWA
  (Propshaft + Open Props media/container queries; we are **not** on Tailwind).

Because we develop as a PWA, we **do build the responsive mobile web chrome**
(slim header, web tab bar when nav exists, popover-as-bottom-sheet) — but every
piece is **gated**: detect the native wrapper (custom user-agent) → add a
**`hotwire-native` body class** → hide web-only nav chrome so it never doubles up
with native nav. One toggle point.

Key point: **content is responsive on every surface** (desktop, mobile web, PWA,
wrapped Native). Hotwire Native only changes who owns the **navigation chrome**.
The top-right avatar/bell decision (ADR 0004) holds on desktop and mobile web;
inside the native app those may become native affordances.

The app already scaffolds a PWA (`app/views/pwa/manifest.json.erb`,
`service-worker.js`) that is **currently disabled** — enabling it (manifest link
in the layout, service-worker registration, `pwa` routes) is a near-term task.

## Gotchas / open questions
- **Notification bell is a stub** — the top-right bell has no panel/destination
  yet. Wire it (and real toasts beyond `flash`) with the notifications feature.
- **Bottom tab bar is deferred** — no primary-nav destinations yet, so it would
  be empty scaffolding. When built it's `.app-tabbar` (already gated for Native),
  Profile = far-right slot.
- **Native app track** — the Xcode/Android shell, path configuration, and bridge
  components are a later, separate effort; the `hotwire-native` gate is ready for it.
- **Service worker is a no-op** — registered for installability, but does no
  caching/offline yet.
