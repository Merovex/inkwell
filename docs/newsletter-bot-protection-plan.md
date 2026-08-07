# Newsletter Signup — Static Form + Bot Protection Plan

*Status: proposed (2026-08-07; revised same day after validation against the
code, and again to add origin lockdown — see log). Scope: wire the Hugo public
newsletter band to the Rails signup endpoint, and stop bots at the door so
their bad addresses never trigger a confirmation send. Lands as part of the
Phase 2 theme + the Merovex cut-over — see [[phase-2-static-serving]].*

## Problem

The public site is (Phase 2) static Hugo served from R2 by a Worker; the real
signup flow lives in Rails (`SubscriptionsController`, ADR 0011 —
[[0011-subscribers-and-consent-log]]). Today the Hugo newsletter band renders
only a `mailto:` fallback (`vendor/filibuster/layouts/_partials/sections/
newsletter.html`), whose own comment anticipates wiring a real form "when the
contract grows a signup endpoint." Three things to solve:

1. **Feed Rails from a static page** — the form is baked at build time and must
   post to Rails, and should appear only when the account can actually send the
   confirmation (`account.ses_tenant_provisioned?`).
2. **Bots → sender reputation.** A bot submitting a *well-formed but fake*
   address (`xk39@gmail.com`) passes the app's pre-send hygiene (format /
   reserved-TLD / disposable — no MX lookup, by design; see
   `app/models/subscriber.rb`), so **the confirmation email is sent and
   hard-bounces**. At volume that spikes SES bounce rate (>5% review, >10%
   possible pause) and risks spamtraps. Double opt-in protects list *quality*
   but does **not** stop that one confirmation send from bouncing. A plausible
   fake can't be detected at submit time, so the fix is to **stop the bot
   before the send**.
3. **The origin is a second front door.** All of the above assumes traffic
   arrives via the Worker. An attacker who discovers the Rails origin (its
   hostname or IP) can post to it directly, bypassing Cloudflare — no edge
   rate rules, no future Bot Management, nothing between them and the
   controller. The island endpoints must refuse traffic that did not come
   through the Worker.

## Routing — settled by the docs, not assumed

Per [[phase-2-static-serving]] §2.5, the Worker serves static bytes from R2 and
**proxies an enumerated allowlist of dynamic islands to the Rails origin** —
`POST /newsletter` and `GET /newsletter/sent` are on that list. Consequences:

- The form posts to a **same-origin `/newsletter`** on the tenant host (e.g.
  `merovex.press`); the Worker proxies to Rails. **No cross-origin, no CORS.**
- The success redirect to `/newsletter/sent` is also a proxied island → the
  visitor **stays on the tenant host**.
- **One Worker allowlist addition** — `GET /newsletter/rejected` (see §2). The
  honeypot + Turnstile fields themselves ride inside the existing
  `POST /newsletter` island.
- **The failure paths must not target `GET /newsletter`.** Today `create`'s
  rescue and the rate-limit handler both redirect there with a flash alert —
  but `GET /newsletter` is *not* on the island allowlist (post-cutover the
  Worker serves whatever static bytes live at that path), and flash needs a
  session cookie plus a Rails-rendered page, neither of which a static-form
  visitor has. Fix in §2.
- **The Worker is the only sanctioned door.** Because every legitimate island
  request transits the Worker, the Worker can vouch for its own traffic — the
  basis of the origin lockdown in §2a.

## Defense stack

Already shipped (no work):

- **Double opt-in** — `Subscriber.opt_in` + confirmation flow (ADR 0011).
- **Config-set isolation** — confirmation on the transactional SES set
  (`app/services/email_connection.rb`), so signup bounces don't touch marketing
  reputation. See [[ses-tenants]].
- **Rate limiting** — `rate_limit to: 10, within: 3.minutes` on `create`.

New (this plan): a **pinned honeypot** + **Cloudflare Turnstile** front door,
plus an **origin lockdown** so the front door is the only door. This reaches
Buttondown-grade posture (their stack = risk-scoring firewall + CAPTCHA +
double opt-in + disposable-blocking) by substituting Turnstile's ML for a
homegrown scoring engine — no HMAC rotation, no scoring engine, no release
job to own. Turnstile is free (unlimited verifications; 20 widgets × 10
hostnames on the free tier — ample for one shared widget across tenant hosts).

Check ordering in `create`, cheapest first: **origin header → honeypot →
rate limit → Turnstile siteverify → hygiene → opt_in.** The first three cost
nothing; siteverify is the only outbound call and runs last among the guards,
so a hammering bot burns 403s and 429s, not HTTPS round-trips.

## Implementation

### 1. Rails — `SubscriptionsController#create`
- **Skip CSRF on `create` only.** The page is static from R2 with no
  Rails-rendered token and no session cookie, so forgery protection can't apply.
  The action is anonymous and guarded by origin lockdown + honeypot +
  Turnstile + rate limit + double opt-in.
- **Drop `invisible_captcha` from this controller; hand-roll the honeypot.**
  The gem's session traps don't just "not fire" on a static form — they fire on
  **every** submission: `timestamp_spam?` treats a *missing* session timestamp
  as spam ("form was not fetched"), and `spinner_spam?` rejects when the param
  doesn't match the session value. A session-less static POST has neither, so
  every legitimate signup would hit `discard_spam` and silently vanish.
  `timestamp_enabled: false` can be passed per-controller, but **spinner is
  global-only** (`InvisibleCaptcha.spinner_enabled`, default true, no
  initializer in the repo) — disabling it globally would weaken the
  session-backed traps on `signups`, `sessions`, and `contacts`. So: remove the
  gem from `SubscriptionsController` and replace it with a ~5-line
  `before_action` that checks the **pinned honeypot field name** (a shared
  constant, see §3) and calls the existing `discard_spam` when filled.
- **Verify Turnstile before `Subscriber.opt_in`** — a small `TurnstileVerifier`
  PORO calls siteverify with the secret + `cf-turnstile-response`.
  **Omit `remoteip` from siteverify until §2 lands** — it's optional, and
  passing the Worker's egress IP (which is what `request.remote_ip` returns
  until then) would fail verification, which under fail-closed blocks everyone.
  **Fail closed**: on a failed or unreachable verify, block with a friendly
  "try again" message (protects reputation during a Cloudflare outage at the
  cost of losing real signups in that rare window). Log rejects via the
  existing `log_rejected_signup` path.
- **Add a `rejected` island for the failure paths.** New
  `GET /newsletter/rejected` → `subscriptions#rejected`, rendering the existing
  deliberately-vague message in the `public_minimal` layout (mirrors `sent` —
  a plain page, no flash, no session) with a link back to the site. Point
  `create`'s rescue and the rate-limit handler there instead of
  `newsletter_path`. One-line addition to the Worker island allowlist
  ([[phase-2-static-serving]] §2.5 says islands are enumerated from routes.rb,
  so this is the sanctioned move).

### 2. Worker → Rails: forward the real client IP
Three things key off `request.remote_ip`: the `rate_limit` bucket, Turnstile's
`remoteip`, and the consent log's IP (ADR 0011 provenance). Once the Worker
proxies, Rails sees Cloudflare egress IPs — all visitors would share a handful
of rate-limit buckets (real users throttled at 10/3min collectively), and the
consent log would record the wrong provenance. The Worker must forward
`CF-Connecting-IP` and Rails' `RemoteIp` middleware must be configured to
trust the proxy (no `trusted_proxies` config exists in the repo today). Once
wired, re-add `remoteip` to siteverify.

### 2a. Origin lockdown: Worker shared secret (new)
Close the direct-to-origin path in two tiers.

**Tier 1 (this plan, ships with §1): shared-secret header.**
- The Worker attaches `X-Island-Auth: <secret>` to every proxied island
  request. Secret lives in the Worker as a Wrangler secret and in Rails
  credentials — same handling pattern as the Turnstile secret in §6.
- Rails: one `before_action :require_island_auth` in a small
  `IslandProtected` controller concern, included by every island controller
  (`SubscriptionsController` now; `ContactsController` when its island lands).
  Compares with `ActiveSupport::SecurityUtils.secure_compare`, returns a bare
  `head :forbidden` on mismatch or absence — no redirect, no body, no logging
  beyond a counter. It runs **first** in the guard chain: cheaper than the
  honeypot check and conclusive.
- **Islands only.** Admin/app routes on the Rails host keep their existing
  session auth; the concern applies where session auth doesn't exist.
- **Rotation:** two accepted secrets in Rails (current + next) so the Worker
  can roll without a coordinated deploy; drop the old one after cutover.
  Document in the runbook alongside Turnstile key rotation.

**Tier 2 (deferred, tracked): network-level lockdown.**
Firewall the Rails origin to Cloudflare's published IP ranges, or move the
origin behind a Cloudflare Tunnel so it has no public ingress at all. Stronger
than the header (an attacker who somehow obtains the secret still can't reach
the origin) but touches infra provisioning, so it lands with the hosting
hardening pass, not this plan. The header tier is sufficient against the
realistic attacker — someone who scraped the origin hostname from DNS history,
certificate transparency logs, or an old A record.

### 3. Exporter contract → Hugo
- Add to the newsletter block in `Exporter` (`app/models/exporter.rb`):
  `enabled: account.ses_tenant_provisioned?` and the public `turnstile_sitekey`.
- The endpoint is the stable island `/newsletter` (relative action). Carry a
  **shared honeypot-field-name constant** referenced by both Rails and the
  contract so the two never drift.
- The island-auth secret is **not** part of the contract — it never appears in
  baked HTML. It exists only Worker-side and Rails-side.

### 4. Hugo partial
`vendor/filibuster/layouts/_partials/sections/newsletter.html`: when `enabled`,
render a real `<form method="post" action="/newsletter">` with the email field,
hidden `source`, the CSS-hidden honeypot input, and the Turnstile widget div +
script. Otherwise keep today's `mailto:` fallback.

### 5. CSS
Visually-hidden honeypot via a `u-` utility (per [[css-architecture]] /
css-html-standards) — a text input hidden with `tabindex=-1` / `aria-hidden` /
`autocomplete=off`, **not** `type=hidden`.

### 6. Ops (Cloudflare)
Widgets are **per-account and API-provisioned** (`TurnstileConnection` —
custom-domain onboarding is self-serve, so widget registration can't be a
manual step; keys are indexed on the account row, sharding is data entry not
schema). `DomainConnection` provisions/updates the widget on connect as a
**hard gate** and frees the slot on disconnect. Remaining manual work:
- Add **Account → Turnstile → Edit** to the existing Cloudflare API token.
- Tenant Zero backfill (domain connected before widgets existed):
  `TurnstileConnection.provision(account)` from the console, then republish.
- Generate the island-auth secret (`openssl rand -hex 32`) → Wrangler secret +
  Rails credentials (`island_auth_secrets`).
- If the Worker sets a CSP on static pages, add `challenges.cloudflare.com`
  to `script-src` and `frame-src` for the Turnstile widget.
An optional shared fallback pair (`turnstile.site_key`/`secret_key` in
credentials) covers accounts awaiting provisioning; per-account keys win.

## Decisions locked
- **Turnstile over a homegrown scoring engine** — buy Cloudflare's ML, defer the
  risk-score build until the pending/confirmed ratio proves it's needed.
- **Fail closed** when Turnstile verify is unreachable.
- **Hand-rolled pinned honeypot; `invisible_captcha` off this controller** —
  the gem's session-backed traps reject every session-less submit, and its
  spinner trap can only be disabled globally, which would weaken the auth and
  contact controllers.
- **Failure UX = `GET /newsletter/rejected` island** (mirrors `sent`) — the
  old `newsletter_path` + flash redirect assumes a Rails-rendered page and a
  session, neither of which exists post-cutover.
- **One widget per account, keys indexed on the account row** (supersedes the
  earlier "one shared widget": custom-domain onboarding is already self-serve,
  so hostname registration had to be automated, and per-account widgets fall
  out naturally — each gets its own hostname allowance, and the contract
  already carries the sitekey per account). Free-tier ceiling becomes 20
  widgets = ~20 signup-enabled accounts; revisit the tier before then.
- **Turnstile registration is a hard gate on domain connect** — a connected
  domain is a fully working domain; a soft failure would ship a visibly
  broken signup form.
- **Origin lockdown = shared-secret header now, network lockdown later** — the
  header closes the bypass with one concern and one Worker line; Tunnel/IP
  allowlisting is infra work deferred to the hosting hardening pass. The
  concern (`IslandProtected`) is the reusable unit: every future island
  inherits the protection by inclusion.

## Out of scope / deferred
- **Tier 2 origin lockdown** (Cloudflare IP allowlist or Tunnel) — see §2a;
  lands with the hosting hardening pass.
- **Signals + outcome capture** for a future scoring engine (feature rows +
  delayed labels: confirm status, SES bounce events, engagement). Valuable but a
  schema-coupling decision — needs explicit sign-off before building. Note the
  survivorship trap: survivors alone can't train a bot classifier (Turnstile
  deletes the negatives); the real training signal is *outcomes on survivors*.
- ~~**Cloudflare widget-API automation** for hostname registration~~ —
  **shipped** (the deferral assumed operator-provisioned onboarding; it is in
  fact self-serve, so `TurnstileConnection` + the `DomainConnection` hooks
  landed with the implementation).
- **Cloudflare Bot Management** (per-request bot score + JA3/JA4 + detection_ids)
  — the paid Enterprise version of the scoring engine; revisit only if/when an
  Enterprise contract happens anyway (e.g. the any-hostname Turnstile widget at
  custom-domain scale).
- **Per-press reputation firewall** (bounce/complaint auto-pause) — that's Phase
  2.5b's *back-door* layer ([[ses-tenants]]); Turnstile is the complementary
  *front-door* layer. No overlap.
- **`POST /contact` has the identical `invisible_captcha` problem** — it's also
  an allowlisted island, and `ContactsController` uses the same session-backed
  traps that would discard every static-form submission. Apply the same
  pattern (hand-rolled honeypot, `IslandProtected` concern, and its own
  failure-path decision) before cutover; tracked with the contact-form island
  work, not this plan.

## Verify
- Round-trip on the staging hostname per [[phase-2-static-serving]] §2.6.2:
  submit → confirmation email → confirm. This specifically proves a
  **session-less** submit succeeds (the failure mode the old
  `invisible_captcha` traps would have caused is silent).
- Confirm a filled honeypot discards (indistinguishable from success, nothing
  persisted), and a bad/absent Turnstile token fails closed onto
  `/newsletter/rejected` (per §1's friendly "try again" — a visible block is
  fine for Turnstile; stealth is the honeypot's job).
- **Origin lockdown:** a direct POST to the Rails origin (curl, no
  `X-Island-Auth`) returns a bare 403 with nothing persisted and no
  siteverify call made; the same POST with the header but via the origin
  still passes the concern (the header, not the path, is the credential) —
  confirming the Worker is the only holder of that credential is what makes
  the door singular. Verify secret rotation: Rails accepts both current and
  next during the roll.
- A hygiene-rejected address and a rate-limited burst both land on
  `/newsletter/rejected` (via the Worker, on the tenant host).
- With §2 wired: two clients behind different IPs get separate rate-limit
  buckets, and the consent log records the real client IP, not the Worker's.
- After launch, watch **SES bounce rate** and the **pending/confirmed ratio** as
  the tripwire for escalating (build the scoring engine / add Bot Management).

## Effort
~a day for items 1–5 + ~15 min Cloudflare setup (item 6). Item 2 (client-IP
forwarding) is a small Worker + middleware-config change that benefits every
island, not just this one. Item 2a tier 1 adds ~30 min: one concern, one
Worker header, one secret in two places. Lands with the Phase 2 theme.

## Refs
- Code: `app/controllers/subscriptions_controller.rb`,
  `app/models/subscriber.rb`, `app/models/exporter.rb`,
  `app/services/email_connection.rb`,
  `vendor/filibuster/layouts/_partials/sections/newsletter.html`
- Docs: [[phase-2-static-serving]], [[hugo-build-pipeline]], [[ses-tenants]],
  [[0011-subscribers-and-consent-log]], [[custom-domain-onboarding]]