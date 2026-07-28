---
type: decision
title: Phase 1 tenancy model — explicit account-start scoping on the Record spine
status: accepted
tags: [rails, multi-tenancy, accounts, scoping, fizzy]
created: 2026-07-28
updated: 2026-07-28
sources: [../multi-tenancy.md, ../saas-static-hosting-plan.md, ~/Work/fizzy]
---

# 0017. Phase 1 tenancy model — explicit account-start scoping on the Record spine

## Context
Phase 1 of the delivery plan makes every row and query account-aware while the
live Merovex Press tenant serves unchanged. The plan document left several
model-level choices open, and a read of the actual Fizzy source (`~/Work/fizzy`)
plus the 37signals style baseline forced decisions on each. Jumpstart Pro's
account schema was also considered (and largely rejected).

## Decision

**Where `account_id` lives: the `records` spine only** (plus `missives`, and
`subscribers` when the 1.6 person split lands). Fizzy denormalizes `account_id`
onto every table; Inkwell does not, because recordable rows are *versions* —
the spine row is the stable identity, and `Record` itself documents that host
apps scope by adding a column there. Recordable-table queries reach tenancy by
join; at this data size that is free.

**Read scoping is explicit (Option A), Fizzy's rule:** models never read
`Current.account` to scope reads; every content query *starts from the
account object* — `Current.account.records.active.posts.find(…)`,
`Current.account.posts.published` (plain one-liner accessors on `Account`,
written only for the types controllers actually list). Cross-tenant lookups
become 404s because the predicate is inside the `find`. The rejected
alternative — teaching the `.current` scope to read `Current.account` — hides
a global inside a concern and turns "forgot to set tenant context" into a
silent unscoped query.

**Write scoping is ambient:** `Record belongs_to :account,
default: -> { Current.account }`, matching the existing `creator` idiom.
Ambient state may fill in *who's writing*, never *what you can read*.

**Job context:** Fizzy's `AccountTenanted` concern (GlobalID serialization +
`around_perform` restore) rather than hand-passing account_id per job.

**Accounts table, slimmed** (DHH scrub: no columns before their feature):

- kept: `name`, `slug` (opaque Crockford via `Sluggable`, unique index),
  `owner` (NOT NULL FK to users — Jumpstart-inspired; transfers are a console
  operation, deliberately no UI), `domain` (the custom domain, unique index),
  `contact_email` (from the settings singleton)
- cut from the original plan: `status`/`trashed_at`/`purge_after` (lifecycle
  arrives later as who/when records, Fizzy `Cancellation`-style, not flags)
- cut from Jumpstart: `personal` boolean (auto-account-per-user is the "too
  friendly" signup pattern we rejected), `extra_billing_info` (billing has its
  own phase), `subdomain` (deferred to Phase 2's Worker host map), jsonb
  `roles` on the join (stringly-typed, Postgres-only, dual source of truth
  with `users.role`)

**`account_users` (1.7) is membership-only** — no role column until per-account
roles are a real feature; global `users.role` stays authoritative.

**Enforcement:** the dev/test query guard is retrofit scaffolding, deleted
after it runs clean through the soak; the permanent artifact is the
two-account isolation spec.

## Consequences
- The 1.4 audit is a first-token rewrite of ~40 call sites, concentrated in
  the existing `*_scoped.rb` concerns.
- A nil `Current.account` in a scoped path fails loudly (guard/404), never
  silently widens.
- Account creation stays unfriendly (console/setup only) until the deferred
  ownership/identity conversation (plan #5) is had.
