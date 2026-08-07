---
type: concept
title: The Wall — a circle's feed, and the Commons
status: active
tags: [circles, wall, commons, turbo, feed, boosts, pulses]
created: 2026-08-07
updated: 2026-08-07
sources: [concepts/circles.md]
---

# The Wall — a circle's feed, and the Commons

A **candidate presentation** of a circle, built 2026-08-06: a Facebook-style
reverse-chronological feed of the circle's content, swappable with the
existing sectioned circle page while it's judged (neither is yet the
default — the ⋯/head toggle flips between them). The **Commons** is a
platform-wide circle everyone belongs to, built to be the Wall's first real
home. See [[circles]] for the underlying membership/pulse/boost machinery.

## The feed

`Circles::WallsController#show` (`../../app/controllers/circles/walls_controller.rb:11`)
merges two record streams into one reverse-chronological page:

- **Messages** — `Message.current_in(circle.records.listed).published`. Only
  published; drafts and scheduled never enter the stream.
- **Beats** (pulse answers) — every answer is its own card, wearing its
  Pulse's **question** as the title.

Both order by `record_id DESC` and share **one cursor**: each item carries an
`anchor` = its own `record_id`, the merged candidates sort by `-anchor`, and
the page is the top `PER_PAGE` (10). The tail is a lazy `turbo_frame` whose
`src` is `?before_id=<last anchor>`; scrolling it into view fetches the next
page, which slots into a frame id matching the request. `target: "_top"` on
the frames lets card links (the thread modal) escape the frame.

Design history (all built + judged live the same day — the swap-in candidate
view earned its keep): day-grouped pulse cards → per-beat cards →
the-Pulse-as-one-card → **per-beat cards, settled**. The Pulse record itself
does not appear in the stream; the pending pin and the beat cards carry it.

## Cards

`_card` (Message) and `_beat_card` (Beat) share the `.wall__card` shape:
byline (`name · Title` inline — the title is a real `<h3>`), the time_ago
receipt on its own line, a 5-line-clamped `.prose` body, and a footer of
**live comment count + boost chips**. Each fragment-caches on
`[version, creator, comment_count, boosts, …]` — every content, comment, or
boost change mints a new key; version rows are immutable, so edits do too.
Menu visibility joins the key as **capabilities** (can_edit / can_trash
booleans), never identity — so a cached card can't leak an author's menu to a
bystander, yet same-role viewers still share one fragment.

## Interactions

- **Thread modal** — a card's title or comment link fetches
  `Circles::Walls::ThreadsController#show` into the wall's `modal` frame (the
  goals-today dialog pattern: the response carries a `<dialog>` that shows
  itself). Serves **both** Messages and Beats (`@subject`, question-as-title).
  Full body + boost strip + comments + a pinned composer.
- **Comments stream in place** — `CommentActions#create` responds with Turbo
  Streams (redirect is the no-JS fallback); `back=wall` returns the stream to
  the modal. One template, id-targeted, so page-thread and modal surfaces
  can't double-insert. Comments work on Beats for free — the spine allows
  comments on any record.
- **Boosts broadcast live** — `Boost` after_create/destroy_commit
  `broadcast_*_to [circle, :wall]`; walls subscribe via
  `turbo_stream_from @circle, :wall`. A boost lands on / leaves every open
  wall's card in real time. Comment counts broadcast the same way
  (`Comment#broadcast_count_to_wall`).
- **Edit-in-modal** (messages) — the card's ⋯ menu Edit fetches the composer
  into the `modal` frame (`Circles::Walls::EditsController`, author-gated);
  save submits the ordinary `messages#update` with `back=wall`. Beats edit on
  the pulse page.

## Affixed strips (first page only)

Above the stream, in order: the **pending-pulse pin** (the one actionable
row — the circle asked, you haven't answered; the account's own `--tint-soft`
color), a "You have N drafts" link, your **scheduled** messages (warning
tint), and on the Commons, the latest **Bulletins** ([[bulletins]], accent).
All per-viewer, rendered outside the card cache. One `.wall__pin` shape,
tone by modifier.

## The Commons

The one platform-wide circle: `circles.commons` boolean with a **partial
unique index** (the singleton is a DB fact). Everyone belongs via real
membership rows — `Circle.provision_commons(owner:)`
(`../../app/models/circle.rb:102`) seats every existing user (idempotent,
`insert_all`), and `User#join_commons` (`../../app/models/user.rb:107`) seats
newcomers at signup. The exceptions are structural: `full?` short-circuits
(no Dunbar cap), the invite policy denies on it (everyone's already in), and
leaving is blocked. Bulletins affix to its wall.

**Ops:** run `Circle.provision_commons(owner: User.root.first)` once in
production (like Tenant Zero).

## Gotchas / open questions

- **`img, svg { display: block }` base reset breaks inline icons** — the
  first inline-flow icon (the beat card's activity glyph in the title) needed
  `.wall__title .lucide { display: inline-block }`. Every other icon lives in
  a flex row and never noticed.
- **`.prose` self-centers** (its own measure + auto margins + padding) — wrong
  inside a card that already *is* the measure; overridden to full-width under
  `.wall`/`.wall-thread` only.
- **Turbo broadcasts inject the model as an implicit partial local** — a
  strict-locals partial rendered by `broadcast_*` must name it (e.g.
  `comment: nil` on `_comment_count`).
- **Avatar URLs in background renders** — broadcasts have no request host, so
  `image_tag …variant` emitted `example.org`; `avatar_content` now uses
  `rails_storage_proxy_path` (path, not URL). Fixes broadcast boost chips AND
  live bell rows.
- Volume: a busy daily pulse puts one card per member per day into the
  stream. If it drowns messages, the lever is collapsing consecutive
  same-day beat cards (deferred).
- The Wall is a **candidate**, not the default. If it graduates, the sectioned
  circle page's Pulse/Discussions previews become redundant.
