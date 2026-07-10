---
type: decision
title: Email relay — migrate Mailgun → Amazon SES/SNS
status: accepted
tags: [rails, newsletter, email, ses, sns, mailgun, migration, deliverability]
created: 2026-07-10
updated: 2026-07-10
sources: [./0013-broadcast-metrics-via-mailgun.md, ./0011-subscribers-and-consent-log.md]
---

# 0015. Email relay — migrate Mailgun → Amazon SES/SNS

## Context
All app email — transactional (`SessionMailer` magic links) and marketing
(`SubscriberMailer` confirm/re-engage, `PostBroadcastMailer` issues) — currently
relays through **Mailgun** via Action Mailer's `:mailgun` delivery method, with
per-recipient metrics ingested from Mailgun event webhooks ([0013](./0013-broadcast-metrics-via-mailgun.md)).

Two forces drive a move to **Amazon SES** (send) + **SNS** (events):

- **Cost** — SES is ~$0.10/1k emails with no monthly minimum; Mailgun's floor is
  the pain point at our ~1k/month scale. Target: cut over **before the next
  Mailgun monthly invoice**.
- **Data ownership / control** — own the event pipeline rather than depend on
  Mailgun as a metrics broker (the [0013](./0013-broadcast-metrics-via-mailgun.md)/0014 dependency concern).

Constraints: the app is **self-hosted (Kamal, not on AWS)**, so SES/SNS are
external APIs exactly like Mailgun is today. The **subscriber sunset** (ADR 0014)
depends on open/click engagement, so open/click tracking **must be preserved**.

## Decision
**Hard cutover** to SES/SNS, keeping the [0013](./0013-broadcast-metrics-via-mailgun.md)
metrics data model (`broadcast_deliveries` timestamps + cached `broadcasts`
counters) intact and swapping only the relay and the event-ingest mechanism.

- **Send path:** Action Mailer `:ses_v2` via `aws-sdk-rails` (SES API v2), not
  SMTP — native Configuration Set + message-tag support for tracking and event
  mapping, cleaner credentials.
- **Open/click:** SES **Configuration Sets** with open+click tracking and a
  **custom (branded) tracking domain**. Two sets:
  `inkwell-marketing` (open+click ON) and `inkwell-transactional`
  (bounce/complaint only — we don't track magic-link opens).
- **Event→recipient mapping:** replace `X-Mailgun-Variables` with SES **message
  tags** (`broadcast_id`, `subscriber_id`; tag charset `[A-Za-z0-9_-]`, our
  integer IDs fit). SES echoes tags on every event.
- **Event ingest:** **SNS → HTTPS webhook** (`POST /webhooks/ses`), mirroring the
  existing machine-endpoint pattern — no new AWS infra on the Kamal box, and
  `record_event!` is already idempotent (first-event-wins), so SNS's
  at-least-once delivery is harmless. Authenticity via SNS signature
  (cert-based, `Aws::SNS::MessageVerifier`); the controller also auto-confirms
  the SNS `SubscriptionConfirmation` handshake.
- **Event map** (SES type → existing column/counter): `Delivery`→`delivered_at`,
  `Open`→`opened_at`, `Click`→`clicked_at`, `Bounce`(Permanent)→`bounced_at`,
  `Complaint`→`complained_at` (+ `unsubscribe!`), `Reject`/`RenderingFailure`→
  bounce. Transient bounces / `DeliveryDelay` are logged, not stamped. **SES has
  no `unsubscribed` event** — our RFC 8058 one-click POST already hits our own
  controller directly, so that path is unchanged (one fewer moving part).
- **Suppression:** **app-side `Subscriber` is source of truth** (preserves the
  [0011](./0011-subscribers-and-consent-log.md) consent trail); a permanent
  bounce/complaint flips status app-side, and **SES account-level suppression**
  is enabled as a redundant net against re-sending to hard bounces.

**Rollout is phased; the AWS/DNS prerequisites gate the cutover:**

- **Phase 0 — AWS/DNS (no app code; user-assisted "handholding"):** IAM
  least-privilege user; verify sending domain + Easy DKIM (3 CNAMEs); custom
  MAIL FROM subdomain (MX + SPF) for alignment; DMARC (`p=none` to start);
  custom open/click tracking domain (CNAME); the two Configuration Sets with SNS
  event publishing; SNS topic + HTTPS subscription; enable account suppression;
  **request production access (sandbox exit)** — ~24h lead time, and AWS wants
  bounce/complaint handling deployed first.
- **Phase 1 — Sending:** add `aws-sdk-rails` (keep `mailgun-ruby` one release for
  rollback); `production.rb` → `:ses_v2` + region/creds + `default_url_options`
  host off the new credential namespace; `ApplicationMailer` default `from:`;
  swap `PostBroadcastMailer` `X-Mailgun-*` headers for `X-SES-CONFIGURATION-SET`
  + `X-SES-MESSAGE-TAGS`; tag transactional mailers with the transactional set.
- **Phase 2 — Ingest:** `Webhooks::SesController` (SNS confirm + signature +
  event parse); generalize `BroadcastDelivery::EVENTS` to a provider-neutral map
  with Permanent/Transient bounce discrimination; `post "webhooks/ses"`.
- **Phase 3 — Cutover & cleanup:** validate end-to-end in the SES sandbox
  (verified recipients); flip in prod once production access + DNS are green
  (rollback = revert the `delivery_method` config); watch SES guardrails
  (<5% bounce, <0.1% complaint); remove `mailgun-ruby`, `:mailgun` credentials,
  `Webhooks::MailgunController` + route, `X-Mailgun-*` headers.

## Consequences
- The metrics dashboard, per-recipient engagement, and unique open/click
  semantics from [0013](./0013-broadcast-metrics-via-mailgun.md) survive
  unchanged — only the relay and ingest controller are swapped.
- **SES open tracking is noisier/less reliable than Mailgun's** — open/click is
  preserved (the hard requirement), but the ADR 0014 sunset thresholds
  (90d/6-email) may over-drop and should be re-tuned after observing real SES
  open rates.
- **Click tracking rewrites body links** (including "view on web" and the in-body
  unsubscribe link) through the tracking domain; the `List-Unsubscribe` **header
  is not rewritten**, so RFC 8058 one-click stays clean.
- **Production-access lead time is the schedule risk** for a hard cutover —
  everything else stages behind it. File the request early to hit the
  before-next-invoice target.
- **Deployment config (not in the app):** provide `credentials[:ses]` (region,
  IAM key/secret, from, host, tracking/config-set names) and the SNS webhook
  path `POST /webhooks/ses`; complete all Phase-0 DNS records; keep dev on
  `letter_opener`.

## Alternatives considered
- **SES SMTP interface** instead of API v2 — minimal code change, but
  config-sets/tags go through clunky headers and credentials are a second secret
  to manage; API v2 is the cleaner fit for tag-based event mapping.
- **SNS → SQS → poll** instead of an HTTPS webhook — more durable, no public
  endpoint, but adds an SQS queue + SDK poller to operate for no benefit at our
  volume; the idempotent ingest already tolerates duplicates. A later upgrade
  path if volume grows.
- **SES account suppression as sole source of truth** — less app code, but a
  weaker audit trail and harder to reconcile against the consent log; rejected
  in favor of app-side-primary with SES as a net.
- **Gradual dual-run behind a delivery abstraction** — safer, but the app is
  still in development and the cost/timeline pressure favors a hard cutover with
  a config-revert rollback.

## Links
Related: [[0013-broadcast-metrics-via-mailgun]] · [[0011-subscribers-and-consent-log]] · [[0012-broadcast-posts-as-newsletters]]
Supersedes: [[0013-broadcast-metrics-via-mailgun]] (the Mailgun relay + webhook specifics; the metrics data model carries forward)
