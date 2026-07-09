---
type: decision
title: Record-level operational data — Distributors + change-log event tags
status: accepted
tags: [rails, record-recordable, active-storage, changelog]
created: 2026-07-08
updated: 2026-07-08
sources: [../overview.md]
---

# 0009. Distributors on the Record; cover & link change-log events

## Context
Books/Series need **buy links** (Amazon, Apple Books, Kobo, …) with a click
counter. Links are operational metadata: added independently of content (a Kobo
edition ships later), and a click counter can't be versioned. Separately, we
want cover and link changes to appear in the book **change log**, which is built
from recordable version rows.

## Decision
- **`Distributor belongs_to :record`** (the stable identity), not the versioned
  Book. Platform is auto-detected from the URL (host patterns → enum, else
  `other`), the URL is stripped of query params, uniqueness is per-record, and
  `clicks` is a mutable counter (for the public redirect later). One generic
  `Admin::DistributorsController` serves books **and** series (keyed by
  `record_id`).
- **Change-log events**: adding/removing a link on a **published** record mints
  an action-only version tagged `link_added` / `link_removed` (drafts churn, so
  skipped). Cover changes already version (via `save_edit`); `version_event_line`
  narrates them from the `depiction_id` delta ("added/replaced/removed the
  cover"). New `Recordable::EVENTS`: `link_added`, `link_removed`.

## Consequences
- Buy links are managed live (Turbo) on the show page; adding one on a published
  book leaves an "added a distributor link" entry in the change log.
- Distributor changes on drafts are silent (no version noise).
- New table: `distributors`; `Record has_many :distributors, dependent: :destroy`.

## Alternatives considered
- **Distributor as a versioned recordable / on the Book version** — a click
  counter can't be versioned; add/remove would spuriously mint content versions.
- **No change-log entry for links** — the user wanted the audit trail.

## Links
Related: [0008](0008-books-series-recordables.md) · Builds on: [0007](0007-versioned-recordables.md)
