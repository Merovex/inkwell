# Inkwell / Merovex Press

An author's self-hosted home on the web — one Rails codebase wearing two faces:
**Merovex Press**, the anonymous public site at `/`, and **Inkwell**, the
admin-only backend at `/admin` where the author writes, publishes, and
moderates.

## Features

### Merovex Press — the public site (`/`)

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

### Inkwell — the admin backend (`/admin`)

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
- **Passwordless auth** — emailed magic-link sign-in; first-run setup promotes
  the first user to domain admin; everything under `/admin` is gated
- **PWA** — installable app scoped to `/admin`
- **Styleguide** — a living theme page rendering every standard component,
  with light/dark modes and Basecamp-style tint themes

## How content works

All authored content lives on a generic **Record/Recordable spine**: a stable
`Record` identity wrapping immutable, event-tagged versions. Drafts mutate;
published versions are frozen, giving a change log, tracked-changes diffs,
scheduled publishing, and version history for every content type (posts,
messages, comments, chat lines, books, series). Design decisions are recorded
as ADRs in [`docs/decisions/`](docs/decisions/); start with
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
