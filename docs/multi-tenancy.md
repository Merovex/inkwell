# 37signals / Fizzy Multi-Tenancy — How It Works

*Research summary for Inkwell's tenancy design, drawn from Fizzy's source and the
37signals engineering write-ups. Bottom line: **shared single database,
row-level tenancy scoped by `account_id`** — not database-per-tenant.*

Related: [`fizzy-user-account-model.md`](./fizzy-user-account-model.md),
[`fizzy-authentication.md`](./fizzy-authentication.md),
[`database-and-scaling.md`](./database-and-scaling.md).

---

## The answer: one shared DB, row-level scoping

In the shipped version, every account/tenant lives in **one conventional shared
MySQL database**, isolated by an `account_id` column on every row — the same
pattern as Basecamp/HEY. No database-per-tenant, no connection switching, no
schema-per-tenant.

### Mechanism

1. **URL carries the tenant.** Paths are prefixed: `/{account_id}/boards/…`.
   That's why `Account#slug` returns `"/#{AccountSlug.encode(external_account_id)}"`
   — the encoded account id *is* the URL prefix.
2. **Middleware resolves it.** An `AccountSlug::Extractor` middleware pulls the
   account id from the path and sets **`Current.account`** for the request.
   *(Inferred from the slug/`AccountSlug` code + secondary sources; middleware
   source not read line-by-line.)*
3. **Everything scopes off `Current`.** Setting the session/identity resolves
   `Current.user` *within* `Current.account` (see `current.rb`), and every model
   (`boards`, `cards`, `users`, `accesses`, rich text…) `belongs_to :account`.
   Isolation is enforced by always querying **through account-scoped
   associations**, never globally.
4. **`MultiTenantable` is just a toggle.** The concern only holds a
   `multi_tenant` flag + `accepting_signups?` (`multi_tenant || Account.none?`).
   It is *not* the enforcement — the `Current.account` + `belongs_to :account`
   discipline is.

**No `default_scope`, no tenancy gem.** Scoping is explicit.

---

## The history: they almost went database-per-tenant

Per [Behind the Fizzy Infrastructure](https://dev.37signals.com/fizzy-infrastructure/),
Kevin McConnell built an ambitious design giving **every customer their own
SQLite database** on-disk, co-located with the app — meant to serve both SaaS
and self-hosted from one model, with better data locality/performance.

**Two days before launch they pivoted** back to "Plan B" — conventional shared
MySQL — because:
- Cross-tenant features (login, shared avatars) became awkward.
- The operational story (failover, replication lag) wasn't confident.
- The infra work was blocking the product release.

They kept a few spoils: Kamal proxy load-balancing tricks, transaction-aware
replication-lag handling (ported to MySQL), and multi-DB routing for **geo**
distribution (not per-tenant).

**Lesson for Inkwell:** the operational cost of per-tenant DBs (HA, failover,
cross-tenant features) tends to outweigh the locality win. Start shared-DB
row-level.

---

## Open-source vs. hosted

- **Self-hosted Fizzy (`basecamp/fizzy`)** effectively runs **single-account**:
  `multi_tenant` defaults to `false`, so `accepting_signups?` is true only when
  `Account.none?` (first-run setup). One org, one account.
- **`fizzy-saas`** is the engine that flips `multi_tenant = true` and adds the
  many-accounts-in-one-DB hosting on top of the same core. `database.yml`
  branches on the SaaS path — but both branches are a **single primary DB**, not
  per-tenant.

---

## Why this matters for rich text / Lexxy

Because Fizzy is **shared-DB, row-level, `Current.account`-scoped, with no
`default_scope`**, Action Text / Active Storage never hit the historical
multi-tenancy failure modes: rich text and blobs are always reached through an
account-scoped parent record, and there's no default scope fighting SGID
resolution. The tenancy friction with Action Text is specific to
`default_scope`-based tenancy gems and to database-per-tenant setups — neither of
which Fizzy uses. See [`lexxy-and-active-record.md`](./lexxy-and-active-record.md).

---

## Recommendation for Inkwell

Adopt the Fizzy pattern directly:
- Single shared database, `belongs_to :account` on every tenant-owned model.
- `Current.account` set from a URL-path (or subdomain) extractor middleware.
- Reach all content through account-scoped associations; **avoid `default_scope`
  tenancy gems** (they break Action Text/Active Storage + SGIDs).
- Keep per-tenant DB isolation off the table unless a concrete compliance/HA
  requirement forces it later.

## Sources
- [Behind the Fizzy Infrastructure — 37signals Dev](https://dev.37signals.com/fizzy-infrastructure/)
- [Rails Multi-Tenancy — 37signals Dev](https://dev.37signals.com/rails-multi-tenancy/)
- [basecamp/fizzy](https://github.com/basecamp/fizzy) · [basecamp/fizzy-saas](https://github.com/basecamp/fizzy-saas)
- [Inside Fizzy's Authentication Architecture (epona.me)](https://epona.me/fizzy-authentication-architecture-three-tier-multi-tenant/)
