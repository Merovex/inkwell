---
type: concept
title: Bulletins — platform announcements
status: active
tags: [bulletins, platform, notifications, publishable, spine]
created: 2026-08-07
updated: 2026-08-07
sources: [concepts/notifications.md]
---

# Bulletins — platform announcements

Root staff → every user, the Basecamp "bulletin": a title + rich body,
published (or scheduled) once, ringing everyone's bell with **no email**.
Built 2026-08-06.

## Model — a platform record on the spine

`Bulletin` (`../../app/models/bulletin.rb`) is a `Publishable` recordable, so
it inherits the full draft → scheduled → published regime (versioning, the
shared scheduler, `Record::PublishLaterJob`, retention) for one mixin.

Unlike every other record, a Bulletin belongs to **no bucket** — it's the
App's, not any Account's or Circle's. `Record::PLATFORM_TYPES = %w[Bulletin]`
(`../../app/models/record.rb:17`): the `bucket` FK is nullable, and the
`belongs_to :bucket` **default proc decides by type** — platform types get
nil, everything else still defaults to `Current.bucket || Current.account`
and still validates presence. (An explicit `bucket: nil` at create can't beat
a `belongs_to default:` — it fires whenever the association is nil — so the
decision has to live in the default itself.)

## Fan-out — bell only, no email

First publish (either path — the Publish button or `PublishLaterJob` firing)
runs `BulletinAnnounceJob` (`../../app/jobs/bulletin_announce_job.rb`): a
notification for every user **except the author**. `bulletin_published` is
deliberately **not** in `Notification::EMAILED`, so no-email is structural,
not a flag. Idempotent — editing a published bulletin re-commits a version
row but the job dedupes on existing notifications, so it never re-rings. See
[[notifications]].

## Surfaces

- **Authoring** — `/support/bulletins` (`Support::BulletinsController`),
  root-gated like the help desk (bare 404 otherwise). The composer mirrors
  posts: Publishable ladder, shared scheduler, `save_edit`. **Route ordering
  trap**: the tickets `path: "support"` wildcard (`GET /support/:id`) swallows
  `/support/bulletins` as a ticket id — bulletins must be declared first.
- **Reading** — `/bulletins` + `/bulletins/:slug`, any signed-in user (the
  bell links here). Drafts 404 for members, preview for root. Root sees
  "Manage bulletins" / "Edit" affordances on the reader pages.
- **Discovery** — the app menu's platform doors row (Announcements + Support),
  and on the [[circle-wall]] Commons, published bulletins affix atop the feed.

## Ops

Deploy gate is shared with the platform-tenant work: stamped sends need the
From identity associated with the tenant. Bulletins themselves need nothing
beyond a root author.
