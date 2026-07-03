---
type: decision
title: Top-bar app shell — profile & notifications top-right
status: accepted
tags: [ui, layout, navigation, responsive, app-shell]
created: 2026-07-02
updated: 2026-07-02
sources: [../concepts/app-shell.md]
---

# 0004. Top-bar app shell — profile & notifications top-right

## Context
The base layout currently is: a transparent header (`.bar`) with the brand at
top-left, a centered canvas panel (`.main-content`) for content, and a footer
(`.footer`) whose **bottom-left avatar** opens a native-popover user menu.

Reviewing mobile vs. desktop behavior raised three questions: where the user
menu lives, where the notification bell lives, and where toasts appear. The
avatar's bottom-left placement is unconventional on desktop (the universal
convention is profile **top-right** — GitHub, Gmail, Notion) *and* collides with
the mobile bottom-nav "Home" slot, so it risks accidental taps there too.

The real fork underneath all of it: **is Alcovo a top-bar shell or a sidebar
shell?** That single choice determines avatar/bell placement. Bottom-left is only
correct at the foot of a *sidebar* (Slack/Discord/Linear) — not in a footer strip.

## Decision
Alcovo uses a **top-bar app shell**:

- **Desktop:** brand top-left; **user-menu avatar + notification bell top-right**
  in the header. Content stays in the centered canvas panel (good for long-form
  reading/writing).
- **Mobile:** a slim sticky top header keeps the avatar (and bell) top-right.
  Primary navigation will later move to a **bottom tab bar**, with **Profile as
  the far-right tab** (never far-left, which is reserved for Home/Dashboard).
- The user menu keeps the **native Popover API**: a dropdown on desktop, a
  **bottom-sheet** (slides up, thumb-reachable) on mobile via a media query.
- **Notifications:** bell top-right next to the avatar (desktop) / in the slim
  top header (mobile) — not a bottom-tab slot, since notifications are not
  Alcovo's engagement loop. **Toasts** slide in **bottom-right** on desktop and
  as a **top banner** on mobile, exposed via an `aria-live` region.
- The **footer avatar is retired** in favor of the header.

Sequencing: the **bottom tab bar is deferred** until real primary-nav
destinations exist (today there is only brand + user menu — a tab bar now would
be empty scaffolding). Notifications/toasts are built **with** the notifications
feature, not before.

## Consequences
- Matches the near-universal profile-top-right convention; removes the mobile
  Home-slot collision risk.
- Fits the centered reading canvas (no sidebar eating horizontal space).
- Small, reversible first step: move the existing avatar + popover to the header
  top-right and make the popover responsive.
- **Reverses the earlier "avatar bottom-left" placement.** The footer is freed
  for other chrome or removed.
- Responsive is done with our **own CSS media/container queries** on existing
  components (`.bar`, `.menu`, etc.) — this project is Propshaft + Open Props,
  **not Tailwind**.
- Mobile bottom tab bar, notification bell, and toast region are **planned, not
  built** — tracked in [[app-shell]].
- **Open sub-decision:** whether mobile navigation chrome is **responsive web**
  (our CSS: slim header + bottom tab bar + bottom-sheet popover) or **Hotwire
  Native** (native tab bar + path config; suppress web chrome via a
  `hotwire-native` body class). The web app stays mobile-responsive either way;
  Hotwire Native only changes who owns the nav chrome. Needs its own ADR once
  chosen. This top-bar / top-right decision holds regardless. See [[app-shell]].

## Alternatives considered
- **Left sidebar shell, avatar at bottom** (Slack/Discord/Linear) — rejected for
  now: bigger rebuild (a real sidebar, not a footer), and it eats horizontal room
  the reading canvas wants. Revisit if navigation and account/community switching
  (we are multi-tenant) grow rich enough to justify persistent side nav.
- **Keep the footer avatar bottom-left** — rejected: worst of both worlds —
  unconventional on desktop and colliding with the mobile Home slot.

## Links
Related: [[app-shell]] · Refined by: [[0005-mobile-hotwire-native-pwa-dev]] (mobile mechanism) · Supersedes: — · Superseded by: —
