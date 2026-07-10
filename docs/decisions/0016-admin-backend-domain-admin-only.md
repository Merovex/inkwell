---
type: decision
title: Admin backend is domain-admin-only; auth + account move out of /admin
status: accepted
tags: [rails, authorization, admin, authentication, roles]
created: 2026-07-10
updated: 2026-07-10
sources: [./0011-subscribers-and-consent-log.md]
---

# 0016. Admin backend is domain-admin-only; auth + account move out of /admin

## Context
`/admin` had grown to hold three different things behind one namespace: the
domain-admin **install management** (settings, subscribers, broadcasts,
analytics, authors, categories), authenticated **content authoring** (posts,
messages, chat, books, series — open to any signed-in member with per-record
creator-or-admin policies), and the **entry points** every user needs
(passwordless sign-in, first-run setup, open signup, and the signed-in user's
own profile). Only the install-management sections were actually gated to
`domain_admin`; the authoring sections merely required a session, so a member
could reach `/admin/posts` and friends. For a single-author press this blurred
"the author's backend" with "anything a logged-in person can do."

## Decision
Make **everything that stays under `/admin` require `domain_admin`**, and move
the things that aren't admin actions out of the namespace.

- **`Admin::BaseController`** — inherits `ApplicationController` (which already
  forces authentication) and adds `AdminOnly` (`require_admin`). Every backend
  controller inherits it, so a signed-in non-admin gets the same 404 as a
  missing record. The `/admin` root and static styleguide stay public dev refs.
- **Authentication moves to the top level** — `SessionsController`,
  `SetupsController`, `SignupsController` at `/session`, `/setup`, `/signup`
  (was `/admin/…`). You can't be an admin before you're signed in, so these
  can't live behind the admin gate.
- **The user's own account moves to the top level** — `User::SettingsController`
  + `User::AvatarsController` at `/user/settings`, `/user/avatar`. Managing
  yourself isn't a domain-admin action; it just needs a session.
- **Comments and boosts are the deliberate exception** — their controllers
  inherit `ApplicationController` (session required, admin **not**), so they
  stay usable by non-admins. They still render inside the (now admin-only)
  post/message pages, so today only admins reach them; the auth-only gate is
  forward-looking for a future member/public surface.
- **First user is safe** — `Setup#save` still creates the first user as
  `domain_admin`, so the owner is never locked out.

## Consequences
- The backend is now unambiguously the author's: one gate (`Admin::BaseController`),
  and new admin controllers inherit it by default rather than each remembering
  `include AdminOnly`.
- **The member content-authoring model is retired for now** — members can no
  longer author posts/messages/chat, and the creator-vs-admin visibility tests
  that exercised it were reworked or dropped. Open signup creates members who
  currently have no backend to use (kept for the future participation surface).
- Comments/boosts endpoints are reachable by any member but, with no public
  page hosting them yet, only admins exercise them in practice.
- Tests reflect the new model: the content-fixture author (`alice`) is now a
  `domain_admin`; `bob` is the member used to prove non-admins are denied.
- **Deploying this is a behaviour change**: sign-in moves from
  `/admin/session/new` to `/session/new`, and non-admins lose `/admin`.

## Alternatives considered
- **Keep per-section `AdminOnly`** (status quo) — leaves authoring open to any
  member; rejected as the source of the blur this ADR removes.
- **Full lockdown including comments/boosts** — simplest gate, but kills the
  only member-facing participation surface; rejected in favour of exempting
  those two.

## Links
Related: [[0011-subscribers-and-consent-log]] · [[0012-broadcast-posts-as-newsletters]]
