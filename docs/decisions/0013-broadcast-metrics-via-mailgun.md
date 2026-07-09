---
type: decision
title: Broadcast metrics via Mailgun event webhooks
status: accepted
tags: [rails, newsletter, email, metrics, mailgun]
created: 2026-07-09
updated: 2026-07-09
sources: [./0012-broadcast-posts-as-newsletters.md]
---

# 0013. Broadcast metrics via Mailgun event webhooks

## Context
Broadcasts ([0012](./0012-broadcast-posts-as-newsletters.md)) need the usual
newsletter metrics — delivered, opens, clicks, bounces, unsubscribes — surfaced
on an admin dashboard. Mailgun is the chosen relay; it reports these as event
webhooks (and echoes back custom variables we set on each message).

## Decision
Capture metrics **per recipient**, aggregate for the dashboard:

- **`broadcast_deliveries`** gains engagement timestamps (`delivered_at`,
  `opened_at`, `clicked_at`, `bounced_at`, `complained_at`, `unsubscribed_at`),
  stamped **first-event-wins** — so opens/clicks count *unique* recipients.
- **`broadcasts`** caches aggregate counters (`delivered_count`, `opened_count`,
  …) bumped on each delivery's first transition, so the dashboard reads without
  per-row aggregation. Rates (`open_rate` = opened/delivered, etc.) are derived.
- **Mapping:** each email carries `X-Mailgun-Variables` with `broadcast_id` +
  `subscriber_id`; Mailgun echoes them on every event, so
  `Webhooks::MailgunController` resolves the exact `BroadcastDelivery` and calls
  `record_event!`. A Mailgun-side `unsubscribed` also drops the subscriber from
  our list (logged in the consent trail).
- **Auth:** the webhook is a machine endpoint (`ActionController::Base`, no
  browser/forgery/session concerns); authenticity is the Mailgun HMAC signature
  verified against the webhook signing key. Unknown/unmatched events return 200
  so Mailgun doesn't retry forever.
- **Dashboard:** `admin/broadcasts` — domain-admin only (`BroadcastPolicy`),
  read-only; sending stays on the post page.

## Consequences
- Unique opens/clicks and per-recipient engagement come for free from the
  delivery rows; the dashboard stays a cheap counter read.
- Metrics are only as live as the webhooks; a missed webhook undercounts (no
  reconciliation poll against Mailgun's Events API — a possible follow-up).
- **Deployment config (not in the app):** set the Action Mailer delivery method
  to Mailgun for production (dev keeps `letter_opener`); provide the API
  sending credentials; and set the **webhook signing key** via
  `credentials[:mailgun][:webhook_signing_key]` (or `MAILGUN_WEBHOOK_SIGNING_KEY`).
  Point a Mailgun webhook at `POST /webhooks/mailgun` for the delivered / opened
  / clicked / permanent-fail / complained / unsubscribed events, and enable
  open/click tracking (the mailer also sets the per-message track headers).
- Replay protection is signature-only for now (no timestamp-freshness/token
  dedup) — fine to add later if abuse appears.

## Alternatives considered
- **Counters only on `broadcasts`** (increment per event) — rejected: can't
  dedup to unique opens/clicks without per-recipient state, and loses
  per-subscriber engagement.
- **Poll Mailgun's Stats/Events API** instead of webhooks — simpler auth, but
  laggy and rate-limited; webhooks are push and exact. Could be added as a
  reconciliation backstop.

## Links
Related: [[0012-broadcast-posts-as-newsletters]]
