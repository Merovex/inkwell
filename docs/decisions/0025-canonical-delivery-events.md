---
type: decision
title: Canonical delivery events — one vocabulary, two ESP adapters
status: accepted
tags: [rails, newsletter, email, ses, postmark, deliverability, bounces, suppression]
created: 2026-08-05
updated: 2026-08-05
sources: [./0015-email-relay-mailgun-to-ses.md, ./0011-subscribers-and-consent-log.md, ./0014-subscriber-sunset.md]
---

# 0025. Canonical delivery events — one vocabulary, two ESP adapters

## Context

We run two ESPs and want to keep both live: **Postmark** carries the critical
path (auth, subscriber confirmations), **SES** gets applied judiciously — the
current thinking is once a subscriber or User is trusted. Bounce/complaint
handling must therefore work identically regardless of which ESP produced the
event. Before this decision, each webhook controller mapped its provider's
vocabulary straight onto delivery milestones and subscriber suppression inline,
with no shared model, no raw-payload retention, no dedupe, and no way to
attribute an event to the exact send that caused it.

## Decision

**Normalize at the boundary, not at the handler.** Each provider webhook lands
in its own controller (`Webhooks::PostmarkController`, `Webhooks::SesController`),
verifies its own authenticity (Basic Auth / SNS signature), and translates into
one canonical **`DeliveryEvent`**. Everything downstream — milestone stamping,
suppression, subscriber status — reads only the canonical form and never knows
which ESP produced it.

Canonical vocabulary: `delivered, opened, clicked, soft_bounce, hard_bounce,
complaint, suppressed, rejected`.

The mapping, with the traps marked:

| Provider signal | Canonical |
|---|---|
| SES `Permanent` (`General`, `NoEmail`, …) | `hard_bounce` |
| SES `Permanent` / `Suppressed`, `OnAccountSuppressionList` | **`suppressed`** — never sent, AWS blocked it |
| SES `Transient`, `Undetermined` | `soft_bounce` |
| SES `Complaint` | `complaint` |
| SES `Reject`, `RenderingFailure` | `rejected` — never left AWS, not the recipient's fault |
| Postmark `HardBounce` (or `Inactive`) | `hard_bounce` |
| Postmark `Blocked` | **`rejected`** — ISP policy, mailbox may be fine |
| Postmark `SoftBounce`, `Transient`, … | `soft_bounce` |
| Postmark `SpamComplaint`, `SpamNotification` | `complaint` |

The two bolded rows are where naive mappings lose subscribers: `suppressed`
means the ESP refused because the address was already on its own list (nothing
new about the mailbox); `rejected` is about **our** sending reputation, not
their address. **Neither may touch the subscriber** — suppressing either as a
hard bounce quietly kills live subscribers while hiding the sending problem
that caused it. Both are record-only, kept for the future reputation firewall.

Four things that make it hold:

1. **Raw payload stored** alongside every canonical event — a wrong mapping can
   be replayed rather than guessed.
2. **Dedupe on `[provider, provider_message_id, event]`** (unique index) — both
   providers retry, SNS delivers at-least-once. Side effects fire only when the
   row is new (`DeliveryEvent.ingest!`).
3. **Correlation at dispatch** — `DeliveryEvent.dispatch_stamp(message)` reads
   the carrying ESP and its message id off the header the delivery method
   writes back (`X-PM-Message-Id` / `ses_message_id`) and stamps them on the
   `BroadcastDelivery`/`DropDelivery` at send time. Metadata/tags remain the
   webhook routing key; the message id is the audit trail.
4. **Our database is authoritative, not AWS's suppression list.** Disable SES
   account-level auto-suppression (or at minimum treat a `suppressed` event for
   a subscriber we think is `confirmed` as a drift alarm). Otherwise AWS
   silently drops mail we believe we sent and `Subscriber.status` drifts from
   reality.

Subscriber state stays a cached current-state derived from events:
`hard_bounce → bounced`, `complaint → complained` (a new status — "marked us
spam" and "asked to leave" are different facts, and complaint rate is the
firewall's signal; it is the strongest suppression and only a fresh double
opt-in revives it), and soft bounces suppress only after
`DeliveryEvent::SOFT_BOUNCE_LIMIT` (3) consecutive failures with no delivery in
between.

## Out of scope (follow-ups)

- The **reputation firewall** itself (pausing sends on bounce/complaint/reject
  rates) — this decision builds the substrate it will read.
- The Postmark→SES **routing rule** ("trusted" subscribers/users ride SES) —
  the event pipeline is already indifferent to it.
