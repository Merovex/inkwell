---
type: concept
title: Domain vocabulary
status: active
tags: [naming, data-model, glossary]
created: 2026-07-01
updated: 2026-08-05
sources: [decisions/0002-domain-vocabulary-person-user-account.md, decisions/0023-circles-cross-account-buckets.md]
---

# Domain vocabulary

Canonical names for Inkwell's core concepts, as **shipped** — the 0002 shape
evolved in practice (noted below). Use these words in code, docs, and UI.

## Identity & tenancy

- **`User`** — the global, email-based login (magic links). One email = one
  User, across every site and circle. *(0002 planned a `Person` login with
  per-account `User` rows; in practice the login itself is `User`.)*
- **`AccountUser`** — a User's membership in one Account.
- **`Account`** — the tenant: an author's **site**. User-facing word is
  **"site"** — never "press" (owner directive, 2026-07-31; "Merovex Press"
  survives only as that site's brand name).
- **`Person`** — the *reader* identity: one row per email across every site's
  newsletter audience; `Subscriber` is a Person's membership in one site's
  list. Not a login.
- **`bucket`** — REVIVED (0002 retired it; [[0023-circles-cross-account-buckets]]
  brought it back): the polymorphic owner of a `Record` — an `Account`, a
  `Circle`, or a `User`. `Current.bucket` is the active one; account
  namespaces leave it unset and fall back to `Current.account`.

## Community & progress

- **`Circle`** — an invite-only, cross-account author group (a bucket).
  `CircleMembership` (owner + members), `CircleInvitation` (the only door).
- **`Pulse`** — a circle's scheduled check-in question; **`Beat`** — one
  member's answer to one ask.
- **`Goal`** / **`Tally`** — personal progress tracking on the User bucket;
  see [[goals]].
- **`Boost`** — an emoji reaction on a record (site or circle side).
- **`Notification`** — the bell's rows; see [[notifications]].

## Content spine (unchanged)

`Record` (envelope: bucket, creator, parent, trash/archive) ──
`Recordable` versions (`Post`, `Message`, `Comment`, `Book`, `Series`,
`Beat`, `Goal`, `Tally`, …). See
[[0006-record-recordable-generic-spine]] / [[0007-versioned-recordables]].

## Translation table (when reading source/research)

| Inkwell (shipped) | Fizzy source | 0002 plan | Old notional docs |
|-------------------|--------------|-----------|-------------------|
| `User` (global login) | `Identity` | `Person` | `Person` |
| `AccountUser` / `CircleMembership` | `User` | `User` | `Membership` |
| `Account` ("site") | `Account` | `Account` | `Group` / `bucket` |
| `bucket` (polymorphic Record owner) | `bucket` | — (retired, revived) | `bucket` |
