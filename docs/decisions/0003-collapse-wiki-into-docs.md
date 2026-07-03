---
type: decision
title: Collapse documentation into a single docs/ folder
status: accepted
tags: [process, documentation, meta]
created: 2026-07-01
updated: 2026-07-01
sources: [0001-adopt-work-tracking-wiki.md]
---

# 0003. Collapse documentation into a single docs/ folder

## Context
[[0001-adopt-work-tracking-wiki]] put the work-tracking wiki in its own `wiki/`
folder, separate from the pre-existing `docs/` design/reference docs. In
practice that created **two** documentation folders — cutting against the
original "one place, don't muddy the water" goal and forcing a "which folder?"
decision for every new page.

## Decision
Merge the wiki into `docs/` as the single documentation folder, **keeping the
wiki machinery**: the `CLAUDE.md` maintainer contract, `index.md`, `overview.md`,
`log.md`, `decisions/`, `concepts/`, `entities/`, `summaries/`, `_templates/`,
and `raw/`. The existing design docs stay at the `docs/` root as "reference &
design docs", registered in `index.md`; they gain wiki frontmatter
incrementally, not all at once.

This supersedes [[0001-adopt-work-tracking-wiki]] on the *location* only — the
Karpathy-style pattern, contract, and workflows from 0001 are retained.

## Consequences
- One documentation folder, one index, one contract — no folder-choice friction.
- `docs/CLAUDE.md` is the scoped contract for the whole folder.
- Design docs and process pages coexist; the contract defines two tiers
  (polished reference vs. frontmatter'd wiki pages) so they don't clash.
- Relative links from a subfolder page to a root design doc are `../name.md`.

## Alternatives considered
- **Keep `wiki/` and `docs/` separate** — rejected: two folders for one purpose.
- **Merge into `wiki/` instead of `docs/`** — rejected: `docs/` is the
  conventional name and already held most of the content.

## Links
Related: [[0001-adopt-work-tracking-wiki]] · Supersedes: [[0001-adopt-work-tracking-wiki]] (location) · Superseded by: —
