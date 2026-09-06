---
type: decision
title: Fan mail — reader replies go to the author's own inbox, not into Inkwell
status: accepted
tags: [newsletter, email, subscribers, privacy, deliverability]
created: 2026-09-06
updated: 2026-09-06
sources: [./0011-subscribers-and-consent-log.md, ./0015-email-relay-mailgun-to-ses.md]
---

# 0029. Fan mail — reader replies go to the author's own inbox

## Context

Readers have no way to respond to a post. The mental model we want is HEY
World's: an author emails a post, a reader replies, and a conversation happens —
one thread per reader, anchored to the post that prompted it. Subscribers exist
(ADR 0011), broadcasts and drips already reach them, and the SES inbound stack
(receipt rule → S3 → SNS → the `:ses` ingress, `SupportMailbox`) is already
running for `support@kindredquill.com`.

Three ways to deliver it were considered, in increasing order of ambition:

1. **Reply-To only.** Outbound mail carries the author's own address; replies
   land in their inbox, entirely off-system.
2. **A tokened link into Inkwell.** The email carries a link to a write-only
   page; the reply is stored as fan mail and the author answers from the admin.
3. **Inbound email.** Readers hit Reply; the message routes back into the thread
   through ActionMailbox, and the author replies from Inkwell — a mini mail app.

Sizing, given how much already exists: (2) is roughly 4–5 focused days, (3) is
6–8, and (3) is only ~2–3 days more than (2) because the receiving stack is
built and `SupportMailbox` has already solved the traps (multipart bodies, size
caps, never ingesting our own identities, no autoresponder/backscatter).

Volume does not force the question. At 1,000 confirmed subscribers and a 40%
open rate, replies run about 1 per send with no explicit ask and about 8 per
send when the email asks for one — between a dozen and ~400 a year depending on
cadence and whether we ask. A personal inbox does not strain until roughly
5,000 subscribers at weekly cadence with an ask.

## Decision

**Ship (1). Reader replies go to the author's own email system.**

- The account's address is used as `Reply-To` on **author-voice mail**:
  broadcast posts, drip drops, magnet delivery, and the re-engagement nudge.
  All of those reach a confirmed human who opted in.
- It is **removed from confirmation mail** — the subscriber double-opt-in
  confirmation and the contact-form confirmation. Those go to unverified
  addresses: typos, bot signups, spam traps, and strangers. Nothing that has not
  proven itself a real reader should hold the author's address.
- The address is **never published on the site**. The one place the theme
  rendered it (the newsletter section's `mailto:` fallback) points at the
  newsletter island instead, and the field leaves `site.json` — a contract
  change, so `CONTRACT_VERSION` and the theme's pin both move to 3. The public
  route for strangers is the existing contact form, which has its own double
  opt-in guard and admin inbox.
- The field keeps the name `contact_email` and its "Contact email" label; the
  hint under it now says what it actually is. Renaming the column was
  considered and declined as churn.
- **Open:** `Page::Starter` interpolates the address into the generated privacy
  and terms copy, with `"the contact form on this site"` as an existing
  fallback. Merovex Press is unaffected — its legal pages are hand-written and
  name no address — so this only bites the next author who generates starters.
  Whether to drop the address there, or publish it behind Cloudflare's email
  obfuscation, is undecided.
- Authors are advised to use a **dedicated alias** rather than a primary
  address. `Reply-To` rides in the headers of every message sent, so it is
  harvestable from any forward or compromised mailbox — far less exposed than a
  `mailto:` on a public page, but not private.

Fan mail therefore lives in the author's mail client, which is better at
threading, search and archiving than anything we would build this year.

## Consequences

- Nothing is recorded in Inkwell: no thread, no link between a reply and the
  post or issue that prompted it, nothing on the subscriber's card, and no
  answer to "which posts provoke replies".
- The reply address is per account, so this scales across tenants without any
  DNS work at onboarding — each author points it at their own inbox.
- ActionMailbox, `SupportMailbox` and the SES receipt rule are **untouched**.
  This decision is additive; the inbound pipe stays wired for the future.
- The trigger to revisit is not volume. It is (a) wanting the record, (b) a
  second person answering fan mail, or (c) **another author on the platform**
  who cannot be told "check your own inbox". (c) is expected to arrive first.

## The design we are not building yet

Preserved so it need not be re-derived:

- **FanMail** is the thread; **Comment** — the existing recordable — is each
  message in it. Comment already fits: `mutable? = false`, rich text on the
  version, and its wall broadcast is already guarded to Circle buckets, so a
  comment parented elsewhere no-ops.
- The thread is a Recordable in Account space, with `Record#parent` pointing at
  the post's Record, and the `BroadcastDelivery` recorded as provenance — which
  issue this reader was answering.
- `records.creator_id` would become **polymorphic** so a Subscriber can author a
  comment. Cheap: 87 rows in production, and while there are 72 references to
  `.creator`, none call `creator.name` directly — they funnel through
  `avatar_content` and `byline`.
- A note to self is simply a comment that was never sent.
- If inbound (3) is ever built, replies must route through **one platform
  receiving domain** (`fanmail+<key>@reply.…`), not per-author domains: SES only
  receives for verified identities, receipt rules are a limited account-wide
  resource, and asking every author to add MX to a domain that may already run
  their real mail is the thing that would kill adoption. The routing key must be
  a stored random string, not a signed token — email local parts cap at 64
  characters.
- Quote stripping has no general solution. Store the raw message, display a
  best-effort stripped version, and collapse the rest behind a disclosure —
  which is what HEY itself does.
- (3) would make Inkwell a **processor of every author's reader correspondence**.
  That, rather than the engineering, is the decision to weigh: retention,
  per-account purge, and a defensible posture in the terms.

## Alternatives considered

- **(2) tokened link into Inkwell** — rejected for now. It teaches every
  author's readers a new behaviour on every device, and its write-only page is
  the piece that gets thrown away once inbound exists. Going 1 → 3 is likely
  cheaper than 1 → 2 → 3.
- **(3) inbound email** — rejected for now on product maturity, not cost. Six to
  eight days is affordable; being a processor of other people's reader mail
  before a single customer has asked for it is not.
- **Per-author receiving domains** — rejected. MX on a customer's domain risks
  breaking their real mail, and receipt-rule limits cap onboarding.
- **Keeping `Reply-To` on confirmation mail** — rejected. It hands the author's
  address to every unverified opt-in attempt, which is the population most
  likely to be hostile.
