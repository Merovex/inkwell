---
type: decision
title: Person suppression ledger — cross-site bounce/complaint suppression, one guard in the send path
status: accepted
tags: [rails, newsletter, email, ses, deliverability, suppression, multi-tenancy]
created: 2026-08-23
updated: 2026-08-23
sources: [./0025-canonical-delivery-events.md, ./0026-signup-source-retention.md, ./0002-domain-vocabulary-person-user-account.md, ../ses-tenants.md]
---

# 0027. Person suppression ledger — cross-site bounce/complaint suppression, one guard in the send path

## Context

One SES account carries every site's mail. Per-site SES tenants (2026-08-06)
contain the *reputation* blast radius — a bad list pauses that tenant, not the
account — but nothing stopped author B from mailing an address that had
already hard-bounced for author A. Every deliverability signal (`delivery_events`,
`broadcast_deliveries.bounced_at`, `subscribers.status`) was keyed to
Subscriber, which is one site's row; `people` is the only cross-site identity
and tracked nothing but timestamps. With one tenant the gap was invisible; the
point of writing it down was to close it before a second tenant finds it.

Settled before this decision, and relied on here: ADR 0025 makes our database
the authoritative suppression list (SES account-level auto-suppression is off;
`OnAccountSuppressionList` bounces are record-only `suppressed`), so what is
built here is authoritative, not a mirror. ADR 0026 closed the retention
question for the signals that can't be backfilled.

## Decision

**Ledger plus projection.** `delivery_events` (and the consent log) remain the
record; a narrow `suppressions` table is the index the send path reads. If the
projection is ever doubted it is rebuilt from the ledgers (`Suppression.rebuild!`).

1. **`delivery_events.person_id`.** Resolved at ingest — the delivery's
   subscriber's person, or a lookup of the normalized recipient address
   (found, never created). Backfilled. This makes the ledger queryable by
   identity and makes confirmation-email bounces — which carry no delivery
   tags and so had no subscriber to act on — actionable. The ledger now
   **outlives the subscriber**: `dependent: :nullify` (was `:delete_all`) on
   Subscriber, BroadcastDelivery and DropDelivery, so a purged row lets go of
   its events rather than taking them along.

2. **`suppressions`** — `person_id, reason, scope_type/scope_id, lifted_id,
   created_at`. Append-only (`before_update` raises). `scope` nil means every
   site; an Account means that site only. A **lift is a row** pointing at the
   row it lifts (`lifted_id`), never an update or delete — who un-suppressed
   what, and when, stays on record. Reasons: `hard_bounce`, `complaint`,
   `manual` impose; `manual`, `reconfirmed` lift.
   - *Hard bounce* → imposed globally. A dead mailbox is a fact about the
     address, not one author.
   - *Complaint* → imposed for the Account that sent the mail (a reader who
     flags A as spam may still want B); escalates to a global row once
     `ESCALATE_AFTER` (2) distinct sites are involved. A complaint we cannot
     attribute to a site is imposed globally (the safer reading).
   - *Soft bounces* write nothing here. The existing streak rule still
     suppresses the Subscriber after three in a row with no delivery between,
     but that is not a fact about the mailbox for other sites.
   - *Reconfirmed* (`Subscriber#confirm!`) lifts every global row (a click
     from the mailbox is proof of life, and a fresh double opt-in is stronger
     than a stale bounce) and that site's own rows (a complaint here, answered
     by a fresh opt-in). The confirmation email itself is **not** guarded: it
     is the proof-of-life probe, and it was the documented revival path for a
     bounced subscriber already.
   - *Manual* (`Subscriber#reactivate!`, bounced → confirmed) lifts for **that
     site only** — site-scoped lifts of a global row free that site and no
     other. One site's say-so never speaks for another. Complained subscribers
     are re-invited, so their lift is the reconfirmed one.
   - Idempotent imposition: an identical row already binding at that exact
     scope is not written again (webhook retries, rebuilds).

3. **`Person#suppressed?` / `Person#suppressed_for?(account)`**, and
   `Subscriber#suppressed?` (= `person.suppressed_for?(account)`) for the send
   path. Nothing else: no score, no cluster, no thresholds. (The pitch asked
   for a `Person::Reputation` PORO; two one-line predicates didn't earn a
   class — reviewed out the same day.)

4. **One guard, two call sites.** `PostBroadcastJob#perform` skips a
   suppressed recipient before any delivery row exists (logged);
   `Stream#advance!` records `skipped` / `skip_reason: "suppressed"`. Not a
   validation, not a callback. Both ask `subscriber.suppressed?`, which keys
   on `person`, never on the `subscribers.email_address` copy.

5. **Read-only admin list** — `/admin/suppressions` (`resources
   :suppressions, only: :index`): suppressions in force for this site whose
   person is on this site's list, with reason, scope ("Every site" / "This
   site") and date. Linked from the roster. No management UI by design.

`rebuild!` replays both ledgers in time order: delivery events impose,
`confirmed`/`reactivated` consent events lift. Pre-ADR-0025 bounced/complained
subscribers (before the ledger existed) are deliberately not reconstructed:
their status already blocks them on the one site that existed, and the ledger
is the only cross-site authority.

## Consequences

- A hard bounce anywhere now blocks the address everywhere, at send time,
  without touching any other site's roster row — the other site's reader is
  still "confirmed" there, just not mailed, and the admin list says why.
- `Subscriber.status` keeps its meaning (this list's consent/delivery state);
  unsubscribe stays a different concept in a different table, permanently.
- Ops precondition is unchanged and now load-bearing for two reasons: SES
  account-level **and** tenant-level auto-suppression stay off. To verify in
  the console, not in code. Also verify the transactional config set publishes
  bounce/complaint events to the same SNS topic — otherwise confirmation-email
  bounces never arrive.
- Not done, by design (the pitch's no-gos): cluster detection, counter columns
  on `people`, scoring, management UI, or marketing any of this as a feature.
- Follow-up, separate: dropping the `subscribers.email_address` duplicate of
  `people.email_address` — touches validations, `opt_in`, both mailers and an
  index. Harmless to this decision because every check resolves via `person_id`.

## Alternatives considered

- **Mirror SES's suppression list** — rejected; ADR 0025 already chose the
  database as authoritative, and AWS's list silently drifts `Subscriber.status`.
- **A boolean on `people`** — rejected: loses who/when/why, can't scope a
  complaint to one site, can't be lifted without erasing history.
- **Lifts as updates/deletes** — rejected: the history of un-suppression is
  the part an ops question will actually ask about.
- **Guard as a model validation or callback** — rejected: the send decision
  belongs in the one place sends originate, visible and loggable.
- **Suppress on soft-bounce streak globally** — rejected: mailbox-full for one
  author's three sends is not evidence for the next author.
- **Suppress the confirmation email** — rejected: it is the proof-of-life
  probe and the documented revival path; one transactional mail to a possibly
  dead mailbox is the cheapest test there is.

## Links

Related: [[0025-canonical-delivery-events]] · [[0026-signup-source-retention]]
· [[0011-subscribers-and-consent-log]] · [[ses-tenants]] · Supersedes: — · Superseded by: —
