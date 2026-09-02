---
type: decision
title: Notifications — stamped copy, bell + tiered email digests
status: accepted
tags: [notifications, email, solid-queue, ui]
created: 2026-08-05
updated: 2026-08-05
sources: [0023-circles-cross-account-buckets.md]
---

# 0024. Notifications — stamped copy, bell + tiered email digests

## Context

Circles brought person-to-person acts (invitations, mentions, boosts, replies,
pulse asks) that the recipient should hear about. Early prototypes referenced
the source record at render time — and died with it (accepting an invitation
destroys the invitation, taking its notification's copy along). The owner's
brief: bell + email, calm by default, "we don't want to bug people."

## Decision

One generic **`Notification`** row per event: recipient, `kind`, polymorphic
`source`, and **its own stamped copy** — actor, title sentence, and URL are
computed once at delivery (`Notification.deliver`, the single choke point) so
a row outlives its source. Sources nullify on destroy; deleting notifications
is an explicit act on revoke/decline paths only.

Channels, per kind:

- **Bell always** — live Turbo Stream prepend + a red dot (ping animation);
  opening the flyout marks all read. A 30-day `/notifications` page backs the
  15-row flyout; read rows prune after 30 days.
- **Email for the digest-worthy kinds only**, batched, and reading in-app
  first cancels the email. Two cadences share one `NotificationDigestJob`:
  every 4 hours for `invited` + `mentioned`; **once a day** for `replied`
  (thread chatter, `EMAILED_DAILY`). `boosted` and `invitation_accepted` are
  bell-only; `pulse_asked` is bell-only because PulseMailer already sends the
  question.

## Consequences

- Notification rendering needs no joins and can never raise on a dead source;
  the cost is copy frozen at delivery (a renamed circle keeps its old name in
  old rows — acceptable for a 30-day shelf life).
- New kinds are cheap: a `KINDS` entry, a `copy_for` case, and a cadence
  choice. `replied` (thread participants minus the commenter, mention wins
  over reply for the same comment) landed exactly this way.
- The digest job is idempotent per cadence via `emailed_at`; the recurring
  schedule owns cadence, not the model.

## Alternatives considered

- **Render-time copy from live sources** — broke the moment sources were
  destroyed; keeping sources alive just for notifications inverts ownership.
- **Immediate per-event email** — noisy; rejected on the "calm" principle.
- **Single 4-hour cadence for everything** — the owner explicitly demoted
  replies to daily; cadence is a per-kind editorial choice.

## Links

Related: [[notifications]] · [[circles]] ·
Supersedes: — · Superseded by: —
