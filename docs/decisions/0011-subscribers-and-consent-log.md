---
type: decision
title: Subscribers — current-state row + append-only consent log
status: accepted
tags: [rails, newsletter, privacy, public-site]
created: 2026-07-08
updated: 2026-07-08
sources: [../overview.md]
---

# 0011. Subscribers — current-state row + append-only consent log

## Context
The public Merovex Press site has "Join the Newsletter" CTAs. We need to capture
mailing-list opt-ins with a legally sound consent trail (GDPR/CAN-SPAM: prove
opt-in, honor and retain unsubscribes) — and handle the re-subscribe case
(unsubscribe, then opt in again months later) without losing history. Capture,
double-opt-in confirmation email, and management are in scope; *broadcast*
sending (composing and mailing the actual newsletters) is not.

## Decision
Two tables, deliberately **off** the Record/Recordable spine:

- **`subscribers`** — one row per email (unique index dedupes), holding the
  *current* state: `status` (`pending` → `confirmed` → `unsubscribed`),
  `confirmed_at`, `unsubscribed_at`, `source`, `consent_ip`. A projection.
- **`subscription_events`** — an **append-only** log, one immutable row per
  transition (`subscribed` / `confirmed` / `unsubscribed` / `resubscribed`) with
  `ip_address`, `source`, `created_at` (no `updated_at`; `before_update` raises
  `ReadOnlyRecord`). This is the legal proof-of-consent trail.

**Double opt-in** is the consent proof: an opt-in always lands `pending` until a
tokened confirmation link flips it (`Subscriber.generates_token_for
:confirmation`, expiring, folding in `confirmed_at`). Every email carries a
stable `:unsubscribe` token. Re-subscribe reuses the same `subscribers` row and
**appends** a `resubscribed` event — the timeline is reconstructable; the row
says where they stand today. Unsubscribe never deletes — the row is retained as
a suppression record.

Subscribers are **not** users (no session/role/login) and **not** recordables
(no body to diff; the spine's `purge_after` would fight retention). Spam is
filtered by a honeypot + time-to-submit trap (`invisible_captcha`) plus a create
`rate_limit`, mirroring the auth controllers. The admin roster is domain-admin
only (`SubscriberPolicy`) with CSV export as the bridge to an external sender.

## Consequences
- Full consent history survives re-subscribe cycles; each opt-in is independently
  evidenced (when/where/IP).
- Immutable event rows mean the log is audit-grade, at the cost of a second table
  and deriving/caching current status on the `subscribers` row.
- `Subscriber.opt_in` emails the tokened confirmation link
  (`SubscriberMailer#confirmation`, `deliver_later`) whenever the result is
  pending; broadcast/newsletter sending remains unbuilt.
- When multi-tenancy arrives, `subscribers` gains `account_id` like the other
  install-scoped tables.

## Alternatives considered
- **Single mutable row** (flip `confirmed_at`/`unsubscribed_at` in place) —
  rejected: overwrites lose the re-subscribe history and the consent evidence.
- **Put subscribers on the Record spine** — rejected: content-versioning
  machinery (bodies, diffs, `purge_after`) is the wrong tool and its purge path
  works against legally required retention.
- **Fold subscribers into `users`** — rejected: drags sessions/roles/auth into
  what is just an email on a list.
