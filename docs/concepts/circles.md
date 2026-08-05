---
type: concept
title: Circles — author community
status: active
tags: [circles, social, pulses, mentions, boosts]
created: 2026-08-05
updated: 2026-08-05
sources: [decisions/0023-circles-cross-account-buckets.md]
---

# Circles — author community

Invite-only accountability groups for authors, cross-account, on the app host
at `/circles/*`. A `Circle` is a **bucket** on the Record spine
([[0023-circles-cross-account-buckets]]) — its content rides the same
versioning, trash, and comment machinery as site content.

## Membership

- `CircleMembership` (one `owner`, members; `MEMBER_HARD_CAP = 150`).
- **Invite-only is an invariant** — no toggle, no lock icon. The only door is
  a `CircleInvitation`, extendable by any member; the invitee sees a **golden
  invitation card** leading their circles deck (and standing in on the
  all-circles page) until they accept or decline.
- ⋯ menu: **Membership** page (roster, invite form, pending seats — visible to
  all members) and **Leave this circle** (non-owners; the owner hands off or
  deletes, never abandons).
- `Circle#roster` orders owner first; avatar groups (header, cards) read it.

## Content

- **Messages** — the circle's discussions (`Message` records, comment
  threads). The circle home previews recent discussions with an activity line
  ("X comments · time ago" + commenter avatar group).
- **Pulse check-ins** — a `Pulse` (question + Fugit schedule, Eastern wall
  clock) asks its subscribers on cadence: `PulseTickJob` every 30 minutes
  fires due pulses; each ask emails (PulseMailer) and rings the bell
  (`pulse_asked`). Answers are **`Beat`** records — one per member per ask,
  editable in place like a comment. The circle home shows the last three
  answers as cards with ghost slots.

## Social layer (messages, comments, beats)

- **Boosts** — the admin side's boost UI reused bucket-agnostically
  (`BoostsHelper` routes to `Circles::BoostsController` in circles). 12-emoji
  palette; boosting notifies the author (bell-only).
- **@mentions** — two inputs, one result:
  - *Typed tokens*: `@handle` or `@email`, scanned by `Mentions` against
    circle members only (create, edit, publish, and scheduled publish).
  - *Picked from the prompt*: Lexxy's native `<lexxy-prompt trigger="@">`
    lists members (avatar + name); picking attaches the **User as an Action
    Text attachment** (sgid). `User` is `ActionText::Attachable` — partial
    `users/_mention` renders the chip (avatar + name, sage) in the editor,
    in rendered content, and on edit round-trips; plain-text form is
    `@display_name`; content-type pinned to `application/vnd.actiontext.mention`.
  - Either path delivers a `mentioned` notification ([[notifications]]);
    recognized typed tokens render as sage chips too (`mentions_highlighted`),
    so a lit chip is proof the mention landed.
- **Comment replies** — a new comment notifies the thread (parent author +
  prior commenters); mention wins over reply for the same comment.

## CSS gotchas worth remembering

- `lexxy.css` ships **unlayered** rules for `vnd.actiontext.*` attachments
  (1em round img). Unlayered beats every `@layer` rule — counter-rules in
  `mention.css` must also be unlayered (it loads after lexxy).
- The mention chip is a plain **inline** box so its baseline is the name's
  text baseline; a flex chip exports the avatar box's synthesized baseline
  and rides ~4px high.
- Never size `.avatar` with `em` on the avatar element itself — `.avatar`
  derives its font-size *from* `--avatar-size`, so the unit chases its own
  tail. Declare a `rem` on the element (mention.css loads after avatar.css).

## Links

[[0023-circles-cross-account-buckets]] · [[notifications]] · [[goals]] ·
code: `../../app/models/circle.rb`, `../../app/models/mentions.rb`,
`../../app/models/pulse.rb`, `../../app/views/circles/`
