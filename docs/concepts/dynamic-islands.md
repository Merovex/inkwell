---
type: concept
title: Dynamic islands — Rails endpoints on static tenant hosts
status: active
tags: [phase-2, worker, newsletter, turnstile, security, multi-tenancy]
created: 2026-08-07
updated: 2026-08-07
sources: [newsletter-bot-protection-plan.md, phase-2-static-serving.md, log.md]
---

# Dynamic islands — Rails endpoints on static tenant hosts

Post-cutover, a tenant host (merovex.press, cohwall.com) serves static bytes
from R2 via the edge Worker (`edge/src/index.js`). The **islands** are the
enumerated Rails-backed paths the Worker proxies to the origin instead —
everything else is static. Built and proven end-to-end 2026-08-07 (Merovex +
cohwall both completed signup → confirm round-trips).

## The allowlist (enumerated from routes.rb, phase-2 §2.5)

Live today: `POST /newsletter`, `GET /newsletter/sent|rejected`,
`GET /newsletter/confirm|unsubscribe|keep(/:token)`. Still to add as their
flows are hardened: `POST /contact` (+ its pages — the contacts controller
still carries session-backed spam traps that discard static submits),
`GET /buy/:id`, `/ahoy/*`, `POST /webhooks/ses`. Custom-domain hosts only so
far; the platform host (`sites.kindredquill.com`) has no Rails-side hostname
mapping yet.

## The header contract (the hard-won part)

The proxy hops in front of Rails (Cloudflare on the app host, kamal-proxy/
Thruster) **rewrite `X-Forwarded-Host` and `X-Forwarded-For` from their own
peer**, so nothing standard survives from Worker to Rails. The Worker
therefore sends three custom headers, and Rails' `IslandHost::Rewriter`
middleware (before `AccountHost::Extractor`) restores the standard ones —
**gated on the island-auth secret**, so nothing can be spoofed at the origin:

| Header | Carries | Restored into |
|---|---|---|
| `X-Island-Auth` | shared secret (Wrangler secret ↔ `island_auth_secrets` credentials array, current+next for rotation) | — (gate; `IslandProtected` concern also 403s non-Worker traffic) |
| `X-Island-Host` | tenant host | `X-Forwarded-Host` → `AccountHost` tenant resolution, redirect URLs |
| `X-Island-IP` | `CF-Connecting-IP` | `X-Forwarded-For` → rate-limit buckets, consent-log provenance (ADR 0011) |

Unprovisioned (`island_auth_secrets` empty — dev, test), both the rewrite and
the 403 gate are off; the test initializers force this even though the
credentials file is shared across environments.

## Rendering rules for island pages

- **Assets are absolute** (`config.asset_host = https://<APP_HOST>`): a
  relative `/assets/...` on a tenant host resolves into the Worker's static
  build and 404s. Fonts additionally need the `access-control-allow-origin`
  header on Rails' asset responses (cross-origin `@font-face`).
- **No flash, no session**: island pages are plain renders in the
  `public_minimal` layout. Failure paths redirect to the `rejected` island —
  never to `GET /newsletter` (not proxied) and never via flash.
- `redirect_to` works normally: the restored tenant host makes Rails emit
  tenant-host Locations, the browser re-enters the Worker.

## Gotchas that cost real debugging

- **Ruby 4 `Net::HTTP#post` sends no default Content-Type** (the Ruby 3
  fallback was removed) — a form POST without one gets `bad-request` from
  Cloudflare siteverify. Use `set_form_data`. Applies to any raw form POST.
- The Worker's build-pointer cache (30s) can serve the previous build just
  after a publish; site CSS carries a day of browser cache (stable URLs).
- Turnstile tokens are single-use, ~5-minute expiry; `TurnstileVerifier`
  logs siteverify `error-codes` on every reject so failures self-diagnose.

## Related

[[newsletter-bot-protection-plan]] (the design + decisions),
[[phase-2-static-serving]] §2.5 (the Worker), [[ses-tenants]],
[[0011-subscribers-and-consent-log]]. Enablement: sending-domain connect
auto-provisions SES tenant + per-account Turnstile widget
(`EmailConnection#connect`), or `bin/rails "newsletter:enable[ident]"`.
