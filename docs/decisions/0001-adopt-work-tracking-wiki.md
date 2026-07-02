---
type: decision
title: Adopt a work-tracking wiki
status: superseded
tags: [process, documentation, meta]
created: 2026-07-01
updated: 2026-07-01
sources: [https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f]
---

# 0001. Adopt a work-tracking wiki

> **Superseded on location by [[0003-collapse-wiki-into-docs]]** — the wiki now
> lives in `docs/`, not a separate `wiki/` folder. The Karpathy-style pattern,
> `CLAUDE.md` contract, and workflows established here still stand.

## Context
We want a durable, compounding record of *how and why* work happens on Alcovo —
decisions, learnings, and the current state of the project — without scattering
it across chat logs, tickets, and memory. Andrej Karpathy's "LLM Wiki" pattern
fits: a folder of human-readable, LLM-maintained markdown that accumulates over
time and can be queried in natural language.

The repo already has a `../docs/` folder for durable design/reference material
(data model, auth, multi-tenancy, etc.). We do not want to muddy that or the
application source.

## Decision
Create a single self-contained `wiki/` folder at the repo root, following the
Karpathy LLM-wiki pattern adapted for **work tracking** (hybrid: work log +
decisions **and** concept/entity knowledge pages). Conventions and agent
workflows are codified in `wiki/CLAUDE.md`, which scopes agent behavior when
operating inside the folder.

## Consequences
- Easier: one place to answer "why did we do X?" and "what's the state of Y?";
  git gives us version history and provenance for free.
- Harder: requires discipline to keep `index.md`, `overview.md`, and `log.md` in
  sync — the `CLAUDE.md` contract and lint workflow exist to enforce this.
- The wiki links to, rather than duplicates, `../docs/` and code.

## Alternatives considered
- **Put it in `../docs/`** — rejected: mixes work-narrative with durable design
  docs and muddies both.
- **Rely on chat/agent memory + tickets** — rejected: not compounding, not
  grep-able, not versioned, easily lost.
- **Full RAG over raw docs** — rejected: heavier, and the wiki's curated pages
  give grounded answers without a retrieval stack.

## Links
Related: [[overview]] · Supersedes: — · Superseded by: [[0003-collapse-wiki-into-docs]] (location only)
