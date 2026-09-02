---
type: concept
title: Notifications — bell, digests, stamped copy
status: active
tags: [notifications, email, turbo, solid-queue]
created: 2026-08-05
updated: 2026-08-05
sources: [decisions/0024-notifications-stamped-copy-digests.md]
---

# Notifications — bell, digests, stamped copy

"Something happened that concerns you." One `Notification` row per event,
born ONLY via `Notification.deliver(source, to:, kind:)` — which stamps the
row's own copy (actor, title, URL) at delivery so it outlives its source
([[0024-notifications-stamped-copy-digests]]). Your own actions never notify
you (caller's responsibility).

## Kinds and channels

| kind | fired by | email? |
|------|----------|--------|
| `invited` | CircleInvitation extended | 4-hour digest |
| `invitation_accepted` | invitee accepts | bell only |
| `mentioned` | @mention in circle content (typed or picked) | 4-hour digest |
| `boosted` | boost on your message/comment/answer | bell only |
| `pulse_asked` | pulse schedule fires | bell only (PulseMailer emails) |
| `replied` | new comment on a thread you're in (author + prior commenters; everywhere comments exist, incl. site posts/forum) | **daily** digest |
| `ticket_opened` | help-desk ticket opened | bell only (root staff) |
| `bulletin_published` | a [[bulletins]] first-publishes | bell only (everyone but the author) |

`EMAILED` lists the email-worthy kinds; `EMAILED_DAILY` the calm subset.
Mention beats reply for the same comment (one row, the more specific ring).

Each kind carries a lucide **icon** (`Notification::ICONS`), shown beside the
row (and standing in for the avatar when no human acted — pulse asks,
bulletins). `Notification#icon` falls back to the bell for unknown kinds.
NB icons/avatars in **broadcast-rendered** rows must use path-form URLs
(`rails_storage_proxy_path`) — a background render has no request host.

## Channels

- **Bell (live)** — `after_create_commit` Turbo Stream broadcasts prepend the
  row and light a red dot (ping animation, reduced-motion guarded). The
  flyout (switcher-sibling popover) shows 15; opening marks all read.
  `/notifications` is the 30-day page.
- **Email (batched)** — `NotificationDigestJob(kinds)` rolls up unread,
  unemailed rows per user; reading in-app first cancels the email. Schedules
  (recurring.yml): every 4 hours for the default kinds; daily 8am ET with
  `args: [["replied"]]`. `emailed_at` makes each run idempotent.
- **Prune** — read rows die after 30 days (`NotificationPruneJob`, 4am ET).

## URL stamping

Paths are stamped as strings at delivery: circle content →
`/circles/:slug/...`; site-side comment threads → the account's script-name
mount (`Account#admin_path`, e.g. `/:slug/admin/posts/:id#comment_N`) — both
resolve on the app host where the bell lives.

## Links

[[0024-notifications-stamped-copy-digests]] · [[circles]] ·
code: `../../app/models/notification.rb`, `../../app/models/replies.rb`,
`../../app/jobs/notification_digest_job.rb`, `../../app/views/notifications/`
