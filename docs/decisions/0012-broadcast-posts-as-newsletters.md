---
type: decision
title: Newsletters — broadcast a post (HEY World model)
status: accepted
tags: [rails, newsletter, posts, email]
created: 2026-07-09
updated: 2026-07-09
sources: [./0011-subscribers-and-consent-log.md]
---

# 0012. Newsletters — broadcast a post (HEY World model)

## Context
We need to send monthly newsletters to confirmed subscribers ([0011](./0011-subscribers-and-consent-log.md)).
Rather than a separate newsletter content type, we follow **HEY World**: a
published blog post *is* the newsletter. Write once — the post's public page is
the web archive / "view in browser", and it can also be emailed to subscribers.
Scale is small (target ~1000 subscribers, ~monthly).

## Decision
Broadcasting is **an action on a Post**, not a new model — mirroring the existing
publish/pin transitions (`resource :broadcast`, create + destroy). Sending can be
**immediate or scheduled** for a future time, reusing the same deferred-job
mechanism as a post's scheduled publish (`PostBroadcastJob.set(wait_until:)`,
which no-ops if the broadcast was canceled — like `Record::PublishLaterJob`).
`destroy` cancels a scheduled send before it goes out; a *sent* broadcast can't
be undone.

- **`Broadcast`** hangs off the post's **Record** (the stable identity, not a
  version), with a unique `record_id` — so a post is broadcast **exactly once**,
  and the send survives edits. Creating the row *is* the one-time guard.
- **`BroadcastDelivery`** — one row per (broadcast, subscriber), unique. Makes the
  fan-out **idempotent and resumable**: `PostBroadcastJob` skips anyone already
  stamped, so a retried/half-finished job never double-mails.
- Only a **published or scheduled** post can be broadcast (not a draft).
- `PostBroadcastMailer#issue` sends the post body + a "view on the web" link (the
  public blog URL) + the subscriber's unsubscribe token, with a `List-Unsubscribe`
  header (RFC 8058 one-click). From/site-name come from `Setting.current`.
- Admin UI is a **HEY World-style banner** on the post page: the public link (copy
  to share) and an "Email it to my subscribers" button that becomes a "Sent to N
  subscribers" stamp afterward (the share link stays).

## Consequences
- No new content type; posts reuse Lexxy/drafts/publish/history, and the blog page
  is the free archive.
- A newsletter is, by definition, a **public** post — there is no email-only,
  never-public send. (A standalone Newsletter model could be added later if that
  need appears; deliberately not built now.)
- Broadcasting a *scheduled* (not-yet-public) post is supported: the emailed
  "view on the web" link resolves early via a **keyed preview slug**
  (`Record#preview_key` — a 5-char Crockford segment derived from the id by HMAC,
  no stored column), and `blog#show` serves that scheduled post `noindex` until
  it publishes, when the key drops and the keyed link 301s to the clean slug. The
  bare id 404s in the meantime. It's a *timing* gate (the post goes public
  shortly anyway), not security — a short key + the id being enumerable means
  it only deters casual fishing.
- Sending is a sequential in-job fan-out — fine at ~1000/month; would need
  batching if the list grew much larger.
- Delivery still depends on a real relay (SES/Postmark/Resend) + verified sender
  domain — deployment config, not built here.

## Alternatives considered
- **Standalone `Newsletter` content type** — more to build, and it re-poses the
  web-archive question HEY World answers for free. Kept as a future option.
- **`broadcast_at` column on the post/records** — rejected: posts are versioned
  (state belongs on the Record), and a separate table matches how distributors/
  boosts already hang off `records`, while giving us the deliveries log.
