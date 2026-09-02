# Inkwell / Kindred Quill

A multi-tenant home for authors — one Rails codebase wearing three faces:

- **Public sites** — each account's (site's) public face on its own domain,
  rendered by a Hugo static pipeline (Merovex Press is the first tenant)
- **Inkwell** — each site's admin, mounted on the app host at `/{SLUG}/admin`,
  where the author writes, publishes, designs, and moderates
- **The community layer** — on the app host: invite-only **Circles**
  (discussions, pulse check-ins, boosts, @mentions), personal **Goals**, and
  a **notification bell** with calm email digests

## Features

### The public site (per account)

- **Blog** — published posts at `/blog`, with an RSS feed
- **Book catalog** — published books at `/books`, grouped by series, each with
  store **buy-links** (click-throughs are counted before redirecting)
- **Author pages** — bio + published posts and books per pen name
- **Newsletter signup** — anonymous double opt-in with confirm / unsubscribe /
  keep-me-subscribed token links and a honeypot against bots
- **Contact form** — double opt-in as well; submissions are only ever read in
  the admin, never emailed onward
- **About, Privacy, and Terms** pages authored from admin system settings
- **SEO** — XML sitemap, dynamic robots.txt, meta/OpenGraph tags
- **First-party analytics** — Ahoy tracks visits client-side, so edge-cached
  pages still count
- **Fast** — page caching, Turbo Drive with prefetch, self-hosted variable
  fonts, responsive AVIF hero images, mobile hamburger nav

### Community & progress (the app host)

- **Circles** — invite-only, cross-account author groups: message boards with
  comment threads, golden invitation cards, a membership page, owner-first
  rosters (invite-only is an invariant, not a setting)
- **Pulse check-ins** — a scheduled question emailed to a circle's subscribers
  on cadence; answers collect as editable cards on the pulse page
- **Boosts & @mentions** — emoji appreciations and member mentions (typed
  `@handle`/`@email`, or picked from the editor's `@` prompt as an
  avatar-and-name chip) across circle content
- **Goals & tallies** — personal writing goals (rate or project), quick
  logging, and a chosen set of display cards per goal (completion ring, pace,
  rolling average, calendar, GitHub-style heatmap)
- **Notifications** — a live bell for invitations, mentions, boosts, replies,
  and pulse asks; email rides batched digests (4-hourly, daily for thread
  replies), and reading in-app first cancels the email

### Inkwell — the site admin (`/{SLUG}/admin`)

- **Blog posts** — rich-text (Lexxy) composer with drafts, scheduled
  publishing, pinning, excerpts, and per-post comment threads
- **Version history everywhere** — every content type keeps immutable
  published versions with a change log and tracked-changes diffs
- **Forum** — a message board with categories, drafts, and pinning
- **Chatroom** — a single live room for the install
- **Comments & boosts** — comments on posts and forum messages, and tiny
  boost appreciations on any record
- **Books & series** — versioned catalog entries with versioned covers,
  drag-sortable series membership, and store-link management
- **Newsletter broadcasts** — email a post to subscribers (now or scheduled),
  with delivery/open/click metrics fed by webhooks and HMAC-signed preview
  links
- **Subscribers** — roster with CSV export and manual unsubscribe
- **Missives** — the contact-form inbox with a Trash tab (soft delete only;
  a sweep purges at 60 days), and mailto replies from your own mail client
- **Traffic dashboard** — the `/admin` landing page: unique visitors, visits,
  page views, top landing pages and referrers over 30 days
- **Authors** — manage pen names/personas; content creators pick one when
  composing
- **System settings** — site name, tagline, logo, About/legal copy: the whole
  public identity
- **App menu** — a keyboard-driven jump-to sheet (search, arrow keys) over
  sections and recent records
- **Passwordless auth** — emailed magic-link sign-in; join-code signup with a
  referral chain; the first user (via first-run Setup) is platform root, and
  each account's owner administers their own site
- **PWA** — installable app scoped to `/admin`
- **Styleguide** — a living theme page rendering every standard component,
  with light/dark modes and Basecamp-style tint themes

## How content works

All authored content lives on a generic **Record/Recordable spine**: a stable
`Record` identity wrapping immutable, event-tagged versions. Drafts mutate;
published versions are frozen, giving a change log, tracked-changes diffs,
scheduled publishing, and version history for every content type (posts,
messages, comments, chat lines, books, series, pulse answers). Every record
belongs to a **bucket** — an Account (site content), a Circle (community
content), or a User (personal goals) — stamped at birth. Design decisions are
recorded as ADRs in [`docs/decisions/`](docs/decisions/); start with
[`docs/overview.md`](docs/overview.md) for the living synthesis.

## Stack

- Ruby 4.0.5, Rails main (8.2), SQLite, Puma
- Hotwire (Turbo + Stimulus) with import maps — no JS build step
- Propshaft with many small single-purpose CSS files (see
  `app/assets/stylesheets/application.css` for the architecture; do not bundle)
- Solid Queue / Solid Cache / Solid Cable
- Lexxy rich-text editor, Active Storage + libvips for images
- Email via AWS SES (migrating from Mailgun — see ADR 0015 and
  [`docs/ses-migration-runbook.md`](docs/ses-migration-runbook.md))
- Ahoy for first-party analytics

## Getting started

```sh
bin/setup        # installs gems, prepares the database, starts the server
bin/dev          # or just run the dev server (localhost:3000)
```

On a fresh database the sign-in page redirects to first-run setup, where the
first user created becomes the domain admin. Sign-in codes are emailed; in
development they open in the browser via letter_opener.

## Tests & checks

```sh
bin/rails test   # unit + integration
bin/ci           # the full CI script (tests, brakeman, bundler-audit, etc.)
```

## Deployment

Deployed with [Kamal](https://kamal-deploy.org) (`config/deploy.yml`) behind
Thruster. `bin/kamal deploy` from a configured environment.

## Documentation

[`docs/`](docs/) is the single home for design docs, entity references, ADRs,
and the work log. `docs/index.md` is the map.
