---
type: concept
title: SES/SNS migration runbook — Phase 0 (AWS + DNS)
status: active
tags: [rails, email, ses, sns, aws, dns, runbook, migration]
created: 2026-07-10
updated: 2026-08-05
sources: [decisions/0015-email-relay-mailgun-to-ses.md, decisions/0025-canonical-delivery-events.md]
---

# SES/SNS migration runbook — Phase 0 (AWS + DNS)

Operational checklist for the **prerequisite** AWS/DNS work behind
[[0015-email-relay-mailgun-to-ses]]. Phase 0 is all console + DNS — **no app
code**. Work top to bottom; each step says how to verify it's green before the
next. Check boxes as you go; this is a living doc.

> **Why this order:** DNS propagation and the sandbox-exit approval (~24h) are
> the long-lead items — we file those early even though they're logically
> "later," to beat the next Mailgun invoice. One step (SNS subscription, 7) needs
> the Phase-2 webhook endpoint live to confirm; it's flagged where it bites.

## Variables

**Two sending identities** so transactional and marketing sign with different DKIM
`d=` domains — a spammy newsletter run can't drag magic-links toward spam. See
[[0015-email-relay-mailgun-to-ses]] / the reputation-isolation rationale.

| Key | Value | Notes |
|-----|-------|-------|
| Root domain | `merovex.press` | org domain; DMARC published here covers all subdomains |
| AWS region | `us-east-1` | **confirm** — MAIL FROM MX + tracking CNAME targets are region-specific |
| **Transactional** identity | `auth.merovex.press` | magic-links; send `from: noreply@auth.merovex.press` |
| **Marketing** identity | `news.merovex.press` | newsletter; send `from: noreply@news.merovex.press` |
| Transactional MAIL FROM | `bounce.auth.merovex.press` | SPF alignment for the auth stream |
| Marketing MAIL FROM | `bounce.news.merovex.press` | SPF alignment for the news stream |
| Tracking (redirect) domain | `click.news.merovex.press` | branded open/click links — **marketing only** |
| Link host (email body URLs) | `merovex.press` | `default_url_options[:host]`; independent of the sending identity |
| SNS webhook URL | `https://app.kindredquill.com/webhooks/ses` | **corrected 2026-09-04** — was `merovex.press`, see Step 7 |
| DMARC report inbox | `dmarc@merovex.com` | cross-domain → needs the `_report._dmarc` authz record on merovex.com (Step 4) |

Where you edit DNS: **______** (registrar / Cloudflare / Route 53 — note it here).

## Round 2 — platform identities (kindredquill.com), 2026-08-05

The multitenant cut: sending identities become **platform-owned** (every
tenant's mail authenticates as kindredquill.com, tenant name as display label,
tenant contact as Reply-To — the Substack model). Split per the settled
provider policy ([[0025-canonical-delivery-events]] + log note 2026-08-05):
**SES gets only the bulk identity; the must-deliver identity is verified in
Postmark, not SES.**

| Key | Value | Notes |
|-----|-------|-------|
| Root domain | `kindredquill.com` | DMARC published here; **never sends** |
| AWS region | `us-east-1` | unchanged |
| **Bulk** identity (SES) | `news.kindredquill.com` | broadcasts + drips + welcome; future `ses.marketing_from` |
| Bulk MAIL FROM | `bounce.news.kindredquill.com` | SPF alignment |
| **Must-deliver** identity (Postmark) | `auth.kindredquill.com` | sign-in codes, magic links, opt-in confirmations |
| Standby (Postmark, optional) | `news.kindredquill.com` | dual-verify → ESP flip keeps one From identity |
| Tracking | default SES domain | Step 5 decision stands |
| SNS webhook URL | `https://app.kindredquill.com/webhooks/ses` | webhook routes are host-unconstrained |
| DMARC report inbox | `dmarc@merovex.com` | needs `kindredquill.com._report._dmarc.merovex.com` TXT (Step 4 pattern) |

Steps that apply, against the checklist below: **2** (one identity in SES:
`news.` only — auth goes in the Postmark console instead), **3** (MAIL FROM on
`news.`), **4** (DMARC on the kindredquill.com root + the cross-domain report
authz on merovex.com), **6** (reuse the existing `inkwell-marketing` /
`inkwell-transactional` config sets — nothing new to create), **7** (same SNS
topic; add/confirm the app-host subscription), **8 as revised** (suppression
stays OFF). Sandbox exit (9) is already done — the account is shared.

Identity cleanup once cutover lands: drop `auth.merovex.press` (SES carries no
auth mail), drop the cohwall identities (owner, 2026-08-05); keep
`news.merovex.press` until `ses.marketing_from` points at the new identity.
`verkilo.com` is another product — untouched. Code follow-ups at cutover:
`ses.marketing_from` credential → the new address; `marketing_from`'s
hardcoded "Ben Wilson" display name → the tenant's site name; transactional
default From moves off the root (`support@kindredquill.com` → an
`auth.kindredquill.com` sender, keeping support@ as the human mailbox).

> **Reputation split in one line:** transactional signs `d=auth.merovex.press`,
> marketing signs `d=news.merovex.press`; receivers score them separately, so the
> newsletter can never sink the login email. Config sets and suppression (below)
> keep the newsletter from souring the shared *account* reputation too.

---

## Step 1 — IAM sending identity  ☐
**Goal:** a least-privilege credential the app uses to call SES (nothing else).

1. IAM → **Users** → Create user `inkwell-ses` (no console access, programmatic only).
   The wizard's permissions step has **no inline-policy option** — pick **Attach
   policies directly**, select nothing, and finish.
2. Open the created user → **Permissions** tab → **Add permissions ▾ → Create
   inline policy → JSON** → paste, name it `inkwell-ses-send`, create:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": ["ses:SendEmail", "ses:SendRawEmail"],
       "Resource": "*"
     }]
   }
   ```
   (We can tighten `Resource` to the verified-identity ARNs later, once they exist.)
   Alternatively: IAM → **Policies → Create policy** (same JSON) first, then attach
   it in the wizard — equivalent result.
3. On the user → **Security credentials → Create access key** → **Application
   running outside AWS** → save the **Access key ID** + **Secret**. This is the
   only time the secret is shown.

**Lands in Rails credentials (Phase 1):** `ses.access_key_id`, `ses.secret_access_key`, `ses.region`.
**Verify:** user exists with the inline policy; key pair saved somewhere safe (password manager, not the repo).

## Step 2 — Two domain identities + Easy DKIM  ☐
**Goal:** prove ownership and sign each stream with its **own** DKIM `d=` domain —
this is the reputation firewall between magic-links and the newsletter.

Do this **twice**, once per identity:

**2a. Transactional — `auth.merovex.press`**
1. SES → **Configuration → Identities → Create identity → Domain** → `auth.merovex.press`.
2. Enable **Easy DKIM**, key type **RSA 2048**.
3. Add the **3 CNAME** records SES shows (`<token>._domainkey.auth.merovex.press` → `<token>.dkim.amazonses.com`).

**2b. Marketing — `news.merovex.press`**
1. Same flow → `news.merovex.press`, Easy DKIM RSA 2048, add its **own 3 CNAMEs**.

(Only check "Publish DNS records to Route 53" if Route 53 hosts merovex.press; otherwise add records manually at your DNS host.)

**Verify:** **both** identities show **Verified** + DKIM **Successful** (minutes to a few hours). Don't request production access until both are green.

## Step 3 — Custom MAIL FROM subdomain per identity (SPF alignment)  ☐
**Goal:** SPF passes and *aligns* for DMARC on each stream (return-path lives under
the same brand, not `amazonses.com`).

Do this on **each** identity:

**3a. On `auth.merovex.press`** → MAIL FROM `bounce.auth.merovex.press`
   - **MX**: `bounce.auth.merovex.press` → `feedback-smtp.<region>.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.auth.merovex.press` → `"v=spf1 include:amazonses.com ~all"`

**3b. On `news.merovex.press`** → MAIL FROM `bounce.news.merovex.press`
   - **MX**: `bounce.news.merovex.press` → `feedback-smtp.<region>.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.news.merovex.press` → `"v=spf1 include:amazonses.com ~all"`

Leave the on-failure behaviour as **"Use amazonses.com as fallback"** until each verifies.

**Verify:** MAIL FROM shows **Verified** on both identities.

## Step 4 — DMARC  ☐
**Goal:** publish a DMARC policy (monitor first, tighten later).

Aggregate reports go to `dmarc@merovex.com` (a **different domain** than the
DMARC record), so `merovex.com` must authorize the cross-domain reporting — else
mailbox providers won't send the reports.

1. **DMARC record — on `merovex.press`** (org-level → covers `auth.` and `news.`).
   Cloudflare `merovex.press` zone → TXT, Name `_dmarc`:
   ```
   v=DMARC1; p=none; rua=mailto:dmarc@merovex.com; fo=1
   ```
2. **Cross-domain authorization — on `merovex.com`.** Cloudflare `merovex.com`
   zone → TXT, Name `merovex.press._report._dmarc`
   (→ `merovex.press._report._dmarc.merovex.com`):
   ```
   v=DMARC1;
   ```
   This is `merovex.com` saying "I accept DMARC reports for `merovex.press`."
   Without it the reports silently go nowhere.
3. **Mailbox:** ensure `dmarc@merovex.com` actually receives mail (real mailbox or
   catch-all with working MX on `merovex.com`), or the reports land nowhere.
4. Keep `p=none` through cutover; move to `quarantine`/`reject` only after a week+
   of clean aggregate reports.

**Verify** (Arch: `dig` needs `sudo pacman -S bind`; or use `drill`/`resolvectl`):
```
dig +short TXT _dmarc.merovex.press
dig +short TXT merovex.press._report._dmarc.merovex.com
```
Both should return their `v=DMARC1...` values.

## Step 5 — Open/click tracking domain (marketing only)  ☐
**Goal:** working HTTPS click/open tracking on the newsletter stream. **Default
to SES's own tracking domain** — a **custom branded domain is deferred** because
it needs CloudFront (see below).

**Decision (2026-07-10): use the default SES tracking domain.** SES does **not**
auto-provision a TLS cert for a custom redirect domain, so a bare
`click.news.merovex.press` CNAME → `*.awstrack.me` serves an `awstrack.me` cert
and browsers reject it (`ERR_CERT_COMMON_NAME_INVALID`). The default domain
(`https://<region>.awstrack.me/…`) has a valid cert and full open/click
tracking — just unbranded. On `inkwell-marketing`, leave **Tracking options** on
the **default Amazon SES domain** (no custom redirect domain).

**Branded HTTPS (optional, later):** request an ACM cert for
`click.news.merovex.press` in the region, put a CloudFront distribution in front
(origin = the awstrack endpoint) with that cert, point the CNAME at CloudFront,
then set it as the config set's custom redirect domain.

**Verify:** a sent marketing email's links resolve over HTTPS with no cert
warning.

## Step 6 — Configuration sets (the marketing/transactional split)  ☐
**Goal:** two sets so marketing is tracked and transactional is not.

Config sets aren't hard-bound to an identity — the mailer picks the set **per
message** (Phase 1). The mapping we'll wire:

| Stream | Identity / From | Config set |
|---|---|---|
| Transactional (`SessionMailer`) | `noreply@auth.merovex.press` | `inkwell-transactional` |
| Newsletter confirm/re-engage (`SubscriberMailer`) | `noreply@news.merovex.press` | `inkwell-transactional` — *critical links must not be click-rewritten* |
| Broadcast issues (`PostBroadcastMailer`) | `noreply@news.merovex.press` | `inkwell-marketing` |

**6a. `inkwell-marketing`**
1. Create configuration set `inkwell-marketing`.
2. **Tracking options** → leave on the **default Amazon SES domain** (Step 5 — custom branded domain deferred).
3. **Event destination** → publish to **SNS** (topic from Step 7). Subscribe to:
   **Send, Delivery, Bounce, Complaint, Open, Click, Reject, Rendering Failure**.

> **Where these land (Phase 2, built):** `Webhooks::SesController` translates
> every event into a canonical `DeliveryEvent` ([[0025-canonical-delivery-events]]):
> Permanent bounce → `hard_bounce` (suppresses), `Suppressed`/
> `OnAccountSuppressionList` subtypes → `suppressed` (record-only, see Step 8),
> Transient → `soft_bounce` (suppresses after 3 straight), Complaint →
> `complaint` (suppresses as `complained`), Reject/Rendering Failure →
> `rejected` (record-only — our reputation, not their mailbox). Raw payloads
> are stored for replay; SNS redeliveries dedupe on the SES message id.

**6b. `inkwell-transactional`**
1. Create configuration set `inkwell-transactional`.
2. **No** custom redirect domain.
3. **Event destination** → SNS. Subscribe to **Delivery, Bounce, Complaint,
   Reject, Rendering Failure** — **omit Open and Click**. Because the destination
   doesn't publish open/click, SES **won't inject the pixel or rewrite links** on
   magic-link mail (confirmed behaviour). Bounces/complaints still protect us.

**Verify:** both sets exist; marketing lists Open+Click, transactional does not.

## Step 7 — SNS topic + HTTPS subscription  ☐
**Goal:** SES events reach `POST /webhooks/ses`.

1. SNS → **Create topic** (Standard) e.g. `inkwell-ses-events`. Both config sets in
   Step 6 publish here (one topic is fine; the payload carries the config-set name).
2. **Create subscription** → protocol **HTTPS** → endpoint
   `https://app.kindredquill.com/webhooks/ses` — the **app host**, never a
   tenant domain.

   > ⚠️ **Corrected 2026-09-04.** This said `https://merovex.press/webhooks/ses`,
   > from when merovex.press was the Rails host. Static serving later handed that
   > domain to the edge Worker, which answers only its island allowlist: every SES
   > event drew a `405` and `delivered`/`opened`/`clicked` read zero on every
   > broadcast for months while mail sent normally. The subscription showed
   > **Confirmed** throughout — that flag records the handshake, not delivery.
   > With no DLQ, those events are unrecoverable. Never point platform ingest at
   > an author's domain.
   >
   > Two gotchas when repointing: an SNS subscription's **endpoint is immutable**
   > (create a new one, let it confirm, then delete the old — overlapping is safe,
   > `DeliveryEvent.ingest!` dedupes on `[provider, message id, event]`), and the
   > console's endpoint field rejects pasted URLs carrying invisible characters
   > with a bare "Enter a valid HTTPS endpoint" — retype it by hand.

   **Verify delivery, not just status:** CloudWatch → SNS →
   `NumberOfNotificationsFailed` for the topic should be flat, and a test
   broadcast should move `delivered` within seconds.
3. ⚠️ **Ordering gotcha:** SNS immediately sends a `SubscriptionConfirmation` to
   that URL and stays **PendingConfirmation** until the endpoint confirms it.
   That endpoint is built in **Phase 2**. So either:
   - do Step 7 **after** Phase 2 deploys (cleanest), **or**
   - create it now and confirm later — the controller auto-confirms on first hit,
     or you can paste the `SubscribeURL` from the SNS console into a browser once.

**Verify:** subscription state is **Confirmed** (revisit after Phase 2 if needed).

## Step 8 — Account-level suppression: leave it OFF  ☐
> **Revised 2026-08-05 by [[0025-canonical-delivery-events]]** — this step
> originally said to enable suppression as redundancy. Reversed: the app-side
> `Subscriber` table (ADR 0011) is the **only** suppression list. With the AWS
> net enabled, SES silently drops sends to listed addresses and
> `Subscriber.status` drifts from reality — we believe we sent, nothing went out,
> and no bounce ever comes back to tell us.

1. SES → **Configuration → Suppression list** → account-level suppression
   **disabled** for both reasons (Bounces and Complaints).
2. The app-side net that replaces it (already wired, Phase 2):
   `Webhooks::SesController` maps a `Permanent` bounce with subtype
   `Suppressed`/`OnAccountSuppressionList` to canonical **`suppressed`** —
   record-only, never a hard bounce (the mail was never sent, so it says
   nothing about the mailbox). If one of these ever arrives for a subscriber we
   think is `confirmed`, that's the drift alarm: AWS has a list entry we don't.
   Clear it under **Suppression list → the address → Remove**.

**Verify:** suppression list shows account-level suppression disabled; a re-sent
address that previously bounced in the sandbox gets a real send attempt (and a
real bounce event), not a silent drop.

## Step 9 — Request production access (sandbox exit)  ☐  ⏳ long-lead
**Goal:** leave the sandbox (sandbox = 200/day + only verified recipients).

1. SES → **Account dashboard → Request production access**.
2. In the request describe: transactional magic-links + opt-in double-confirmed
   newsletter; RFC 8058 one-click unsubscribe in every marketing email;
   bounce/complaint handling via SNS (Steps 6–8); consent log (ADR 0011). This
   detail gets faster approval.
3. File this **as early as Steps 2–8 allow** — approval is typically ~24h and
   **gates the whole cutover**.

**Verify:** account shows **Production access: Enabled**; sending quota raised.

---

## Phase 0 done when…
- [ ] **Both** identities (`auth.` + `news.`) **Verified**, DKIM **Successful** (Step 2)
- [ ] MAIL FROM **Verified** on both (Step 3), DMARC published (Step 4)
- [ ] Tracking domain active on `inkwell-marketing` (Step 5)
- [ ] Both configuration sets present with the right event sets (Step 6)
- [ ] SNS topic created; subscription **Confirmed** after Phase 2 (Step 7)
- [ ] Account suppression **off** — app DB is the suppression list (Step 8, per [[0025-canonical-delivery-events]])
- [ ] **Production access enabled** (Step 9)

Then Phase 1 (sending) can flip. Gems for Phase 1 (reference): `aws-sdk-rails ~> 5`
+ `aws-actionmailer-ses ~> 1`; `delivery_method = :ses_v2`, `ses_v2_settings = { region: ... }`.

## Links
Decision: [[0015-email-relay-mailgun-to-ses]] · Consent trail: [[0011-subscribers-and-consent-log]] · Event canon: [[0025-canonical-delivery-events]]
