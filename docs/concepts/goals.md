---
type: concept
title: Goals & Tallies — personal progress tracking
status: active
tags: [goals, tallies, user-bucket, charts]
created: 2026-08-05
updated: 2026-08-05
sources: [decisions/0023-circles-cross-account-buckets.md]
---

# Goals & Tallies — personal progress tracking

Personal writing goals on the **User bucket** (the third bucket kind — a
user's own records, no Account or Circle involved). `/goals` on the app host.

## Model

- **`Goal`** — title, `unit` (words/hours/pages), `target`, optional `per`
  (day/week/month), and `displays` (a JSON **set**). Two shapes from one
  model: `per` present = a **rate goal** ("500 words a day"); absent = a
  **project goal** ("80,000 words total").
- **`Tally`** — the log entry: `logged_on`, `amount`, and an optional note
  (≤140 chars, "an old tweet"). Mutable (a tally is a fact you correct, not
  a versioned document).
- Rate goals **observe** all of the owner's same-unit tallies
  (`observed_tallies`) — log words anywhere, every words-rate goal sees them.
  Project goals count only their own tallies.

## Display cards

`displays` is a multi-select set (`DISPLAYS = ring pace rolling last30
calendar heatmap`), canonical order enforced (`DISPLAYS & Array(displays)`).
Each selected display renders its own card in one flat shared grid:
**heatmaps first, full-width; small cards flex after**. Every card carries
Today (quick-log modal) + ⋯ menu, and the whole card links to the goal.
Heatmap is GitHub-style (365d + prior years, month/day axes, 3 intensity
levels, fluid cells). Cards tint via `--stat-accent` (vibrant Tailwind-hue
equivalents per house tint, contrast-verified).

Serialization gotcha: Rails' `serialize ... type: Array` coder dumps `[]` as
NULL — the column must be nullable and the reader defends
(`def displays = super || []`).

## Deferred

Deadlines + NaNo-style pace line; circle-goal surfacing (the "Wins" idea was
dropped 2026-08-05). A hidden design-studies gallery
(`goals/_design_studies.html.erb`) is a deliberate KEEP (owner).

## Links

[[0023-circles-cross-account-buckets]] · [[circles]] ·
code: `../../app/models/goal.rb`, `../../app/models/tally.rb`,
`../../app/helpers/goals_helper.rb`, `../../app/views/goals/`
