# Overview — Inkwell / Merovex Press

> Living synthesis of the current state of the project. Update this whenever the
> shape of the work changes. Keep it short — details live in linked pages.

## What this is

A Rails 8.2 app (Ruby 4.0.5), now **multi-tenant** ([0017](decisions/0017-phase-1-tenancy-model.md)–[0019](decisions/0019-app-subdomain-and-account-picker.md)), wearing three faces:

- **Inkwell** — each site's admin, script-name-mounted on the **app host** at
  `/{SLUG}/admin` (gated per [0016](decisions/0016-admin-backend-domain-admin-only.md));
  sign-in, the account picker, **Circles**, **Goals**, and **Notifications**
  live at the app host's top level.
- **Public sites** — each Account's site on its own domain (Hugo static
  pipeline, [0021](decisions/0021-hugo-static-site-generator.md)); "Merovex
  Press" is the first tenant's brand. See [[merovex-press-public-site]].
- **The community layer** — cross-account Circles
  ([0023](decisions/0023-circles-cross-account-buckets.md)): invite-only
  author groups with discussions, pulse check-ins, boosts, and @mentions.

(Formerly "Alcovo"; renamed 2026-07-08. Accepted ADRs 0001–0006 predate the
rename and keep the old name as history.)

This `docs/` folder is the single home for design/reference docs and the work
log; see [[CLAUDE]] for how it's maintained.

## Current state (2026-08-07)

Since July: multitenancy shipped (app host + tenant hosts, join-code signup,
[0017](decisions/0017-phase-1-tenancy-model.md)–[0020](decisions/0020-join-code-signup-and-root-role.md));
the Hugo static pipeline + SiteDesigner
([0021](decisions/0021-hugo-static-site-generator.md)/[0022](decisions/0022-sitedesigner-design-json-sovereignty.md));
and the August community arc:

- **Circles** ([[circles]], [0023](decisions/0023-circles-cross-account-buckets.md)) —
  invite-only author groups (golden invitation cards, membership page,
  owner-first rosters); Message discussions; **Pulse check-ins** on Eastern
  wall-clock schedules (`PulseTickJob`, answers as `Beat` cards).
- **The Wall** ([[circle-wall]], candidate view built 2026-08-06) — a
  reverse-chrono feed of a circle's Messages + Beats, thread/edit modals,
  live boost/comment broadcasts, per-viewer affixed strips (pending pulse,
  drafts, scheduled). Swappable with the sectioned circle page. Home is the
  **Commons**, the one platform-wide circle everyone auto-joins.
- **Bulletins** ([[bulletins]], built 2026-08-06) — root→everyone platform
  announcements: a nil-bucket `Publishable` record, bell-only fan-out (no
  email), authored at `/support/bulletins`, read at `/bulletins`.
- **Goals & Tallies** ([[goals]]) — personal progress on the User bucket;
  rate vs project goals, display-card sets (heatmaps lead the grid).
- **Notifications** ([[notifications]], [0024](decisions/0024-notifications-stamped-copy-digests.md)) —
  stamped-copy rows with per-kind icons, live bell (Turbo), tiered digests
  (4-hour / daily-for-replies), 30-day shelf life.
- **Boosts & @mentions** across circle content — mentions by typed token or
  Lexxy's `@`-prompt (User as Action Text attachable, avatar+name chip);
  comment replies ring the thread everywhere comments exist.
- **Newsletter signup on static sites** ([[dynamic-islands]],
  [[newsletter-bot-protection-plan]] — built & live 2026-08-07, verified on
  two tenants) — the Hugo band posts to the `POST /newsletter` island through
  the edge Worker (X-Island-Auth/Host/IP header contract, origin lockdown);
  bots stop at a pinned honeypot + per-account Cloudflare Turnstile
  (fail-closed, secret encrypted at rest — first AR-encryption use).
  Enablement is automatic on sending-domain connect, or
  `bin/rails "newsletter:enable[x]"`.
- **Email** ([[email-architecture]], CANONICAL; tenancy + BYOD shipped
  2026-08-06 per [[email-tenant-byod-plan]]) — all-SES; the root never sends.
  Per-site SES tenants (`site-<slug>`, provisioned automatically on
  sending-domain connect, console/task for comped accounts) isolate every
  site's reputation; platform mail stamps
  platform-auth/-circles. Site broadcast From = live BYOD sending domain
  (Email tab, subdomain-only) else `<handle>@kindredquill.email` (author
  handle, `noreply@` fallback). Deploy gated on `email:provision` +
  kindredquill.email DNS + From-identity/tenant associations (ops list in the
  plan doc). Postmark = dormant warm-standby, cancellation pending.
  Owner-facing metrics are in-app now: broadcasts overview chart + per-send
  detail (links, recipient milestones) + roster reactivation — the ESP
  console is no longer part of the Site owner's loop.
- **CSS/HTML standards** — `css-html-standards` skill always-in-force
  (tokens-first, curated `u-*` utilities, earned BEM, 48em/64em stops,
  a11y gates); every stylesheet passes the mechanical check, markup swept
  app-wide (skip links, keyboard-operable editables, dead ARIA stripped).
- **Ops** — Solid Queue in Puma, Mission Control at `/jobs` (root-only),
  Eastern `config.time_zone`, recurring schedule zones explicit. The August
  arc deployed 2026-08-07 (several rounds, through the newsletter-islands
  work); the working tree still holds the final island fixes pending Ben's
  commit + one `wrangler deploy` (client-IP restore). The alcovo container's
  volume collision (it mounted `/var/lib/inkwell`) is diagnosed, its
  deploy.yml fixed, redeploy pending.

## State as of 2026-07-12 (single-tenant era)

- **Auth & shell** — passwordless magic-link auth, first-run Setup, top-bar app
  shell. A Basecamp-style **app menu** (jump-to sheet) is the admin's global
  nav — see [[app-menu]].
- **Content spine** ([0006](decisions/0006-record-recordable-generic-spine.md),
  [0007](decisions/0007-versioned-recordables.md)) — a tenant-agnostic `Record`
  envelope + `Recordable` versioning; recordables are immutable event-tagged
  versions behind a record-keyed identity, with drafts-mutate / published-versions
  semantics, a change log, tracked-changes diffs, and scheduled publishing.
- **Recordables shipped** — `Post` (blog), `Message` (forum), `ChatLine`,
  `Comment`, and now **`Book` & `Series`**
  ([0008](decisions/0008-books-series-recordables.md)): versioned catalog entries
  with a versioned cover (`Depiction`, mirroring `Body`) and a many-to-many
  series↔book join (`Installment`, keyed by Record). Managed live on the show
  page (typeahead + drag-sort).
- **Distributors** ([0009](decisions/0009-distributors-and-changelog-events.md))
  — store buy-links on the `Record` (unversioned, click counter); cover and link
  changes surface in the change log via event tags.
- **Public site** — home, blog (index + articles), and the **books catalog**
  (3-card grid grouped by series) + book detail with a "More in <series>"
  cross-sell section, on id-first slugs
  ([0010](decisions/0010-id-first-public-slugs.md)); branded error pages.
  Typography: self-hosted Source pair + **Federo** (wordmark) + **Archivo
  Narrow** (headings/nav); its own light/dark/auto toggle (`press_theme`
  cookie, default dark — independent of the admin theme). Repeated looks live
  in `press-utilities.css` (compose utilities, not per-page BEM).
- **Theme** — rethemed to the **Merovex palette** (syō-ro teal accent +
  mountain-mist neutrals), shared by both sites; see [[theme-background-colors]].
- **Analytics & ops** — Ahoy still records visits + `$view` events, scoped per
  account, but the only reader left is the weekly digest's per-post reads. The
  admin traffic dashboard and its visitor geography came out (Aug 2026) — the
  numbers were vanity and the edge-served sites never fed them anyway. **No IP
  is stored at all** now (geocoding was what used to discard it). Production
  error reporting via **Honeybadger**.

## Core vocabulary

As shipped (see [[domain-vocabulary]]): **`User`** (global login) ──<
`AccountUser` >── **`Account`** ("site" in UI — never "press"); `Record.bucket`
is polymorphic (**Account | Circle | User**); `Person` is the *reader*
identity (newsletter). Community terms: Circle, Pulse/Beat, Goal/Tally,
Boost, Notification.

## Open threads

- **Deploy** — commit the August arc and `kamal deploy`; fix confirmed for
  alcovo's deploy.yml (own `/var/lib/alcovo` volumes; domain TODO) and its
  redeploy + a check of Inkwell's production DB for alcovo cross-contamination.
- ~~**Goal deadlines + pace line**~~ — shipped 2026-08-05 (see [[goals]]).
- **Request-an-invite** for circles; **web push** channel; **List-Unsubscribe**
  on notification emails (blocked on a settings page).
- The goal design-studies gallery is hidden on disk — deliberate KEEP (owner).
- Older threads (public author/series pages, distributor click redirect,
  geo refresh automation, data-model reconciliation) remain from the
  single-tenant era.
