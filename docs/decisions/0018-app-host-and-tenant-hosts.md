---
type: decision
title: App host + tenant hosts — admin moves to kindredquill.com/{SLUG}/admin
status: accepted
tags: [rails, multi-tenancy, routing, hosts, kamal, fizzy]
created: 2026-07-28
updated: 2026-07-28
sources: [./0017-phase-1-tenancy-model.md, ~/Work/fizzy]
---

# 0018. App host + tenant hosts — admin moves to kindredquill.com/{SLUG}/admin

## Context
The admin lived on the tenant's own domain (merovex.press/admin). For
multi-tenancy the admin must leave tenant domains: one app host serves every
account's backend, path-prefixed by account slug (Basecamp-style), and a
tenant domain serves only its public site. kindredquill.com (Cloudflare,
SSL Full) is the app host.

Note: this landed ahead of most of Phase 1 (only 1.1 existed; 1.2/1.4/1.5
remain open). Prerequisites 1.3 (`Current.account`) and 1.7 (`account_users`,
membership-only) were pulled in with it. Public queries are still globally
scoped — correct today only because one account exists; the "no tenant #2
before the scoping audit" invariant carries that risk.

## Decision

**Host roles, enforced only when `APP_HOST` is set** (`config.x.app_host`):

- app host — `kindredquill.com/{SLUG}/admin/…`. `AccountHost::Extractor`
  (Rack middleware, adapted from Fizzy's `AccountSlug::Extractor`) moves a
  slug-shaped first path segment into `SCRIPT_NAME` when — and only when — an
  account with that (Crockford-normalized) slug exists. Routes never
  namespace the prefix; URL helpers echo it automatically. Unprefixed paths
  on the app host: sign-in/setup/personal settings (you authenticate before
  you have an account context), /assets, /up. Bare app host root redirects
  to sign-in; sign-in lands on `/{SLUG}/admin` via `default_admin_url`.
- tenant host — resolved by `accounts.domain` (www. folds into the apex) to
  `Current.account`; serves only the public site. `/admin` and `/session` on
  a tenant domain are routing 404s (constraint), not controller rejections.
- unknown host — 404. Development falls back to the first account on
  localhost/127.0.0.1 so `APP_HOST=localhost bin/rails s` gives admin on
  localhost and the public site on 127.0.0.1.

**Identification ≠ authorization:** admin additionally requires an
`account_users` row (or ownership) — `Account#member?` — else the same 404 a
wrong slug gets. `Sluggable` refuses reserved slugs (`ASSETS`) so a generated
slug can never shadow an unprefixed app-host path.

**Split by audience:** magic-link email URLs follow enforcement to the app
host (SessionMailer); subscriber-facing mail and the SNS webhook stay on the
tenant domain untouched.

**Two-deploy cut-over, config-keyed:** deploy A adds kindredquill.com to
kamal proxy hosts with `APP_HOST` unset — behavior identical, cert issues.
Deploy B sets `APP_HOST: kindredquill.com`. Rollback = unset the env var.
Enforcement-off is bit-for-bit legacy routing, so a mis-set DNS can never
lock the admin out.

## Consequences
- Admin URLs change once (`kindredquill.com/{SLUG}/admin/…`); sessions reset
  (cookies are host-scoped); bookmarks/password managers need updating.
- The Phase 1 scoping audit (1.4) is still owed; until then tenant-host
  resolution sets context that public queries don't yet consult.
- Workers KV host map (Phase 2) will be seeded from `accounts.domain`, which
  this change makes load-bearing.
