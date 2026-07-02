---
type: decision
title: Domain vocabulary — Person / User / Account
status: accepted
tags: [naming, data-model, auth, tenancy]
created: 2026-07-01
updated: 2026-07-01
sources: [../fizzy-authentication.md, ../fizzy-user-account-model.md, ../data-model.md]
---

# 0002. Domain vocabulary — Person / User / Account

## Context
The design docs use two different naming schemes for the same three
core concepts:

- **Fizzy source** (verbatim): `Identity` (global login) / `User` (per-tenant
  membership) / `Account` (tenant).
- **Notional design docs** (`data-model.md`, `schema.rb`, `account-creation-concern.md`):
  `Person` / `Membership` / `Group` (a.k.a. `bucket`).

We want **plain, simple words** for the domain, and one canonical set — not two.

## Decision
Alcovo's canonical vocabulary for the three core models is:

| Concept | Alcovo term | Fizzy term | Old notional term |
|---------|-------------|------------|-------------------|
| Global, email-based login (who you are across everything) | **`Person`** | `Identity` | `Person` |
| A person's membership in one tenant (role, name, access) | **`User`** | `User` | `Membership` |
| The tenant / community space | **`Account`** | `Account` | `Group` / `bucket` |

Net effect: **keep Fizzy's `User` and `Account`; rename `Identity` → `Person`.**
The terms **`Membership`, `Group`, and `bucket` are retired.**

Consequences for content-model columns:
- `bucket_id` / "the group" on `Recording` becomes **`account_id`**.
- `belongs_to :group` becomes `belongs_to :account`.
- "one email = one Person → many Users → many Accounts" is the identity story.

## Consequences
- **Closer to Fizzy** — less mental translation when reading Fizzy source, since
  two of the three names now match exactly.
- **`Person` reads more plainly than `Identity`** for a writer-community product.
- **The design docs reconciled to this vocabulary on 2026-07-01.** The notional docs
  (`data-model.md`, `schema.rb`, and `account-creation-concern.md` — renamed from
  `group-creation-concern.md`) and the Alcovo-facing prose/mapping tables in the
  two Fizzy docs now use `Person` / `User` / `Account`. Verbatim Fizzy source
  code and Fizzy-describing prose keep Fizzy's own names (`Identity` / `User` /
  `Account`), since those are accurate for Fizzy.
- Also renamed the placeholder product name **"Writer Group" → "Alcovo"**
  throughout the design docs, which removes the last ambiguous use of "Group".

## Alternatives considered
- **Keep Fizzy verbatim (`Identity`/`User`/`Account`)** — rejected: "Identity"
  is jargon-y for this product; "Person" is plainer.
- **Keep the notional `Person`/`Membership`/`Group`** — rejected: "Membership"
  is clunky as a class name and "Group" collides with everyday usage and with
  Rails/UI notions; "Account" is clearer for a tenant.

## Links
Related: [[domain-vocabulary]] · Supersedes: — · Superseded by: —
