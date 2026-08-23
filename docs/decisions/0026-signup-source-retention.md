---
type: decision
title: Signup source retention — fingerprint the neighborhood, keep consent IPs, never visit IPs
status: accepted
tags: [rails, newsletter, privacy, deliverability, multi-tenancy]
created: 2026-08-23
updated: 2026-08-23
sources: [./0011-subscribers-and-consent-log.md, ./0025-canonical-delivery-events.md, ../log.md]
---

# 0026. Signup source retention — fingerprint the neighborhood, keep consent IPs, never visit IPs

## Context

One shared SES account carries every site's mail. A future "Person reputation
and suppression" batch (drawered; pulled on the first outside tenant or the
first paid list import) will want to detect *clusters* — many addresses opting
in to many sites from the same source in a burst — because that is what a
bought list or a bot run looks like, and it is the one signal that cannot be
rebuilt after the fact: suppression state can be re-derived from
`delivery_events` at any time, but where a signup came from exists only if it
was captured at the moment and never pruned.

That pressure arrived the same week the platform went the other way on IPs:
[2026-08-22] removed GeoIP and with it the only consumer of `ahoy_visits.ip`, so
`Ahoy::Store#track_visit` now drops the IP before the insert and
`DiscardAhoyVisitIps` wiped the historical rows, irreversibly. The question was
whether to walk that back "for this purpose."

Where the signal actually lives: a cluster is a property of **signups**, not
page views. The opt-in, confirm, and unsubscribe actions already write the
reader's real client IP (`request.remote_ip`, trusted-proxy config makes it the
`CF-Connecting-IP` behind the Worker) to `subscription_events.ip_address` as
consent evidence (ADR 0011). Ahoy's visit IP was /24-masked, belonged to every
visitor whether or not they ever signed up, and was never linked to a
subscriber. Re-storing it would mean retaining browsing IPs platform-wide for a
signal that already sits, unmasked, in a far narrower and better-purposed table.

## Decision

1. **Visit IPs stay gone, and the decision is final.** `ahoy_visits.ip` is never
   written; the historical wipe stands. Cluster detection will not use browsing
   telemetry. (`visitor_token` is not a cross-site signal either — ahoy's cookie
   is per-host and every site is its own host.)

2. **`subscription_events.ip_address` is the consent record, and its retention is
   the life of the subscriber row.** It is never pruned on its own. It leaves
   when the subscriber leaves: `PendingSubscriberPurgeJob` hard-deletes
   never-confirmed opt-ins at 30 days (their events cascade), and a confirmed /
   unsubscribed / bounced / complained subscriber is kept indefinitely as a
   suppression record, consent IP included — a dispute can arrive years after
   the unsubscribe, and the IP on the `subscribed`/`confirmed` events is the
   evidence. No new retention job; this records the existing behavior as the
   policy.

3. **Every consent event also carries a `source_fingerprint`** — the cross-site
   "same source?" input — computed at write time by
   `SubscriptionEvent.fingerprint(ip)`: HMAC-SHA256 of the IP's network
   neighborhood (IPv4 `/24`, IPv6 `/56`), keyed with a key derived from
   `secret_key_base` (`Rails.application.key_generator`, so nothing new to
   provision). Keyed, because the IPv4 space is small enough to brute-force an
   unkeyed hash; prefix, because "same neighborhood" is all a cluster query
   needs. It is indexed; future correlation queries read it and never the raw
   address. Backfilled from the raw IPs already on the rows.

4. **Every fingerprinted consent event also leaves an identity-free residue**
   on the platform: a `signup_sources` row — `account_id, source_fingerprint,
   action, created_at` — with no email, no person, no IP, and no foreign key to
   the subscriber (`SignupSource.trace`, called from `Subscriber#log_event!`).
   It exists to survive `PendingSubscriberPurgeJob`: never-confirmed opt-ins
   are exactly the population a cluster query wants (bought lists and bot runs
   don't click confirmation links), and their consent events cascade at 30
   days. The residue keeps the *source* after the *address* is gone. The purge
   itself is unchanged — stopping it would hold unconsented addresses, which
   is the worse privacy problem. Backfilled from the consent log's existing
   fingerprints. Append-only; read across accounts by design.

The point of separating (2) from (3) and (4): the durable thing is pseudonymous and the
identifying thing has a bounded, written-down life. If the raw IP's retention
is ever shortened (e.g. cleared some months after confirm), the cluster option
survives. Under GDPR a keyed pseudonym is still personal data — this lowers the
risk, it does not remove the category.

## Consequences

- The drawered suppression pitch's "do this now" item is closed: capture is
  deliberate, retention is stated, and the one signal that can't be backfilled
  is being written.
- Rotating `secret_key_base` would orphan every existing fingerprint (same as
  every signed token in the app). Acceptable; a rotation would want a one-time
  re-fingerprint while the raw IPs still exist.
- `signup_sources` grows by one row per fingerprinted consent event, forever.
  At newsletter scale that is nothing; it is also the one table here with no
  retention at all, which is deliberate and should be re-read if the platform
  ever needs a data-minimization statement — the row is pseudonymous and
  cross-account by construction, so it has nothing to minimize.
- A future cluster query is now a `GROUP BY source_fingerprint` over
  `signup_sources` (distinct accounts, time window) — no join to subscribers,
  no IP, no need to have been there at the time.
- `delivery_events` retention is a separate matter (the suppression pitch
  needs it to survive subscriber deletion — `dependent: :nullify` keyed on a
  future `person_id`) and is left to that batch.

## Alternatives considered

- **Re-enable masked IP storage on `ahoy_visits`** — rejected: wrong table for
  the signal (visits, not signups), platform-wide browsing data retained for a
  hypothetical, and unlinked to any subscriber anyway.
- **Store only the raw consent IP and query it directly** — rejected as the
  long-term shape: ties the cluster signal's life to the consent record's, so
  the raw IP could never get shorter retention without losing the option.
- **Unkeyed hash of the IP or prefix** — rejected: 2^32 IPv4 addresses (2^24
  prefixes) is a lookup table, not a pseudonym.
- **Stop purging pending subscribers** — rejected: the purge is the privacy
  commitment that makes holding the rest defensible; the residue row keeps the
  source signal without keeping the address.
- **Accept the 30-day window** (no residue) — rejected as a drawer decision:
  the whole reason to act now is that this signal cannot be backfilled later.

## Links

Related: [[0011-subscribers-and-consent-log]] · [[0025-canonical-delivery-events]]
· [[0017-phase-1-tenancy-model]] · Supersedes: — · Superseded by: —
