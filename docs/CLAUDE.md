# docs/ — Alcovo Documentation (Schema & Maintainer Contract)

This is Alcovo's **single documentation folder**, run as a **Karpathy-style LLM
wiki**: a compounding, human-readable, LLM-maintained knowledge base. It holds
**both** the durable reference/design docs **and** the work-tracking machinery
(log, decisions, index) in one place.

When you (an LLM agent) operate inside `docs/`, you act as a **disciplined
maintainer**: you read what exists, update it precisely, keep cross-links and
the index honest, and append to the log. You do not invent structure, and you
do not silently overwrite provenance.

---

## Layout

```
docs/
├── CLAUDE.md          # this file — schema + workflows (the contract)
├── index.md           # catalog of everything in this folder
├── overview.md        # living synthesis: current state of the project
├── log.md             # append-only chronological work log
│
├── *.md               # reference / design docs at the root, e.g.
│                      #   data-model.md, schema.rb, fizzy-authentication.md,
│                      #   fizzy-user-account-model.md, account-creation-concern.md,
│                      #   multi-tenancy.md, database-and-scaling.md,
│                      #   lexxy-and-active-record.md
│
├── decisions/         # ADRs — one file per decision, why we chose X
├── concepts/          # topic/how-it-works pages (synthesized knowledge)
├── entities/          # people, services, systems, models, external deps
├── summaries/         # summaries of raw sources (papers, threads, tickets)
├── _templates/        # copy these when creating a new page
└── raw/               # IMMUTABLE source material (never edit)
    └── assets/        # images, screenshots, downloaded files
```

**Two tiers of page, one folder:**
- **Reference / design docs** (root `*.md`) — polished, standalone research and
  design (often with a Sources section). Registered in `index.md` under
  "Reference & design docs". They may lack the frontmatter below; add it
  incrementally, don't force it.
- **Wiki pages** (`decisions/`, `concepts/`, `entities/`, `summaries/`) — use the
  frontmatter + conventions below.

## Page types & frontmatter

Wiki pages start with YAML frontmatter:

```yaml
---
type: decision | concept | entity | summary
title: Human Readable Title
status: draft | active | superseded | archived   # decisions: proposed|accepted|superseded
tags: [rails, auth, multi-tenancy]
created: 2026-07-01
updated: 2026-07-01
sources: [fizzy-authentication.md, raw/some-thread.md]   # provenance
---
```

- `decisions/` files are **ADRs**, numbered `NNNN-kebab-title.md`
  (e.g. `0001-adopt-work-tracking-wiki.md`). Once `accepted`, treat the body as
  immutable history — to change a decision, add a **new** ADR and set the old
  one's `status: superseded` with a link to the replacement.
- `concepts/`, `entities/`, `summaries/` files are `kebab-title.md` and are
  **living** — update them in place as understanding changes.

## Linking

- Cross-link pages with wiki-links: `[[auth-flow]]` refers to the page whose
  filename slug is `auth-flow`, in any subfolder or the root.
- Relative-path links depend on where the page lives:
  - From a **root** page (index/overview/log or a design doc): sibling design
    doc → `data-model.md`; subfolder page → `concepts/auth-flow.md`; repo code →
    `../app/models/user.rb:42`.
  - From a **subfolder** page (`decisions/`, `concepts/`, …): root design doc →
    `../data-model.md`; repo code → `../../app/models/user.rb:42`.

## Log format

`log.md` is **append-only**. Newest entries at the top. Each entry:

```
## [2026-07-01] <verb> | <short title>
- what changed / what was learned
- pages touched: [[page-a]], [[page-b]]
- refs: ../app/..., PR #, commit sha
```

Verbs: `decision`, `build`, `fix`, `ingest`, `refactor`, `note`, `lint`.
Keep entries terse and factual. The log is the audit trail — parseable with
`grep '^## \[' log.md`.

---

## Workflows

### Ingest (new source or finding)
1. Drop raw material into `raw/` (converted to markdown/text where possible).
2. Read it. Discuss the takeaways with the user.
3. Write/update 1–N pages (`summaries/`, then `concepts/`/`entities/`).
4. Add/refresh cross-links; register new pages in `index.md`.
5. Append a `## [date] ingest | ...` entry to `log.md`.

### Decision
1. Copy `_templates/decision.md` to `decisions/NNNN-title.md` (next number).
2. Fill Context / Decision / Consequences / Alternatives.
3. Set `status: accepted` once the user agrees; register in `index.md`.
4. Append a `## [date] decision | ...` entry to `log.md`.

### Query (answering a question from the docs)
1. Read `index.md` and `overview.md` first.
2. Open the relevant pages; answer **grounded in them** with citations.
3. If the answer produced a durable insight, file it back as a page/log entry.

### Lint (periodic health check — run when asked, or before big handoffs)
Report (don't auto-fix unless told):
- orphan pages (no inbound links) and dangling `[[links]]` (no target file),
- pages missing from `index.md`,
- stale `updated:` dates vs code that has since changed,
- contradictions between pages, and coverage gaps.

---

## Rules

- **Never edit `raw/`.** It is provenance.
- **Never delete history.** Supersede/archive with a status + link instead.
- Keep `index.md` and `overview.md` in sync with reality on every change.
- Prefer linking to code over duplicating it here.
- One concept per page. Split when a page tries to be two things.
- Terse, factual, dated. This is a lab notebook, not marketing.
