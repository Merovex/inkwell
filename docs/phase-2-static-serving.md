# Phase 2 — Static Serving Cut-Over (and Phase 2.5 — Email Transition)

*The canonical delivery plan for what follows Phase 1. Supersedes the
numbering in [saas-static-hosting-plan.md](saas-static-hosting-plan.md) (an
earlier draft where "Phase 1" meant static publish): in THIS numbering,
Phase 1 = multi-tenancy core (shipped 2026-07-28, ADRs 0017–0020), Phase 2 =
static serving, Phase 2.5 = the email transition, deliberately last.*

**The governing invariant, restated: no second tenant goes live before
Phase 2 ships.** Multi-tenant admin with one live tenant is safe; multi-tenant
public serving through Rails is the state that must never exist. (A test
account exists in production — fine: it has no audience, and the isolation
spec guards it.)

Goal: the public sites become files on R2 served by a Worker; Rails serves
only the app host. Droplet load drops to admin traffic. Appetite: two to
three weeks.

---

## What changed since this plan was first drafted

- **Host resolution already exists** (ADR 0018/0019): tenant domains and
  apex slug paths (`kindredquill.com/{SLUG}/…`) both serve per-account public
  sites from Rails today. The Worker replaces both.
- **`accounts.domain` is the host map's seed** — no hand-maintained list.
  `Account#public_address` answers "where does this press live."
- **The Site recordable exists** (1.5) with `site_name`/`tagline` + rich
  texts + logo. The `template` string and `theme` JSON columns were
  deliberately deferred — they arrive with 2.1/2.2 below.
- **The 1.5 shim is already retired** (old plan step 2.6.4) — Setting is gone.
- **Renderer inputs are all account-derived**: identity from `account.site`,
  absolute URLs from `account.public_address`, content from
  `account.records` (ADR 0017 accessors).
- **The rendering engine is Hugo, not extracted ERB** (ADR 0021,
  2026-07-29): §2.1–2.4 amended in place; full pipeline design in
  [hugo-build-pipeline.md](hugo-build-pipeline.md). Themes are being
  pre-built separately against its JSON contract.

## 2.1 Theme v1  *(amended 2026-07-29 — ADR 0021: Hugo, not ERB)*

One first-party **Hugo theme**, matching the current Rails public views'
page inventory: layout, home, blog index/show, book show, series show with
reading order, about/legal pages, subscribe page. The theme is pre-built
(owner-authored, own repo, versioned by tag) against the JSON contract in
[hugo-build-pipeline.md](hugo-build-pipeline.md) §4, in parallel with the
Rails-side pipeline work. Assets fingerprinted, referenced by hash. Add the
theme fields (`theme_name`, `theme_version`, `theme` JSON knobs via
`store_accessor`) to `sites` NOW — this is the moment their features exist.
v1 supports a deliberately tiny, declared set of theme knobs; they cross the
boundary inside `site.json`.

## 2.2 The renderer  *(amended 2026-07-29 — ADR 0021)*

The three-stage pipeline of
[hugo-build-pipeline.md](hugo-build-pipeline.md): an `Exporter` serializes
the account's current versions (the account accessors already encode
"highest live version") to the versioned JSON contract in a per-build
workspace; a pinned, vendored **Hugo** binary renders it against the theme
(content adapters materialize one page per book/series/post from the JSON —
Rails emits no per-page stubs); a `Publisher` syncs to R2. Rich-text bodies
cross as pre-rendered `body_html` fragments, so admin and public share one
renderer. Full Merovex build must complete in seconds —
full-rebuild-per-publish is the concurrency model; everything downstream
assumes builds are cheap.

Outputs per account: HTML pages, RSS/Atom feed, sitemap.xml, robots.txt, a
404 page, and `manifest.json` (account, theme version, contract version,
content high-water mark, file list with hashes).

## 2.3 SiteBuildJob

Solid Queue job keyed by account (`AccountTenanted` already carries context).
Publish transitions and Site edits enqueue it; a 30–60s debounce coalesces
bursts. Renders to a temp workspace, diffs against the previous manifest,
uploads changed files to an immutable per-build prefix, then **flips
`pointer.json`** — the atomic "build complete" marker *(amended 2026-07-29:
pointer-flip supersedes manifest-last; ADR 0021 /
[hugo-build-pipeline.md](hugo-build-pipeline.md) §5.4 — instant rollback is
rewriting the pointer)*. Failures alert Honeybadger and leave the previous
build serving — a failed build can never take a site down, only leave it
stale. The admin shows build status (queued/building/live at HH:MM) from
day one.

## 2.4 R2 layout and upload  *(amended 2026-07-29 — ADR 0021)*

`sites/{account_slug}/builds/{build_id}/…` + `sites/{account_slug}/
pointer.json` naming the live build; a reaper keeps the last 3 builds (the
slug, per the talking points — opaque, survives anything). S3-compatible
API, content-type set correctly (the historical footgun). Long max-age +
content hashing for assets; short max-age (60s) for HTML so publishes appear
promptly **without purge machinery** — this stands; worst-case staleness is
HTML max-age + the Worker's pointer cache TTL, inside the two-minute exit
criterion. No per-tenant buckets; the prefix is the tenancy.

## 2.5 The Worker  *(the serving component, not the email phase)*

- Host map in Workers KV: hostname → account slug. Seeded from
  `accounts.domain`; Cloudflare for SaaS custom hostnames write into this
  same map in the later domains phase.
- Request path: look up host, fetch `sites/{slug}/current{path}` (with
  /index.html resolution), serve with R2's etag, fall through to the
  account's 404 page.
- **Apex slug paths** (`kindredquill.com/{SLUG}/…`) route the same way with
  the slug taken from the path — the Worker replicates what the AccountHost
  extractor does today, so domain-less presses stay static too.
- Dynamic islands proxy to the Rails origin — **enumerated from routes.rb,
  not memory**. *Status 2026-08-07: the newsletter set is live (plus
  `GET /newsletter/rejected`), with the X-Island-Auth/Host/IP header
  contract — standard forwarding headers don't survive the origin's proxy
  hops; see [[dynamic-islands]]. 2026-08-23: `GET /buy/:id` is live too —
  the theme's `dist-url` partial emits `buy/<distributor id>` and the Worker
  proxies it (it had been emitting `out/…`, a path nothing served). The rest
  below still to land, each with its own hardening pass.* The list: `POST /newsletter` + `GET /newsletter/confirm|unsubscribe|
  keep/:token` + `GET /newsletter/sent`, `POST /contact` +
  `GET /contact/confirm/:token` + `GET /contact/sent`, `GET /buy/:id`
  (click counting), `POST /webhooks/ses` (stays on merovex.press per
  standing decision), and the **ahoy tracking endpoints** (`/ahoy/*` —
  visits/events are client-posted; miss this and analytics silently die at
  cut-over). Explicit allowlist; everything else static.
- The Worker never renders; it routes bytes.
- **Asset caching (2026-08-23).** Theme CSS/JS and the font sheet are
  fingerprinted by the Hugo build (`css/06-sections.<sha256>.css`, `js/…`,
  `fonts/…`) and the Worker serves any `.<hex>.css|js` filename
  `max-age=31536000, immutable` — a theme change reaches readers on their
  next page load. Everything else at a stable URL (HTML, covers, feeds, font
  files) keeps `max-age=0` (HTML) or a day + a week of SWR.

## 2.6 Merovex cut-over

1. Build + push the full Merovex site; run a **semantic-diff** script over
   the FULL sitemap against Rails-rendered output — extracted text, link
   graph, meta tags, feed entries, sitemap coverage (eyeballs miss things;
   a byte-level HTML diff died with the ERB path — ADR 0021).
2. Serve on a staging hostname; click everything; feeds validate; subscribe
   and contact round-trips work through the proxy.
3. DNS: point merovex.press (+ www) at the Worker. Rollback is pointing
   back; keep the Rails public routes deployed but dark for two weeks.
4. After soak: delete the Rails public controllers/views/caching and the
   public-route constraints; watch droplet metrics confirm the point.

## 2.7 Lift the invariant

With serving static and the admin tenant-scoped, tenant #2 is
architecturally safe. Onboarding the first real second account (join code →
press → publish → site appears on its apex URL with zero code changes) is
the phase's true smoke test.

### Phase 2 exit criteria

- Merovex serves from the Worker with feeds, forms, unsubscribe flows working.
- Publish-to-live under two minutes including debounce.
- A failed build demonstrably leaves the old site serving.
- Rails public routes deleted; droplet load reduced to admin traffic.
- A second account publishes a working site with no code changes.
- Tenancy-guard retirement decision made (its soak ends mid-phase).

---

# Phase 2.5 — Email Transition (deliberately last)

Everything email was frozen during Phase 1 by explicit decision. The full
inventory of what that froze, in two tranches:

**2.5a — Link-host decoupling (required before tenant #2 sends anything):**
- Subscriber-facing mail (broadcasts, drips, confirmations, unsubscribe)
  generates URLs from `account.public_address`, not the global `ses:host`
  credential. With Phase 2 shipped these links point at Worker-served pages
  and proxy islands.
- `MissiveMailer.digest` loses its `Account.first` fallback — becomes
  per-account (owner-addressed) or an explicit root report.
- Retire the `ses:host` credential.
- Subscribe/unsubscribe pages render under the subscriber's own account
  regardless of which host the token lands on.

**2.5b — Per-tenant sending (the old plan's "multi-tenant email" phase):**
- Per-tenant SES identities: platform sending domain by default, BYOD
  sending subdomain for presses with domains (DKIM/MAIL FROM/DMARC
  walk-through).
- Per-account configuration sets and message tags; bounce/complaint
  metrics split per tenant.
- The reputation firewall: per-press bounce/complaint monitoring with
  auto-pause, so one press's bad list can't sink the platform's delivery.

Until 2.5a lands, every tenant email flows through the current SES setup
with merovex.press links — correct for the only press with an audience.

## Explicitly still deferred beyond 2.5

Custom-domain self-service (Cloudflare for SaaS automation), list import,
billing/plan enforcement, per-account roles on account_users, open-beta
invite flip, circles. Each has its phase; none blocks these.
