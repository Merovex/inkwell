# Custom-domain onboarding (Cloudflare for SaaS)

How an author connects their own domain (e.g. `merovex.press`) so the edge
Worker serves their published site over TLS. Five moving parts: the Rails UI,
the Cloudflare custom-hostname API, the KV write, the author's DNS, and a
status poll.

## Architecture

```
author's browser
      │  https://www.merovex.press
      ▼
Cloudflare edge  ──► kindquill zone custom hostname (cert) ──► Worker route */*
      │
      ▼  kindredquill-edge (edge/src/index.js)
   HOSTNAMES KV:  "www.merovex.press" → "merovex"   (bare host → account slug)
   SITES R2:      sites/merovex/pointer.json {build_id}
                  sites/merovex/builds/<id>/…        (the published static site)
      │
      ▼  x-kq-build: <id>
   200 OK
```

The Worker resolves the incoming host against **HOSTNAMES KV** to an account
slug, reads that slug's `pointer.json` from **SITES R2** for the current build,
and serves the build. Onboarding's job is to (a) provision a Cloudflare custom
hostname + certificate for the domain and (b) write the KV mapping.

Non-secret ids live in `config.x.cloudflare` (ENV-overridable): zone
`1eb37a3d7c529846411c5030707a0d5f`, account `a65cb156b161e9bcd5107601fcc6255a`,
KV namespace `31cc38518280423694f78a0ae0726878`, CNAME target
`sites.kindredquill.com`.

## Prerequisites (one-time, done by a human — not the app)

1. **API token** — create in the Cloudflare dashboard with:
   - Zone → SSL and Certificates → **Edit** on kindredquill.com
   - Account → Workers KV Storage → **Edit**
   Store it in Rails credentials as `cloudflare.api_token`
   (`bin/rails credentials:edit`). The app never handles token creation.
2. **SSL/TLS mode** — pin the kindredquill.com zone off "automatic" (Full or
   Full (strict) to match the origin), so a mode flip can't break tenants.
3. **Mail** — confirm SPF/DKIM/DMARC still pass after any DNS changes; the
   `pm-bounces` and marketing identities must keep delivering.

## The flow

Code map: `DomainConnection` orchestrates; `Cloudflare::Client` makes the API +
KV calls; `CustomDomain` is the per-hostname row; `CustomDomainStatusJob` polls.

### Step 1 — Author enters the domain (`CustomDomainsController#create`)
`Hostname` normalises the input: downcase, strip scheme/path/port/trailing dot,
require an ASCII (or punycode) registrable hostname, and **reject anything under
`kindredquill.com`** (our namespace). A **UNIQUE index on `custom_domains.
hostname`** plus a pre-check rejects a domain already connected to another
account — the check that matters, because the last KV write would otherwise win.

We onboard **both** `merovex.press` and `www.merovex.press` (two rows, two KV
keys, two custom hostnames), treating **`www` as canonical** — authors type the
bare domain but `www` is what they can actually CNAME.

### Step 2 — Create the custom hostname (`Cloudflare::Client#create_custom_hostname`)
`POST /zones/{zone}/custom_hostnames` with `ssl.method: "txt"` (DV
pre-validation — the cert issues *before* DNS cuts over, avoiding the TLS-error
window that `http` validation opens). The returned `id` is saved on the row (to
poll and to delete on disconnect); the response's DV-TXT record is shown to the
author.

### Step 3 — Write KV *before* DNS (`Cloudflare::Client#kv_put`)
`PUT …/storage/kv/namespaces/{ns}/values/{host}` with the **plain slug** as the
body — no JSON wrapper (the Worker reads a bare string). One key per hostname.
Done before the author changes DNS so the Worker is ready the instant traffic
arrives. Note: the Worker caches KV reads for **300s**, so a correction takes up
to five minutes to propagate.

### Step 4 — Show DNS instructions (`custom_domains/index.html.erb`)
> **Record 1** — Type: `CNAME` · Name: `www` · Target: `sites.kindredquill.com`
> **Record 2** — Type: `TXT` · Name: `_acme-challenge.www` · Value: *(each
> outstanding `validation_records` entry)*

Kept literally "type, name, value" — that's what every registrar's form asks.

Two things the first cut of this page got wrong, both of which stranded a real
domain (benwilsondev.com, 2026-08-26):

- **`ssl.validation_records` is a list, not a record.** Cloudflare carries one
  entry per in-flight validation attempt, so a rotated order leaves the old
  value *and* a new one outstanding, and the certificate issues only when every
  one of them is published. Rendering `.first` hid the blocking value while the
  author dutifully re-added the one they already had. The rows store the whole
  set (`custom_domains.validation_records`, JSON) and the page renders all of
  them, saying explicitly that the values coexist on one name.
- **The records are not one-time.** Cloudflare re-uses them at renewal, so
  nothing should tell the author to delete them. Only rows still short of
  `live` render instructions at all — a finished hostname kept advertising its
  spent token otherwise.

### Step 5 — Poll until active (`CustomDomainStatusJob`)
`GET …/custom_hostnames/{id}` on a backing-off background job. A domain is
**live only when `result.status` is `active` AND `result.ssl.status` is
`active`** — a TLS handshake can succeed before `ssl.status` flips, so "the site
loaded for me" is not the signal. When every row is live the job bridges the
canonical apex onto `accounts.domain` (legacy host resolution + apex redirect)
and emails the author (`DomainMailer#live`).

The chain runs ~25h (30 attempts, backoff capped at an hour). It used to run
~2.6h, which was shorter than the time it takes most authors to get to their
registrar — so the common case was the chain dying before DNS landed, and then
nothing ever looking at the row again. When it does run out the rows go to
`status: "error"`, which means *nothing is watching any more*, not *this domain
is broken*: `CustomDomain::UNRESOLVED_STATUSES` keeps them eligible, opening the
domains page re-enqueues the poll, and the Check badge still polls inline. The
page says so rather than showing a "verifying" that will never change.

### Diagnosing a stuck row (`CustomDomain::Diagnosis`)
Reads public DNS and names the first unmet precondition. One rule matters more
than the DNS reading itself: **when `cloudflare_status` is active, Cloudflare
has verified the hostname and routing is settled**, whatever our resolver
infers. An author whose own zone is on Cloudflare orange-clouds the record, so
it answers with *their* proxy addresses and never exposes the CNAME — reading
DNS alone concludes `:proxied` and tells them to disable a proxy that is
carrying their traffic perfectly well (and their own wildcard certificate makes
the site look finished meanwhile). Believing our own guess over Cloudflare's
answer is how that advice reached a working domain.

## The merovex.press wrinkle

`merovex.press` is a zone in this same Cloudflare account, and it currently has
live Pages projects. Two cautions when testing on it:
- Create the `www` CNAME → `sites.kindredquill.com` as **DNS only (grey cloud)**.
  A proxied record here is orange-to-orange, which misbehaves for SaaS.
- Pick a hostname that isn't already serving something — don't test on a name a
  Pages project is using.

## Apex vs www

`merovex.press` with no `www` can only be CNAME'd at the apex via Cloudflare's
CNAME flattening; most registrars can't do that, and plain A records to a SaaS
target aren't supported without apex proxying. **Build around `www`** and offer
an apex → `www` redirect.

## Failure modes (handled in the UI)

- **TXT missing/wrong** → `ssl.status` sits at `pending_validation`. The index
  view shows the exact expected TXT name/value, not a spinner.
- **DNS before KV** → the Worker returns "No site is configured for this
  domain" (reads as a broken site). We always write KV in step 3, before step 4.
- **Disconnect** (`DomainConnection#disconnect`) deletes the KV key **and** the
  custom hostname — leaving the hostname would keep eating the 100-hostname
  allowance and keep resolving.

## Verify end-to-end

Once `merovex.press` is done: `curl -sI https://www.merovex.press/` returns
`200` with an `x-kq-build` header naming the build id.

## Still pending (separate work)

- **R2 publisher**: the exporter/renderer write builds to local disk
  (`BUILDS_PATH`); a Publisher must sync `sites/<slug>/builds/<id>/` to R2 and
  write `sites/<slug>/pointer.json` (`{ "build_id": "<id>" }`). Needs an R2 API
  token scoped to `kindredquill-sites`.
- **Housekeeping**: reserved slug/labels are in `Sluggable::RESERVED_SLUGS`;
  decide whether to proxy the apex and `app` (to stop publishing the VM IP).
