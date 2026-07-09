---
type: decision
title: Books & Series — versioned recordables, shared-owner cover, Record-keyed join
status: accepted
tags: [rails, record-recordable, versioning, active-storage]
created: 2026-07-08
updated: 2026-07-08
sources: [../overview.md]
---

# 0008. Books & Series — versioned recordables, shared-owner cover, Record-keyed join

## Context
The catalog needs Books and Series. Both carry a title + rich body and publish
like posts, so they ride the versioned-recordable spine (0006/0007). Two things
don't fit the plain spine:

1. A Book has a **cover image** (Active Storage). Attachments key to a row id,
   so `build_successor`'s `dup` — which only copies columns — drops the cover on
   every new version.
2. A Series **has many books, ordered per series**, and a book can live in
   **multiple** series. `records.parent_id`/`position` (a single parent) can't
   express many-to-many.

## Decision
- **Book** and **Series** are `Publishable` recordables (drafts→publish +
  history), added to `Record::RECORDABLE_TYPES`.
- **Cover via a `Depiction` model** that owns the Active Storage image; Book
  holds a scalar `depiction_id`. This mirrors `Body`: `dup` carries an unchanged
  cover forward by id, and a real cover change mints a new `Depiction` — so the
  cover **versions in lockstep with the text** (`Depictionable` concern).
- **Series↔Book via an `Installment` join** between two **Records** (not version
  rows), carrying `position`. Keying on the stable Record id means memberships
  survive versioning; a book can appear in many series, each ordered
  independently.

## Consequences
- Covers get real per-version history (see [0009](0009-distributors-and-changelog-events.md)).
- Membership add/remove/reorder is immediate and independent of the book's
  content edit (managed on the show page via a typeahead + drag-sort), because
  the join lives on the Record.
- `Series#books` / `Book#series` resolve through the join; a standalone book is
  simply zero installments.
- New tables: `books`, `series`, `depictions`, `installments`.

## Alternatives considered
- **Attach the cover to the `Record`** — one cover per identity, but not
  versioned (changing it wouldn't create history). Rejected; we wanted history.
- **`records.parent_id` for membership** — single parent only; no many-to-many
  or per-series ordering.
- **Books not versioned (mutable)** — simpler attachments, but loses the
  draft/publish + history consistency with Post/Message.

## Links
Related: [[merovex-press-public-site]] · Builds on: [0006](0006-record-recordable-generic-spine.md), [0007](0007-versioned-recordables.md)
