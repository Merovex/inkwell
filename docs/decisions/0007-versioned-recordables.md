---
type: decision
title: Versioned recordables — event-tagged immutable versions, no events table
status: accepted
tags: [data-model, versioning, delegated-types, history]
created: 2026-07-03
updated: 2026-07-03
sources: [0006-record-recordable-generic-spine.md, Basecamp document history UI (recordings/:id/events, documents/:id/changes/:id)]
---

# 0007. Versioned recordables — event-tagged immutable versions, no events table

## Context
Editing a recordable destroyed its previous content (plain `delegated_type`
usage mutates the row in place). The product requirement: prior versions must
be available — a Basecamp-style change history ("created this document",
"saved a new version", "changed the title from … to …") with tracked-changes
diffs. Basecamp keys those URLs by the *recording* id, revealing that the
envelope is the public identity and content rows are disposable versions.

## Decision
1. **Record is the only public identity.** `/posts/:id` is the Record id; the
   record's `recordable` pointer is the cursor to the current version.
   Superseded versions stay put as history. (Cursor is DB-nullable only for
   the creation transaction; the version's `record_id` is NOT NULL.)
2. **Recordables are immutable, event-tagged versions.** Every version carries
   `record_id`, `creator_id` (who made *this* version) and `event`
   (`created / updated / published / unpublished / pinned / unpinned /
   trashed / restored`). `event` is a display tag for the feed — state is
   always queried off `status`.
3. **The regime rule: drafts mutate, published versions.** `status == drafted`
   → saves amend the current version in place (draft churn is nobody's
   business); `status == published` → every save inserts. Transitions always
   insert — including trash/restore, draft or published. Invariant: **every
   state the world ever saw is permanently recorded**; unpublish→edit→republish
   collapses the interlude into one diff anchored on published versions.
4. **No events table.** History is a column select over the versions
   (`record.versions`); feed lines derive from adjacent-version deltas (event
   tag; `title` compare; `body_id` compare → "saved a new version"). A journal
   table can be layered on later if a cross-type account timeline needs one.
5. **Bodies are shared by reference.** Rich text hangs off a tiny `Body` row;
   versions carry `body_id`. Assigning `content` mints a new Body (so content
   edits version their text); action-only versions share the previous one.
   Files never duplicate — versions share Active Storage blobs.
6. `published_at` stamps on first publish and survives the round trip (feed /
   permalink date only — it is *not* the regime switch; `status` is).

## Consequences
- Spine API: `Record.originate` (birth: row → first version → cursor, one
  transaction), `Record#versions`, `Record#revise` (insert + repoint, in a
  transaction; invalid version leaves the cursor alone), `Record#save_edit`
  (the whole save ladder: requested transition — publish/schedule/unschedule —
  wins and folds the edit in; otherwise the regime branch via
  `Recordable#mutable?`), `Record#trash/restore` (event version + `trashed_at`
  envelope cache for cheap list filtering).
- History pages: `/posts/:id/events` (feed), `/posts/:id/changes/:version_id`
  (word-level tracked-changes diff, `diff-lcs` + in-repo `HtmlDiff`),
  `/posts/:id/versions/:version_id` (frozen render).
- Superseded versions are kept indefinitely; destroyed only when the record is
  destroyed (bodies garbage-collected when their last version goes). A prune
  policy can come later if needed.
- Storage: ~10KB HTML per content version; one embedded photo ≈ hundreds of
  text versions. Non-issue.
- Known accepted quirks: the `created` version holds the draft's final
  pre-publish content; the `unpublished` version's content drifts during
  draft-mode edits (converging to the next published version); collaborative
  drafting is untracked until publish.

## Alternatives considered
- **BC3-style events/journal table** — richer (cross-type timeline) but a
  second table duplicating what version rows already say; deferred until a
  real cross-type feed exists (additive later).
- **`published_at` as the immutability ratchet (no take-back)** — rejected:
  draft churn between unpublish/republish is deliberately untracked; published
  anchors keep the interlude diffable, so nothing is hidden.
- **Serialized snapshots (PaperTrail-style)** — rejected: opaque blobs, fights
  Action Text instead of riding the two-rows-two-rich-texts structure.
- **Copying the rich text on action-only versions** — rejected for the body
  pointer: `body_id` comparison is also what keeps the feed a column select.

## Links
Related: [[0006-record-recordable-generic-spine]] · Supersedes: — · Superseded by: —
