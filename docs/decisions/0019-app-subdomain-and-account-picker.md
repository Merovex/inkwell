---
type: decision
title: App host moves to app.kindredquill.com; account picker at its root
status: accepted
tags: [rails, multi-tenancy, routing, hosts]
created: 2026-07-28
updated: 2026-07-28
sources: [./0018-app-host-and-tenant-hosts.md]
---

# 0019. App host moves to app.kindredquill.com; account picker at its root

Amends ADR 0018 (host-role model unchanged) in two ways:

## Decision

**`APP_HOST` becomes `app.kindredquill.com`.** The bare apex
(kindredquill.com) is not a tenant and not the app: the AccountHost middleware
301s any apex request to the app subdomain, path intact (`apex_host` derives
the registrable domain from the app host; nil when there's no subdomain to
strip). The apex stays in kamal's proxy hosts so its cert keeps serving the
redirect — and stays free for a future product/marketing site.

**The app-host root is the account picker, not a blind sign-in redirect.**
`AccountsController#index` (auth layout) inherits forced authentication:
signed-out visitors bounce to sign-in; signed-in users with exactly one
membership are redirected straight into `/{SLUG}/admin`; several memberships
get one card per account (name + domain); zero get an empty state.
`default_admin_url` follows the same rule after sign-in. `/{SLUG}` (bare)
redirects to `/{SLUG}/admin` — constrained to slug-mounted requests only, so
it can never shadow the public root in legacy mode.

## Consequences
- DNS: `app.kindredquill.com` must exist in Cloudflare (proxied, SSL Full)
  before the deploy that flips `APP_HOST`, or the admin is unreachable until
  it does (rollback: unset `APP_HOST`).
- Admin URLs change again, once: `app.kindredquill.com/{SLUG}/admin/…`.
  Sessions reset (new host); magic-link mail follows automatically.
- The picker is the first UI that assumes multi-membership — 1.7's join is
  now user-visible, not just an authorization table.
