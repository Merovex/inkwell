# Overview — Inkwell / Merovex Press

> Living synthesis of the current state of the project. Update this whenever the
> shape of the work changes. Keep it short — details live in linked pages.

## What this is

A Rails 8.2 app (Ruby 4.0.5) that wears **two faces on one codebase**:

- **Inkwell** — the **domain-admin-only backend** at `/admin/*` (app module
  `Inkwell`). Where the author writes, publishes, and moderates. Gated by
  `Admin::BaseController` ([0016](decisions/0016-admin-backend-domain-admin-only.md));
  sign-in and the user's own account live at the top level (`/session`, `/user/*`),
  and Comments/Boosts stay session-only (not admin) as a future member surface.
- **Merovex Press** — the anonymous **public site** at `/`. See
  [[merovex-press-public-site]].

(Formerly "Alcovo"; renamed 2026-07-08. Accepted ADRs 0001–0006 predate the
rename and keep the old name as history.)

This `docs/` folder is the single home for design/reference docs and the work
log; see [[CLAUDE]] for how it's maintained.

## Current state (2026-07-12)

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
- **Analytics & ops** — first-party Ahoy analytics (visits + events) with
  **visitor geography**: offline GeoIP (MMDB in `storage/geoip/`, no IP leaves
  the server; country/region kept, IP discarded after geocoding) feeding a
  jsVectorMap choropleth + unique-visitor country/region lists on the admin
  dashboard. Production error reporting via **Honeybadger**.

## Core vocabulary

Canonical names (see [[domain-vocabulary]] / [0002](decisions/0002-domain-vocabulary-person-user-account.md)):
**`Person`** (global login) ──< **`User`** (membership) ──< **`Account`** (tenant).
Retired: `Identity`, `Membership`, `Group`, `bucket`.

## Open threads

- Public **author** and **series** pages are still stubbed.
- A public **distributor click** redirect (increment `clicks`) is not wired yet.
- App-menu polish: focus-trap, lazy `turbo-permanent` frame, open hotkey.
- Geo database refresh is manual (`bin/update-geoip.sh`, monthly-ish) and the
  first deploy needs `geoip:backfill`; no automation yet.
- Reconcile [data-model.md](data-model.md) / [schema.rb](schema.rb) with the
  shipped spine; `Account` + `records.account_id` tenancy still deferred.
