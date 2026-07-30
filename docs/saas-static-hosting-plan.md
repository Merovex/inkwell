# Inkwell → Multi-Tenant SaaS — Static Publishing on R2 + BYODomain + SES

> **Numbering superseded (2026-07-29):** this draft's phases predate the
> delivery numbering used since — see
> [phase-2-static-serving.md](phase-2-static-serving.md) for the canonical
> plan (Phase 1 = multi-tenancy, shipped; Phase 2 = static serving;
> Phase 2.5 = email). This doc remains useful for its Worker/R2/SES detail.

*Design plan, 2026-07-27. Turns Inkwell from the single-tenant Merovex Press
install into a multi-client publishing SaaS: writers use the Rails app as their
admin (posts, newsletters, email ops); readers get a static site served from
Cloudflare R2 at the edge under the client's own domain; newsletters go out via
SES under per-tenant identities.*

Related: [multi-tenancy.md](multi-tenancy.md) (tenancy pattern — already
decided), [account-creation-concern.md](account-creation-concern.md) (signup
flow), [database-and-scaling.md](database-and-scaling.md),
[ses-migration-runbook.md](ses-migration-runbook.md), ADRs 0006/0007 (Record
spine), 0011/0012 (subscribers/broadcasts), 0015 (SES).

---

## Target architecture

```
Reader ── https://www.authorsite.com        (BYOD cert: Cloudflare for SaaS)
   │
Cloudflare edge ── Worker "press-router"
   ├─ Host → account lookup (Workers KV, written by Rails)
   ├─ GET page/asset      → R2 site bucket   tenants/{account}/site/…, shared assets/…
   ├─ media               → R2 media bucket  (Active Storage, public URLs)
   └─ dynamic allowlist   → proxy to Rails origin, tenant host forwarded:
        POST /newsletter, /newsletter/{confirm,unsubscribe,keep}/:token,
        /contact*, /buy/:id, /ahoy/*, any request with a preview key

Rails app (Kamal, current box) — the backend + writers' admin
   ├─ app.<platform>.com/:account_slug/admin/…  (writing, broadcasts, drips, subscribers)
   ├─ publishes static snapshots to R2 on publish events (Solid Queue job)
   ├─ SES v2 sends (per-tenant identities) + SNS /webhooks/ses (unchanged shape)
   └─ SQLite trifecta stays — viable far longer because public reads never hit Rails
```

The strategic payoff: the Rails box serves only signed-in writers, form posts,
and webhooks. All reader traffic terminates at Cloudflare. That's what makes
single-box SQLite ([database-and-scaling.md](database-and-scaling.md)) hold up
across many tenants.

What deliberately does **not** change: the Record/Recordable spine (built
tenant-agnostic for exactly this, per ADR 0006), the double-opt-in subscriber
machinery, drips/broadcasts, the SES webhook's message-tag routing, Kamal
deployment.

---

## Phase 1 — Static publish pipeline to R2 (prove it single-tenant)

Ship this against merovex.press alone, before any tenancy work. Everything here
survives unchanged into multi-tenant (paths just gain a tenant prefix).

### 1a. Renderer + uploader

- Add `aws-sdk-s3` (R2 is S3-compatible; endpoint `https://<account>.r2.cloudflarestorage.com`).
- `StaticSite::Snapshot` service: enumerates the public URL manifest and renders
  each via `ActionDispatch::Integration::Session` (real middleware stack, real
  layouts, correct host). Manifest, all derivable from existing routes
  (`../config/routes.rb`):
  - `/`, `/blog`, `/blog/:slug` per published post, `/books`, `/books/:slug`,
    `/authors/:slug`, `/about`, `/privacy`, `/terms`
  - `/blog/feed` (RSS), `/sitemap`, `/robots.txt`, a rendered `404.html`
- Upload to R2 as `site/<path>/index.html` (feed/sitemap/robots keep their own
  content types). Set `Cache-Control` metadata (`public, s-maxage=300`) — short
  enough that a missed purge self-heals.
- **Assets:** sync `public/assets` (Propshaft-fingerprinted, immutable) to R2
  `assets/` as a deploy step (Kamal post-deploy hook). Pages already reference
  `/assets/…`.
- **Media:** move Active Storage from Disk to an R2 `media` bucket, `public: true`,
  so rendered HTML carries permanent public URLs instead of Rails redirect URLs.
  One-time blob mirror task; watch the WebP-variant regeneration cost (see
  [[public-image-handling]]). Worker keeps proxying `/rails/active_storage/*`
  to origin as a fallback for old cached HTML.

### 1b. Triggers (the "automatically" part)

Enqueue `StaticSite::PublishJob` (debounced — a `perform_later` guarded by a
Solid Cache lock key, ~30s window) from:

- `Publishable#publish` / `#unpublish` / `#schedule` completion — including
  `Record::PublishLaterJob`, so scheduled posts go live at the edge on time
- trash/restore of a published record; depiction (cover), distributor,
  installment, author changes
- `Setting` update (already busts its cache in `after_commit` — same hook)

Full-site rebuild per trigger is correct at this scale (dozens of pages, a few
seconds); incremental page-level publishing is a later optimization. After
upload, purge changed URLs via the Cloudflare API.

### 1c. Worker v1 (single zone)

Worker on the merovex.press zone with an R2 binding: GETs served from R2;
the dynamic allowlist above proxied to the Rails origin; everything else
(admin, session) proxied too while single-tenant. Serve `404.html` from R2 on
miss — never fall through to origin on miss (avoids cache-poisoned 404 storms).

### 1d. Static-compat fixes in the public site

- **Theme/font cookies** (`press_theme`, `press_hfont`): any server-side
  variance must move to client-side JS class-swapping — static HTML is
  identical for all visitors. (The toggle is already cookie-based; audit
  `layouts/public.html.erb` for ERB-side reads.)
- **Ahoy** keeps working untouched: the JS client posts to `/ahoy/*`, which the
  Worker proxies to Rails ([[public-site-uses-turbo]] behavior unchanged).
- **Preview links** (unpublished content, `preview_key`): Worker forwards any
  request carrying the preview param to origin — previews stay dynamic and
  `noindex/no-store` as today.
- ETag/`fresh_when` logic stays for the origin-rendered paths; it's simply
  unused on the static path.

**Exit criteria:** merovex.press served entirely from the edge; publish a post
→ live at the edge < 1 min; newsletter signup, contact, buy-links, analytics,
previews all still work; Rails box receives no anonymous page-read traffic.

---

## Phase 2 — Multi-tenancy core (the Fizzy pattern, already decided)

Per [multi-tenancy.md](multi-tenancy.md): shared DB, `account_id` rows,
`Current.account`, explicit scoping, **no default_scope, no tenancy gem**.

### 2a. Schema

- `accounts` — name, slug (unique), status (active/suspended), plan, timestamps.
- `account_users` — account_id, user_id, role (owner/admin). Supersedes the
  global `users.role` enum for authorization (keep a separate platform-operator
  flag for yourself, outside tenant scope).
- `account_id` column, backfilled to account 1 (Merovex Press) then NOT NULL,
  on: `records` (the spine — covers posts/books/series/authors/comments/drips/
  drops via one column), `subscribers`, `subscription_events`, `broadcasts`,
  `broadcast_deliveries`, `streams`, `drops_deliveries`, `missives`,
  `categories`, `settings`, `ahoy_visits`, `ahoy_events`. Composite indexes
  lead with `account_id` on hot paths (subscribers by status, records by type).
- `settings` drops the singleton: `Account has_one :setting`; `Setting.current`
  becomes `Current.account.setting`, cached per account.

### 2b. Request scoping

- **Admin:** Fizzy-style path prefix — `/:account_slug/admin/…`. An
  `AccountSlug` extractor middleware sets `Current.account`; membership checked
  via `account_users`. Every admin query goes through `Current.account`
  associations. (Path prefix over subdomain: link-shareable, one users table,
  matches the researched pattern.)
- **Public dynamic endpoints** (subscriptions, contacts, buy clicks, ahoy):
  resolve the account from the request **Host** (Worker forwards the original
  hostname) via the `domains` table from Phase 3.
- **Webhooks** (`/webhooks/ses`): unscoped route; account resolved from SES
  message tags (see Phase 4).
- **Recurring jobs** (`DripTickJob`, `SubscriberSunsetJob`, `MissiveDigestJob`,
  purges): iterate accounts, setting `Current.account` per iteration. One-shot
  jobs derive the account from their record.
- **Mailer URLs:** `default_url_options` per send, from the account's primary
  domain — confirmation/unsubscribe/keep links must live on the tenant's own
  hostname.

### 2c. Onboarding

`Signup` flow per [account-creation-concern.md](account-creation-concern.md):
creates Account + owner membership + default Setting + platform subdomain
(Phase 3) + enqueues first static publish. Flip the `multi_tenant`-style config
so signups open; the existing invite/magic-link auth is already multi-account
safe (sessions belong to users, not accounts).

### 2d. Isolation verification

A dedicated test pass: every admin controller test gains a second-account
fixture and asserts cross-account access 404s. This is the discipline that
replaces default_scope — enforce it in tests, not magic.

---

## Phase 3 — Domains + BYODomain (Cloudflare for SaaS)

### 3a. Model

`domains` — account_id, hostname (unique), kind (`platform` | `custom`),
status (`pending` → `active` | `failed`), `cf_custom_hostname_id`, primary
flag, timestamps.

### 3b. Platform subdomains (day-one URL for every tenant)

Pick the platform domain (e.g. `inkwell.press`). Wildcard DNS
`*.<platform>` → the Worker; wildcard cert is native to your own zone — no
Cloudflare-for-SaaS involvement. Every new account gets
`{slug}.<platform>` immediately, so sites work before (or without) BYOD.

### 3c. Custom hostnames (BYOD)

1. Writer adds `www.authorname.com` in admin → Rails calls the Cloudflare
   **Custom Hostnames** API (fallback origin = your zone/Worker).
2. UI shows the DNS instruction: `CNAME www → <platform-cname-target>`
   (plus optional TXT pre-validation so the cert can issue before cutover).
3. Poll (or CF webhook) until validation + cert issuance complete → `active`.
4. Rails writes `hostname → account_slug` into **Workers KV**; Worker resolves
   `Host` → KV → R2 prefix `tenants/{slug}/site/…`.
5. Republish the tenant's static site — canonical URLs, RSS, sitemap, and
   mailer links all switch to the new primary domain; Worker 301s the platform
   subdomain and any non-primary hostnames to the primary.

**Caveats to document in the UI:** apex domains need CNAME-flattening/ALIAS
support at the registrar — recommend `www` as primary with an apex redirect;
Cloudflare for SaaS pricing is 100 custom hostnames free, then ~$0.10/mo each.

---

## Phase 4 — Multi-tenant SES newsletters

Keeps the ADR 0015 architecture (two config sets, message tags, SNS →
`/webhooks/ses`) and extends it per-tenant. This phase carries the **largest
business risk** of the whole plan: every tenant shares your SES account's
reputation and quota.

### 4a. Sending identities — two tiers

- **Tier 1 (default, instant):** one platform mail domain, e.g.
  `mail.<platform>.com`, verified once in SES. A verified domain identity
  covers its subaddresses, so every tenant can send as
  `{slug}@mail.<platform>.com` immediately — From display name is the
  publication name, Reply-To is the writer. Platform DKIM/SPF/DMARC set up
  once (mirror of the [ses-migration-runbook.md](ses-migration-runbook.md)
  checklist).
- **Tier 2 (BYOD sending, paid-plan feature):** per-tenant SES identity via
  SESv2 `CreateEmailIdentity` for a tenant subdomain (recommend
  `news.authorname.com` — keeps their apex reputation insulated, mirrors the
  merovex two-identity insight). Admin UI shows the records to add: 3 DKIM
  CNAMEs, custom MAIL FROM MX+TXT, DMARC guidance; Rails polls
  `GetEmailIdentity` until verified. New table `sending_identities`
  (account_id, domain, status, dkim_tokens, verified_at). Bonus: for domains
  already on Cloudflare via Phase 3, offer to create the DNS records through
  the CF API — one-click verification.

Transactional platform mail (magic links, confirmations) stays on the existing
platform transactional identity for everyone — tenant identities are for
marketing sends only (broadcasts + drips), exactly the current
transactional/marketing split.

### 4b. Event routing

Add an `account_id` message tag alongside the existing
`broadcast_id`/`drop_record_id`/`subscriber_id` tags in `PostBroadcastMailer`
and `DropMailer`. `Webhooks::SesController` already routes by tags — it gains
one lookup, no structural change. Single SNS topic and webhook endpoint stay.

### 4c. Deliverability governance (do not skip)

- Per-account rollups of the delivery metrics you already store: bounce rate,
  complaint rate, volume, over a trailing window.
- **Auto-pause** an account's marketing sends at complaint > 0.1% or bounce
  > 5% (SES's own alarm thresholds), flag for platform-operator review.
- Double opt-in is already mandatory in the codebase — keep it
  platform-mandatory; it's the single best abuse control you have. **No list
  import at launch** (or import → forced re-confirmation): imported lists are
  how one tenant torches shared reputation.
- Throttle `PostBroadcastJob` (pace `find_each` batches) against the SES
  account send-rate quota; per-plan daily send caps; monitor aggregate quota
  as tenants grow.
- Existing sunset machinery (ADR 0014) runs per account — it's now also a
  platform hygiene feature.

---

## Phase 5 — SaaS operations

- **Billing:** Stripe (the `pay` gem fits Rails 8) — plans gate subscriber
  count, monthly email volume, custom domains, BYOD sending identity.
- **Platform-operator console** (outside tenant scope, your eyes only):
  accounts list, suspend/reactivate, deliverability dashboard, quota view.
- **Backups:** R2 static content is derived (rebuildable from DB) — only the
  SQLite databases and the media bucket are precious. Litestream (or periodic
  snapshot) to a private R2 bucket.
- **Suspension semantics:** suspended account → Worker serves a parked page
  (KV flag), sends paused, admin read-only.
- **Scaling path** unchanged from [database-and-scaling.md](database-and-scaling.md):
  the edge absorbs reader traffic, so the trigger to move SQLite → MariaDB is
  writer/job write contention, not audience growth.

---

## Sequencing & rough effort

| Phase | Contents | Relative size |
|-------|----------|---------------|
| 1 | R2 snapshot pipeline, Worker, Active Storage → R2, static-compat fixes | M — mostly new, low-risk code beside the app |
| 2 | accounts, account_id backfill, Current.account, admin path prefix, isolation tests | L — touches everything; the migration discipline is the work |
| 3 | domains table, platform subdomains, CF for SaaS + KV | S/M — mostly API integration |
| 4 | tenant SES identities, tags, governance | M — the governance half matters more than the plumbing |
| 5 | billing, operator console, backups | M — standard SaaS chrome |

1 → 2 → 3 → 4 → 5 strictly: each phase is shippable and valuable alone
(Phase 1 alone gives merovex.press free global CDN hosting and slashes origin
load; Phase 2 alone enables a second hand-provisioned client).

## Costs (order of magnitude)

R2: storage pennies, **zero egress**. Workers: $5/mo paid plan (includes KV).
Cloudflare for SaaS: 100 custom hostnames free, ~$0.10/mo after. SES:
$0.10/1k emails. Existing Hetzner box unchanged. The architecture's marginal
cost per tenant is close to zero until email volume dominates.

## Risks & open questions

- **Rails edge:** Gemfile tracks rails `main` — pin to a released 8.2.x before
  taking paying customers.
- **Shared SES reputation** is the existential SaaS risk — Phase 4c ships
  *with* Phase 4a, not after.
- **Static staleness:** scheduled publishes must trigger republish via
  `Record::PublishLaterJob` (wired in Phase 1b) or edge content lags the DB.
- **Cookie-varied rendering:** audit before Phase 1 cutover; anything the
  server varies per visitor breaks silently as static HTML.
- **Apex-domain support** varies by registrar; make `www`-primary the guided
  default.
- Open: platform domain name; whether comments/boosts ever surface on the
  public site (would need a dynamic island or fetch-from-origin widget);
  whether Ahoy events should also be captured Worker-side to reduce origin
  chatter.
