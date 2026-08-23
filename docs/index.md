# Documentation Index

Catalog of everything in `docs/`. Keep this in sync whenever a page is added,
renamed, or superseded. See [[CLAUDE]] (`CLAUDE.md`) for conventions.

- **[overview.md](overview.md)** — living synthesis of the current project state
- **[log.md](log.md)** — chronological work log (append-only)

## Reference & design docs

Polished research/design (modeled on Basecamp's Fizzy). See [[domain-vocabulary]]
for canonical naming.

- [email-tenant-byod-plan.md](email-tenant-byod-plan.md) — SHIPPED 2026-08-06: per-site SES tenants + BYOD sending domains + kindredquill.email shared lane with author handles (doc carries the locked decisions + ops gate)
- [data-model.md](data-model.md) — delegated-type (`Recording`/`Recordable`) content model
- [schema.rb](schema.rb) — notional Rails schema for the data model
- [account-creation-concern.md](account-creation-concern.md) — `Account::Foundable` + `Signup` flow
- [fizzy-authentication.md](fizzy-authentication.md) — Fizzy's passwordless auth protocol
- [fizzy-user-account-model.md](fizzy-user-account-model.md) — Fizzy's User / Account / Access layer
- [multi-tenancy.md](multi-tenancy.md) — shared-DB, row-level tenancy (`Current.account`)
- [database-and-scaling.md](database-and-scaling.md) — SQLite vs MariaDB; when to split app servers
- [lexxy-and-active-record.md](lexxy-and-active-record.md) — Lexxy editor + Action Text coupling
- [ses-tenants.md](ses-tenants.md) — SES tenant isolation (Aug 2025 feature): per-Site reputation + auto-pause on the shared identity — the reputation firewall's design answer (context block, verify API before implementing)
- [email-architecture.md](email-architecture.md) — CANONICAL email map: four audience streams, all-SES, identity/domain plan, economics, import policy, migration sequence (supersedes ADR 0015's posture in part)
- [ses-migration-runbook.md](ses-migration-runbook.md) — Phase 0 (AWS + DNS) checklist for the Mailgun → SES/SNS migration (ADR 0015)
- [phase-2-static-serving.md](phase-2-static-serving.md) — CANONICAL delivery plan: Phase 2 (static serving cut-over) + Phase 2.5 (email transition)
- [hugo-build-pipeline.md](hugo-build-pipeline.md) — Phase 2 build pipeline: Rails exports JSON contract → pinned Hugo + pre-baked themes → R2 pointer-flip deploys (ADR 0021)
- [filibuster-merovex-parity.md](filibuster-merovex-parity.md) — gap analysis: what the `filibuster` theme must gain to capture the live merovex.press public design (multi-author REQUIRED; open questions; books/series index pages shipped 2026-07-31)
- [site-designer.md](site-designer.md) — SiteDesigner design plan: manifest-driven rail, Site-draft save semantics, preview = local Hugo build in an iframe, CSS foundation pass (layers, `mode` axis, mobile-first), build order (ADR 0022)
- [site-designer-user-guide.md](site-designer-user-guide.md) — author-facing copy (seed of "How to use this page"): the three-rung brand ladder, header controls, palettes + light/dark mode + custom colors, the books section, font pairings
- [draft-design-staging.md](draft-design-staging.md) — status/handoff: versioned `site_design_versions`, Save≠publish, `preview.kindredquill.com` staging host; open items (revert UI, Cloudflare custom domain, deploys)
- [saas-static-hosting-plan.md](saas-static-hosting-plan.md) — five-phase plan: static publish to Cloudflare R2 + Worker, multi-tenant SaaS (Fizzy pattern), BYODomain via CF for SaaS, per-tenant SES
- [newsletter-bot-protection-plan.md](newsletter-bot-protection-plan.md) — IMPLEMENTED & LIVE (2026-08-07): Hugo newsletter band → `POST /newsletter` island; pinned honeypot + per-account Cloudflare Turnstile (fail-closed) + origin lockdown; see its "As built" section for the deltas, [dynamic-islands](concepts/dynamic-islands.md) for the durable contract

## Decisions (ADRs)

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](decisions/0001-adopt-work-tracking-wiki.md) | Adopt a work-tracking wiki | superseded → 0003 | 2026-07-01 |
| [0002](decisions/0002-domain-vocabulary-person-user-account.md) | Domain vocabulary — Person / User / Account | accepted | 2026-07-01 |
| [0003](decisions/0003-collapse-wiki-into-docs.md) | Collapse documentation into a single docs/ folder | accepted | 2026-07-01 |
| [0004](decisions/0004-top-bar-app-shell.md) | Top-bar app shell — profile & notifications top-right | accepted | 2026-07-02 |
| [0005](decisions/0005-mobile-hotwire-native-pwa-dev.md) | Mobile — Hotwire Native target, PWA in development | accepted | 2026-07-02 |
| [0006](decisions/0006-record-recordable-generic-spine.md) | Record/Recordable — generic, tenant-agnostic content spine | accepted | 2026-07-03 |
| [0007](decisions/0007-versioned-recordables.md) | Versioned recordables — event-tagged immutable versions | accepted | 2026-07-03 |
| [0008](decisions/0008-books-series-recordables.md) | Books & Series — versioned recordables, shared-owner cover, Record-keyed join | accepted | 2026-07-08 |
| [0009](decisions/0009-distributors-and-changelog-events.md) | Distributors on the Record; cover & link change-log events | accepted | 2026-07-08 |
| [0010](decisions/0010-id-first-public-slugs.md) | Public URLs — id-first slugs | accepted | 2026-07-08 |
| [0011](decisions/0011-subscribers-and-consent-log.md) | Subscribers — current-state row + append-only consent log | accepted | 2026-07-08 |
| [0012](decisions/0012-broadcast-posts-as-newsletters.md) | Newsletters — broadcast a post (HEY World model) | accepted | 2026-07-09 |
| [0013](decisions/0013-broadcast-metrics-via-mailgun.md) | Broadcast metrics via Mailgun event webhooks | superseded → 0015 | 2026-07-09 |
| [0015](decisions/0015-email-relay-mailgun-to-ses.md) | Email relay — migrate Mailgun → Amazon SES/SNS | accepted | 2026-07-10 |
| [0016](decisions/0016-admin-backend-domain-admin-only.md) | Admin backend is domain-admin-only; auth + account move out of /admin | accepted | 2026-07-10 |
| [0017](decisions/0017-phase-1-tenancy-model.md) | Phase 1 tenancy model — explicit account-start scoping on the Record spine | accepted | 2026-07-28 |
| [0018](decisions/0018-app-host-and-tenant-hosts.md) | App host + tenant hosts — admin moves to kindredquill.com/{SLUG}/admin | accepted, amended → 0019 | 2026-07-28 |
| [0019](decisions/0019-app-subdomain-and-account-picker.md) | App host moves to app.kindredquill.com; account picker at its root | accepted | 2026-07-28 |
| [0020](decisions/0020-join-code-signup-and-root-role.md) | Join-code signup, owner_id authority, and the root role | accepted | 2026-07-28 |
| [0021](decisions/0021-hugo-static-site-generator.md) | Hugo renders the public sites — templates leave Rails | accepted | 2026-07-29 |
| [0022](decisions/0022-sitedesigner-design-json-sovereignty.md) | SiteDesigner + design.json sovereignty — the switcher is retired | accepted | 2026-07-31 |
| [0023](decisions/0023-circles-cross-account-buckets.md) | Circles — cross-account buckets; invite-only invariant; bucket goes polymorphic | accepted | 2026-08-05 |
| [0024](decisions/0024-notifications-stamped-copy-digests.md) | Notifications — stamped copy, bell + tiered email digests | accepted | 2026-08-05 |
| [0025](decisions/0025-canonical-delivery-events.md) | Canonical delivery events — one vocabulary, two ESP adapters (Postmark + SES) | accepted | 2026-08-05 |
| [0026](decisions/0026-signup-source-retention.md) | Signup source retention — fingerprint the neighborhood, keep consent IPs, never visit IPs | accepted | 2026-08-23 |

## Concepts

- [domain-vocabulary](concepts/domain-vocabulary.md) — canonical names as shipped: User (global login) / Account ("site") / polymorphic bucket / Circle / Person (reader)
- [circles](concepts/circles.md) — invite-only author groups: membership, pulses/beats, boosts, @mentions (incl. the Lexxy attachment-chip mechanics)
- [circle-wall](concepts/circle-wall.md) — the Wall (reverse-chrono feed of Messages + Beats, thread/edit modals, live boost/comment broadcasts) + the Commons singleton circle (candidate view, built 2026-08-06)
- [bulletins](concepts/bulletins.md) — platform announcements: root→everyone, nil-bucket Publishable record, bell-only fan-out (built 2026-08-06)
- [dynamic-islands](concepts/dynamic-islands.md) — Rails endpoints on static tenant hosts: the Worker's island allowlist, the X-Island-* header contract (auth / host / IP restore), rendering rules (absolute assets, no flash), and the Ruby 4 + caching gotchas (built 2026-08-07)
- [notifications](concepts/notifications.md) — kinds table, bell + digest channels, URL stamping, per-kind icons
- [goals](concepts/goals.md) — Goals & Tallies on the User bucket; rate vs project; display-card sets
- [merovex-press-public-site](concepts/merovex-press-public-site.md) — the public front-of-house (public layout, `press.css`, `PublicController`)
- [app-menu](concepts/app-menu.md) — the Basecamp-style jump menu (native popover + type-to-filter)
- [theme-background-colors](concepts/theme-background-colors.md) — site/canvas backgrounds + tints; **rethemed 2026-07-08 to the Merovex palette**
- [theme-model-playbook](concepts/theme-model-playbook.md) — the three appearance axes (mode / tint / accent) + how-to steps to change each
- [app-shell](concepts/app-shell.md) — top-bar shell; responsive nav; the responsive-web vs Hotwire Native mobile fork
- [css-architecture](concepts/css-architecture.md) — CUBE/BEM hybrid: layers, u- compositions/utilities, standard BEM blocks, exceptions via modifiers/data-attrs
- [break-glass-sign-in](concepts/break-glass-sign-in.md) — email-independent console sign-in: `auth:setup_admin` (bootstrap first admin) + `bin/kamal rescue-code` (break-glass); sessions/SES-sandbox notes
- [public-image-handling](concepts/public-image-handling.md) — Active Storage on the public site: cover WebP variants + fragment-cache versioning (the "covers disappeared" incident), and web-WebP/email-JPEG Action Text attachments

## Entities

_None yet. Create from `_templates/entity.md` → `entities/<slug>.md`._

## Summaries

_None yet. Create from `_templates/summary.md` → `summaries/<slug>.md`._
