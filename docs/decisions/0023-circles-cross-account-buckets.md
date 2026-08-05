---
type: decision
title: Circles — cross-account buckets for author community
status: accepted
tags: [circles, tenancy, social, data-model]
created: 2026-08-05
updated: 2026-08-05
sources: [0017-phase-1-tenancy-model.md, 0006-record-recordable-generic-spine.md]
---

# 0023. Circles — cross-account buckets for author community

## Context

Authors on the platform work alone inside their Accounts (sites). The owner
wanted "an area where authors come together": accountability groups for
discussion, check-ins, and progress — independent of any one site. The
Record/Recordable spine ([[0006-record-recordable-generic-spine]]) was already
tenant-agnostic, and Phase-1 tenancy ([[0017-phase-1-tenancy-model]]) scoped
records to an owner object.

## Decision

`Record.bucket` becomes **polymorphic** — the bucket that owns a record is an
`Account` (site content), a `Circle` (community content), or a `User`
(personal content, e.g. Goals). Tenancy is stamped at birth via
`Current.bucket || Current.account` and never changes.

**Circle** is a first-class bucket: cross-account, living on the app host at
`/circles/*` (URLs never carry a site slug). Its content: `Message`
discussions with `Comment` threads, and **Pulse** check-ins (a scheduled
question; answers are `Beat` records). Membership is `CircleMembership`
(owner role + members, hard cap 150); the only door in is a
`CircleInvitation` extended by a member.

**Circles are invite-only as an invariant**, not a setting. There is no
public/private toggle and no lock icon (nothing to distinguish from). The
future relief valve is request-an-invite, not an "open" switch.

## Consequences

- The spine carries three bucket kinds with one authorization vocabulary:
  editing is the author's; moderation belongs to the bucket's owner (circle
  owner / account admin).
- Social features (boosts, @mentions, notifications) compose bucket-agnostic
  helpers over the same records — see [[notifications]] and [[circles]].
- The tenancy guard must accept any bucket-anchored query, and `Current.bucket`
  discipline matters: account namespaces leave it unset and fall back.
- A user's circles are global: leaving/joining is independent of account
  membership, so the circles index is the post-sign-in landing when a user has
  no site.

## Alternatives considered

- **Circles as Accounts with a flag** — collapses two very different privacy
  and URL models into one table; every account query grows a "not a circle"
  clause.
- **A separate forum app/table outside the spine** — loses versioning,
  trash/archive, comments, and boosts for free; duplicates the content model.
- **Owner-chosen public/private toggle** — rejected outright; privacy as an
  invariant keeps the mental model ("a circle is a room you're invited into").

## Links

Related: [[circles]] · [[goals]] · [[0017-phase-1-tenancy-model]] ·
Supersedes: — · Superseded by: —
