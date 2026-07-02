---
type: decision
title: Mobile delivery — Hotwire Native target, PWA in development
status: accepted
tags: [ui, mobile, hotwire-native, pwa, navigation]
created: 2026-07-02
updated: 2026-07-02
sources: [0004-top-bar-app-shell.md, ../concepts/app-shell.md]
---

# 0005. Mobile delivery — Hotwire Native target, PWA in development

## Context
[[0004-top-bar-app-shell]] left open *how* mobile navigation chrome is delivered:
responsive web (our CSS) vs. Hotwire Native (native tab bar). Alcovo is on the
37signals stack (edge Rails, Propshaft, importmap, Hotwire), where Hotwire Native
is the natural production path. But we must develop and test the mobile UI now,
before any native shell exists — and the app already scaffolds a PWA
(`app/views/pwa/manifest.json.erb`, `service-worker.js`, both currently disabled
in the layout/routes).

## Decision
- **Production mobile target: Hotwire Native.** A thin native shell renders the
  web views; the **tab bar and navigation are native** (path-configuration JSON,
  native bar items, bridge components).
- **Development assumption: PWA.** The web app is an installable, responsive PWA.
  We therefore **do build the responsive mobile web chrome** (slim top header,
  web tab bar when nav exists, popover-as-bottom-sheet) so the PWA is complete on
  its own and for mobile-web visitors.
- **Gate the web chrome.** Detect the native wrapper (custom user-agent) and add
  a **`hotwire-native` body class**; web-only nav chrome is hidden under that
  class so it never doubles up with native nav. Design every piece of web chrome
  to be suppressible from a single toggle point.
- **Content is responsive regardless** — the same web views serve desktop,
  mobile web, PWA, and (wrapped) Hotwire Native.

## Consequences
- One responsive web codebase serves all four surfaces; no separate mobile web
  app.
- **Enable the PWA scaffolding** (link the manifest in the layout, register the
  service worker, uncomment the `pwa` routes) — a concrete near-term task.
- Build web nav chrome behind a single `hotwire-native`-aware toggle so it can be
  hidden without rework when the native shell lands.
- The native app itself (Xcode/Android projects, path config, bridge components)
  is a **later, separate track**; nothing blocks web/PWA development now.
- Reconfirms ADR 0004's deferral of the bottom tab bar until real primary-nav
  destinations exist — PWA or Native, there is nothing to put in it yet.

## Alternatives considered
- **Pure responsive web, no native** — rejected as the *target* (the 37signals
  stack favors Native), but its output (responsive web + PWA) is exactly our dev
  substrate, so nothing is wasted.
- **Native-only chrome, skip PWA in dev** — rejected: we must exercise the mobile
  UI before a native shell exists, and mobile-web/PWA users need working chrome.

## Links
Refines: [[0004-top-bar-app-shell]] · Related: [[app-shell]] · Superseded by: —
