---
type: decision
title: Public URLs — id-first slugs via Record#to_slug
status: accepted
tags: [rails, routing, public-site]
created: 2026-07-08
updated: 2026-07-08
sources: [../overview.md]
---

# 0010. Public URLs — id-first slugs

## Context
The public Merovex Press site needs shareable, stable permalinks for posts and
books. Admin keeps bare Record-id URLs; the public side wants a human-readable
slug that survives title edits.

## Decision
Public URLs are **id-first**: `/blog/3-my-title`, `/books/3-strand-discovery`,
built by `Record#to_slug` (`"#{id}-#{title.parameterize}"`, degrading to just the
id for titleless records). Lookup uses `Record.find(params[:id])` — Ruby's
`String#to_i` takes the leading integer, so a stale or bare-id slug still
resolves; the controller then 301-redirects to the canonical slug. Admin URLs
stay bare ids (no global `to_param` override).

## Consequences
- Stable permalinks: editing a title doesn't break links (the id is the
  identity; the slug is cosmetic).
- The public id is visible/enumerable — acceptable, since draft protection is the
  `published?`/auth check, not URL obscurity.
- `Record#to_slug` is reusable across public pages.

## Alternatives considered
- **Base-32 token of `published_at`** (`/blog/…-1n4v4r0`) — obfuscation, not
  security (the token decodes to a date already printed on the page), plus extra
  machinery. Rejected.
- **Global `to_param` override** — would change admin URLs and break integer
  `find`s in the scoped finders.

## Links
Related: [[merovex-press-public-site]] · Builds on: [0006](0006-record-recordable-generic-spine.md)
