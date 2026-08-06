# Email: Per-Site Tenants + BYOD Sending Domains — Implementation Plan

Status: **approved by Ben 2026-08-06 (late night), build starts on his morning
go.** Written to survive a context clear; everything needed to execute is here.
Companion docs: [[email-architecture]], [[ses-tenants]].

## Approved decisions (do not re-litigate)

- **Tenant name is derived, not stored**: `Account#ses_tenant_name` =
  `"site-#{slug}"`. Slug is immutable ⇒ tenant name is immutable. The only
  persisted state is `accounts.ses_tenant_provisioned_at` (new datetime column).
- **Tenant is created when the author BUYS broadcast email** — not lazily on
  first send. No billing exists yet, so `EmailConnection.provision_tenant(account)`
  is callable from console (Tenant Zero is comped) and later by the purchase flow.
- **BYOD ships first-class from the start** (Buttondown model; their custom
  domain is gratis ⇒ broadcast capability is the paid thing, BYOD included).
  Merovex Press needs `news.merovex.press` soonest — it's BYOD customer #1
  through the same UI every author will use.
- **Shared lane moves to `kindredquill.email`** (domain BOUGHT 2026-08-06,
  DNS should go on the same Cloudflare account). Rationale: Gmail/Yahoo score
  reputation at the registrable-domain level; customer-generated bulk must not
  share a registrable domain with auth mail (verify.kindredquill.com). Industry
  standard (mcsv.net, sendgrid.net, buttondown.email).
  - Shared identity: `mail.kindredquill.email`.
  - `kindredquill.com` subdomains become first-party only: verify (auth),
    notify (platform bulk), news (KQ's own marketing to authors).
- **Subdomain only for BYOD** (e.g. `news.merovex.press`) — apex refused.
  Isolates email reputation from the author's root domain.
- Sends stamp `tenant_name` in delivery options once the account's tenant is
  provisioned; BYOD identities are associated with the site's tenant, so
  reputation isolation holds in both lanes.

## Build plan

### 0. Platform groundwork
- Extend `lib/tasks/email.rake` `email:provision` to also provision the
  `mail.kindredquill.email` identity (DKIM, MAIL FROM, config set
  `inkwell-marketing`), printing DNS records for Ben + a recommended DMARC.
- `ApplicationMailer.marketing_from`: remove hardcoded "Ben Wilson" display
  name; shared-lane From = `"<Site name>" <noreply@mail.kindredquill.email>`.
- (#1, folded in as trivial unless Ben objects) stamp the existing platform
  tenants on sends: auth mailers → `platform-auth`, pulse/circle mailers →
  `platform-circles`, via `delivery_method_options: { tenant_name: }`.

### 1. Data model
- Migration: `accounts.ses_tenant_provisioned_at` (datetime, null).
- Migration: `create_table :sending_domains` mirroring `custom_domains`:
  `account_id` FK, `domain` (unique index), `status`
  (pending/verifying/live/error/disconnected), `dkim_tokens` (json, 3 CNAMEs),
  `mail_from_domain`, `last_checked_at`, timestamps.

### 2. Services (each mirrors its custom-web-domain twin — copy the shape)
- `EmailConnection` (≙ `app/services/domain_connection.rb`):
  - `provision_tenant(account)`: SES `create_tenant("site-#{slug}")` +
    `create_tenant_resource_association` with the shared identity; idempotent
    (rescue AlreadyExists); stamps `ses_tenant_provisioned_at`.
  - `connect(account:, input:)`: validate via `Hostname` PLUS a
    subdomain-required check (≥3 labels / not a registrable apex);
    `CreateEmailIdentity` (config set inkwell-marketing) → response carries
    the 3 DKIM tokens; `PutEmailIdentityMailFromAttributes` (convention
    pending Ben: default `bounce.<domain>`); associate identity to the
    account's tenant; persist row status "verifying"; enqueue poll.
  - `disconnect`: `DeleteEmailIdentity`, mark row disconnected.
  - Injectable SES client for tests (see CustomDomainStatusJob.client_override
    pattern; SES tests use aws-sdk `stub_responses` — see
    test/models/publisher_test.rb).
- `SendingDomainStatusJob` (≙ `CustomDomainStatusJob`): polls
  `GetEmailIdentity` until DKIM status SUCCESS + MAIL FROM MX SUCCESS →
  status live, notify Ben/author (new mailer method, crib `DomainMailer.live`).

### 3. From resolution + stamping
- `Account#broadcast_from`: live sending_domain →
  `"#{site.site_name}" <noreply@#{domain}>`; else shared lane.
- Broadcast/Drip mailers use it; add
  `delivery_method_options: { tenant_name: account.ses_tenant_name }` when
  `ses_tenant_provisioned_at` present.

### 4. UI — settings tab
- Sixth segment in System settings tab bar (same link-segment pattern as
  Domain — see `segmented_tabs` `href:` support in
  app/helpers/tabs_helper.rb and app/views/admin/custom_domains/index.html.erb
  for the whole pattern incl. `?tab=` deep-links back).
- New `admin/sending_domains` page wearing the identical chrome: status card
  (shared lane vs custom, per-record badges), connect form, disconnect in the
  card footer, and **`shared/copy_field` rows for every DNS record**:
  3× DKIM CNAME, MAIL FROM MX + SPF TXT, suggested DMARC TXT.
- Routes: `resources :sending_domains, only: %i[index create destroy]` in the
  admin namespace next to custom_domains.

### 5. Tests
Mirror test/services/domain_connection_test.rb +
test/controllers/admin_custom_domains_test.rb with stubbed SES.

## Morning questions — ANSWERED (locked 2026-08-06 morning)
1. MAIL FROM: `bounce.<domain>` for BYOD (e.g. `bounce.news.merovex.press`),
   matching the platform convention. Shared lane: `bounce.kindredquill.email`.
2. **Handles ship now, not later.** Shared-lane From is
   `<handle>@kindredquill.email` — the **apex**, not `mail.` ("I said
   <handle>@kindredquill.email for a reason" — supersedes the
   `mail.kindredquill.email` shared-identity bullet above). The handle is
   **user-chosen with limits** (`accounts.handle`: unique, format-limited,
   reserved-word list) — explicitly NOT the slug. Until an account claims one,
   fall back to `noreply@kindredquill.email`.
3. Tab label: **Email**.
4. Platform-tenant stamping folded in: **yes** — "each account [is] a tenant…
   so their reputation falls into their own tenant"; platform lanes get the
   same treatment (auth → platform-auth, circles → platform-circles).

## Build discovery (2026-08-06)
- `aws-actionmailer-ses` 1.2.0's SESV2 Mailer whitelists only
  `configuration_set_name` / `email_tags` / `list_management_options` for
  SendEmail; an unknown key like `tenant_name` falls through to
  `Aws::SESV2::Client.new` and raises. Fix: subclass the gem Mailer to extract
  `tenant_name` into `@send_email_params`, re-register as `:ses_v2` in an
  initializer. `send_email` itself accepts `tenant_name` in aws-sdk-sesv2
  1.105.

## Ops (Ben's side)
- Add the `kindredquill.email` DNS records `email:provision` prints
  (Cloudflare zone for kindredquill.email — apex identity per the locked
  handle decision, not `mail.`).
- **Deploy gate for platform stamping**: sends that name a tenant fail unless
  the From identity is associated with it. Before deploying, either point
  `ses.transactional_from` / `ses.notify_from` at the kindredquill.com
  identities the rake associates (verify./notify.), or console-associate the
  legacy auth./news.merovex.press identities to platform-auth/-circles as a
  bridge.
- After the feature ships: connect `news.merovex.press` in the Email tab, add
  records in the merovex.press CF zone, console-run
  `EmailConnection.provision_tenant(Account.find(1))`.
- Still pending from earlier: tenant reputation policies in console
  (platform-auth→Strict, platform-circles→Standard), pull the old
  auth./news.merovex.press identities from SES (or the new connect adopts
  news.merovex.press — check for duplicate-identity conflict), cancel
  Postmark, delete the inkwell-provisioner IAM key.
- #3 (EventBridge feedback loop → DeliveryEvent, paused-tenant UI) deliberately
  deferred — "we will discuss #3 later".

## Adjacent state (so the next session has the map)
- **Web**: www.merovex.press serves the static build (98/100/100/100 mobile
  PSI). Apex DNS flip is done/awaiting propagation per Ben ("already pointing
  to sites.*"). Fonts vendored in-theme (bin/vendor-fonts, 22 pairings);
  designer preview intentionally still uses Google.
- **House rules**: never inline CSS (memory: never-inline-css); never commit
  (Ben commits); confirm design couplings before building.
- **Queued ideas, not approved work**: fingerprinted asset URLs (Ben floated —
  enables immutable edge caching), srcset responsive images, AVIF dual-format
  via the theme's img partial, shared `/assets` alias (theme chrome served
  once platform-wide — discussed, awaiting go), Worker If-None-Match/304
  handling, CF Insights beacon toggle (Ben's dashboard, his call).
