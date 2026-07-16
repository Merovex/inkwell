---
type: concept
title: Public image handling — cover variants, fragment caches, web-vs-email formats
status: active
tags: [active-storage, images, caching, email, public-site]
created: 2026-07-13
updated: 2026-07-13
sources: []
---

# Public image handling — cover variants, fragment caches, web-vs-email formats

## Summary
Every image on the public site is an Active Storage **variant** served in
**proxy mode** (`config.active_storage.resolve_model_to_route =
:rails_storage_proxy`, see [`../../config/application.rb`](../../config/application.rb)) —
the app streams the bytes at a signed `/rails/active_storage/representations/proxy/…`
URL with long-lived immutable cache headers. Two concerns bite here: (1) the
signed variant URL is **baked into fragment caches**, so changing a variant
definition can strand every cached page on dead URLs; and (2) the same Action
Text image partial renders on the **website and in newsletter emails**, which
need different formats.

## Covers — WebP variant + fragment-cache versioning
Book/Series covers live on a [Depiction](../../app/models/depiction.rb) with a
`:cover` variant (`resize_to_limit: [480, 720], format: :webp`) and a `:thumb`.
The public library/detail pages render each cover **inside a fragment cache**:
`cache [cover_fragment_version, series, books]`
([`../../app/views/books/index.html.erb`](../../app/views/books/index.html.erb),
[`show`](../../app/views/books/show.html.erb)).

**The gotcha (root cause of the "covers all disappeared" incident, 2026-07-13):**
the cache store is **Solid Cache** — DB-backed, so fragments survive deploys.
A fragment's key is `template_digest + collection_key(records)`. When the cover
variant definition changed (Jul 11: `[600,900]` JPG → `[480,720]` WebP), it
touched only a **model**, which changes neither the template digest nor any
Book/Series `updated_at`. So the fragments were **never invalidated** and kept
serving HTML pointing at the old JPG variant URLs, which no longer resolve —
covers appeared broken for everyone (server-side cache, so incognito too).
Uploading any cover bumped a record in the cached collection, changed the
collection key, regenerated that fragment with live WebP URLs, and "all covers
reappeared" — the upload busted the stale cache, it didn't fix the images.

**The fix:** a manual version token, `ApplicationHelper#cover_fragment_version`
(`"covers-v2"`), is mixed into every cover fragment key.
**Bump it whenever the cover variant definition changes** so stale fragments
drop. After the incident the poisoned cache was cleared in prod with
`bin/kamal app exec --reuse "bin/rails runner 'Rails.cache.clear'"` (bumping the
token clears it on the next deploy regardless).

**Rule of thumb:** any signed variant URL rendered *inside* a fragment cache
must have a version token you bump when the variant changes — records don't
self-invalidate on a variant-definition change.

## Action Text attachments — WebP on web, JPEG in email
In-body images (post/book/message/drip bodies) render through the shared
partial [`../../app/views/active_storage/blobs/_blob.html.erb`](../../app/views/active_storage/blobs/_blob.html.erb),
which calls `ApplicationHelper#attachment_variation(blob, in_gallery:)`. That
partial renders on **both** the website (e.g. `blog/show`) and inside newsletter
mailers (`post_broadcast_mailer/issue`, `drop_mailer/step`) — and **WebP doesn't
render in Outlook desktop**, so the two contexts need different formats:

| Uploaded format | Web | Email |
|---|---|---|
| PNG / JPEG / GIF | → **WebP** | original (already email-safe) |
| WebP / AVIF | original (already modern) | → **JPEG** (Outlook-safe) |

Context is a per-request flag, `Current.web_images`
([`../../app/models/current.rb`](../../app/models/current.rb)), set by a
`before_action` in [`ApplicationController`](../../app/controllers/application_controller.rb).
**Web requests set it; mailers have no request, so they default to `false`
(email-safe).** This inversion is deliberate: a missed context degrades to a
larger original-format image, never a broken email image. Originals are always
preserved; non-representable files (SVG, PDFs) are untouched.

Posts are **not** exposed to the cover fragment-cache gotcha: `blog/index`
caches only text (no variant URLs) and `blog/show` renders the body uncached.

## Gotchas / open questions
- `preprocessed: true` only builds a variant for **newly attached** images, not
  retroactively — after a variant-definition change, existing images generate
  the new variant lazily on first request (works in proxy mode, but the first
  visitor pays the cost). No backfill task exists yet.
- `preprocessed: true` is **deprecated in Rails 9** (use `process: :later`) —
  flagged by the test suite; not yet migrated.
- The web/email split assumes only mailers render Action Text without a request.
  If a background job ever renders body HTML for the web, it must set
  `Current.web_images` itself.
