---
type: decision
title: Record/Recordable — generic, tenant-agnostic content spine
status: accepted
tags: [data-model, delegated-types, tenancy, state-modeling]
created: 2026-07-03
updated: 2026-07-03
sources: [../data-model.md, fizzy card.rb / card/closeable.rb / card/statuses.rb (basecamp/fizzy@main)]
---

# 0006. Record/Recordable — generic, tenant-agnostic content spine

## Context
The delegated-type content model ([data-model.md](../data-model.md)) is wanted
as **reusable bones**: Alcovo uses it, but future apps should mount the same
spine — including apps with *no* tenant at all. The notional design baked
`account_id` and a `status` enum (`active/archived/trashed`) into the envelope.
Separately, reading Fizzy's actual source showed 37signals split state modeling
by kind: a string **enum column** for a universal, mutually-exclusive lifecycle
(`Card::Statuses` — `drafted/published`), and **separate record objects** for
optional who/when states (`Closure`, `Goldness`).

## Decision
1. **Naming: `Record` / `Recordable`** (37signals' public vocabulary; Rails
   calls the mechanism delegated types). The envelope model is `Record`.
2. **The spine is tenant-agnostic.** `records` carries only: the
   `recordable_type/id` pointer, `creator_id`, self-referential `parent_id`
   (threading/comments), `position`, `trashed_at`, timestamps. **No
   `account_id`** — a host app that needs scoping adds its own column on top
   (Alcovo will add `account_id` when Accounts/tools land).
3. **State modeling ladder** (from Fizzy): nullable **datetime column** for
   on/off + when (`trashed_at`, `pinned_at`, `published_at`); **string enum**
   for exactly-one-of-N lifecycle (`drafted/published`); **separate record
   object** (Closure-style) only when *who* matters — none needed yet.
   Consequences: no status enum on the envelope; editorial state lives on the
   recordable; trash is `records.trashed_at` (purge job deferred); `archived`
   dropped (unpublish already covers "off the site, could come back").
4. **First recordable: `Post`** — a throwaway blog post (not an Alcovo product
   type) to build the spine against: `title`, `status` (`drafted/published`),
   `published_at` (stamped on *first* publish only, preserved through
   unpublish/republish so feed order and permalink dates stay honest),
   `pinned_at`.
5. **Rich text: Action Text + Active Storage, edited with Lexxy** (adapter
   mode on edge Rails; `form.rich_textarea` renders `<lexxy-editor>`).

## Consequences
- Any future app mounts the spine without an Account; extraction to an engine
  later is mechanical (spine has zero references to app-specific models).
- Alcovo's tenancy becomes an additive migration, not a rework.
- `data-model.md` / `schema.rb` still describe the earlier notional envelope
  (`Recording`, `status`, `account_id`, Vault) — treat this ADR as current
  direction; reconcile those docs when Alcovo's real tools land.
- Trash needs a purge job before it's a complete feature.

## Alternatives considered
- **BC3-style `status` enum on the envelope** — rejected: conflates lifecycle
  axes (restore-from-trash would need "previous state" bookkeeping) and carries
  states (`archived`) with no current need.
- **State-as-record (`Publication`, `Trashing`) from day one** — rejected for a
  one-user/small-team blog: who/when is already knowable (`creator`,
  timestamps); pure ceremony until accountability matters.
- **`account_id` in the spine now** — rejected: tenancy is a host-app concern;
  baking it in breaks the "bones without an account" requirement.

## Links
Related: [[data-model]] · [[0002-domain-vocabulary-person-user-account]] ·
Supersedes: — · Superseded by: —
