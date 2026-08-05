# Kindred Quill Email Architecture

Revised 2026-08-05. Supersedes the prior map, which was built on a
single-tenant reading of the product and got the growth curve, the
economics, and the tenancy model wrong.

---

## What changed from the prior map

**Terminology.** "Press" is retired. An author's publishing account is a
**Site**.

**Circle mail is platform mail.** Circles are author-owned, cross-site,
and never affiliated with a Site. The platform sends on its own behalf.
There is no per-Circle sending identity and no scenario where Circle mail
wears a Site's domain.

**The growth stream inverted.** The prior map said reader bulk grows with
tenants and member mail could ride the transactional identity until
volume justified a split. Backwards. Circles are the onboarding surface
and currently free; Sites are the paid add-on. Member mail therefore
scales with total users while reader bulk scales only with paying Sites.
At 1,000 users, daily digests alone run roughly 30,000 messages a month
and a four-hour cadence pushes toward 180,000. That stream never rides
the verification identity, not even on day one.

**SES is load-bearing, not optional.** The prior map framed SES as
saving trivial money. At $50/year flat for a Site and a median list
around 2,500 subscribers sending 1.5 times a month, bulk costs roughly
$4.50/year on SES and roughly $65/year at Postmark's entry rate. The
price point only exists on SES-class economics for bulk.

**BYOD is not a DKIM problem.** Premium bring-your-own-domain means the
author brings their own ESP and leaves your sending stack entirely. You
sync subscribers out. There is no per-tenant DKIM to build, no per-tenant
warming, no second tenancy model. Every message the platform sends is
platform identity.

**The root already sends.** Magic links go out from
support@kindredquill.com today. This is the highest-stakes stream sitting
on the one identity that can never be replaced. Migration item, not a
decision.

---

## The four streams

Identity splits by **audience**, not by transactional-versus-bulk. Users
and Subscribers are different populations with different consent
histories and different complaint behavior, and mail to one should never
be able to damage mail to the other.

### 1. User transactional — `verify.kindredquill.com`

Magic-link authentication, account-creation confirmation. Low volume,
rare per user, unrecoverable on failure since login *is* an email link.
Recipients are known Users.

**ESP: Postmark.** Premium placement is worth paying for on the one
stream that cannot fail, and volume is small enough that the cost is
noise.

### 2. User bulk — `notify.kindredquill.com`

Circle at-mention alerts, periodic activity digests, Pulse prompts.
Highest volume in the system, sent to a free tier, and the single most
likely stream to catch a reflexive spam click. Recipients are known
Users who opted into a Circle, which is not the same as opting into six
emails a day.

**ESP: SES.** Not for cost — $216/year at worst case against $50k of
revenue is nothing. For isolation. This stream will take complaint
damage eventually, and it should take that damage somewhere that cannot
touch magic links and cannot get an account suspended by a strictly
policed transactional provider.

**Design note:** the four-hour cadence is the largest single lever on
this stream. Digest-on-activity rather than digest-on-schedule, with a
per-user frequency preference, likely cuts volume and complaints
together.

### 3. Subscriber mail — `news.kindredquill.com`

Double opt-in confirmations, the three-email onboarding sequence,
Site broadcasts. Everything addressed to a Subscriber rather than a User.

Confirmations belong here, not on the verification identity, even though
they feel transactional. They go to unproven addresses — typos, bots,
dead mailboxes — which makes them the highest bounce-risk mail in the
system. That risk belongs with the list it is acquiring for, not next to
authentication.

**ESP: SES.** This is where the flat price point lives or dies.

### 4. Human — `support@kindredquill.com`

Inbound support and replies only, after the migration. No automated
sending.

---

## Domain plan

| Name | Role | Sends |
|---|---|---|
| `kindredquill.com` | Root, brand, link target | No. Inbound only for support@ |
| `verify.kindredquill.com` | User transactional | Postmark |
| `notify.kindredquill.com` | User bulk | SES |
| `news.kindredquill.com` | Subscriber mail | SES |
| `sites.kindredquill.com` | Custom-domain alias target | No |

Root posture: keep MX for inbound support, publish SPF `-all`, and sit at
DMARC `p=reject`. For a product whose login is an email link, a silent
root at reject is real anti-phishing value, and it protects the link
reputation that every message points back to.

Each sending subdomain gets its own DKIM key, its own SPF, and its own
DMARC record starting at `p=quarantine` and moving to `p=reject` once
aligned. Three identities, three DNS record sets, created together.

---

## Economics

Sending, at scale, is not the expensive part.

| Stream | Volume at 1,000 users | SES | Postmark |
|---|---|---|---|
| User transactional | ~5k/mo | ~$0.50 | ~$15 |
| User bulk (Circles) | 50k–180k/mo | $5–18 | $50–300 |
| Subscriber (200 paid Sites) | ~750k/mo | ~$75 | $400–750 |

Against $50k of Circles revenue and $10k of Site revenue at those
assumptions, total sending cost lands near $100/month. There is no paid
user floor to hit. The margin is roughly 10:1 in your favor on bulk.

**List verification is the real cost.** Per-address rates run about
$0.008 at ZeroBounce, a cent at Kickbox's entry tier, $0.003–0.006 at
Emailable, and as low as $0.00045 at DeBounce. At half a cent, cleaning
a 2,500-address list costs $12.50 — nearly three times what it costs to
mail that list for a year. A 12,000-address import exceeds the entire
annual subscription.

Verification is therefore a per-address cost that cannot be absorbed into
a flat price. It is priced or it is refused.

---

## Import policy

**Position:** import is a paid cleansing service, quoted before it runs.

The author uploads, the system counts, and the platform returns a price
before processing a single address. Passthrough of the vendor rate, or
passthrough plus a margin, but visible and per-address either way.

Two things to get right:

**Framing.** "We remove the barnacles from your list" is the correct
pitch. It sells the outcome the author wants — mail that lands — rather
than a tax on joining.

**Placement.** A bill at upload is friction at the worst possible moment,
before the author has seen the product work. Consider crediting the
cleansing fee against the first year, or waiving it under some threshold,
so the invoice lands as a benefit rather than a toll.

**Verification is not consent.** Cleansing catches deliverability;
re-confirmation catches permission. An imported list that verifies clean
can still generate complaints from people who never opted in. If import
ships, both gates are needed.

---

## Decisions closed

- **Terminology.** Site, never press.
- **Circle mail is platform-sent.** No per-Circle identity, ever.
- **BYOD means bring your own ESP.** No per-tenant DKIM. Premium tier
  exports subscribers to the author's provider.
- **merovex.press is patient zero.** It migrates onto platform identities
  as tenant one rather than surviving as a special case. This is what
  forces every single-author assumption out of the code, including the
  hardcoded display name, before a paying customer finds them.
- **Root never sends.** Migration required, since it currently does.
- **Identity granularity.** Three sending subdomains on day one, not two.
- **ESP split.** Postmark for user transactional, SES for both bulk
  streams. SES goes live before the first paying Site, not "when volume
  justifies."
- **Substrate unchanged.** Canonical DeliveryEvent pipeline, dedupe,
  raw-payload replay, per-send provider stamping, complained status,
  soft-bounce thresholds. The database remains the authoritative
  suppression list; SES auto-suppression stays off.

## Decisions open

- **The reputation firewall.** All Site broadcasts sign with one bulk
  identity, so one author's bad list degrades every author's placement.
  No policy exists yet for what happens at 8% bounce or 0.5% complaints.
  Because this is unresolved, do not commit to a permanent single bulk
  identity — keep the option to shard authors across several sending
  subdomains so a bad list poisons a cohort rather than the platform.
- **Import policy specifics.** Whether import ships at launch, which
  vendor, what margin, and whether the fee is credited back.
- **Circles pricing.** Free, $20/year, or $50/year. Affects nothing in
  the sending architecture; affects whether the largest mail stream has
  revenue attached to it.
- **Digest cadence.** Four-hour versus daily versus activity-triggered.
  The single largest input to volume and complaint rate.
- **Paid subscriber model.** Authors selling paid content on a Site
  introduces a fourth audience with different consent and different
  stakes. Unexamined.

---

## Migration sequence

1. Create the three sending identities and their DNS records.
2. Move magic links off support@ to `verify.kindredquill.com`. Lock the
   root: SPF `-all`, DMARC `p=reject`, inbound only.
3. Replace the hardcoded display name with a per-tenant value.
4. Migrate merovex.press onto platform identities as tenant one.
5. Postmark console hygiene: one production server with streams, spares
   become staging or get deleted.
6. Bring SES live for both bulk streams before the first paying Site.
7. Revisit the firewall before the second paying Site, and certainly
   before import ships.

None of this is a one-way door. The substrate was built provider-agnostic,
so every choice above is configuration rather than code.
