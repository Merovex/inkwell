# Overview — Alcovo

> Living synthesis of the current state of the project. Update this whenever the
> shape of the work changes. Keep it short — details live in linked pages.

## What this is

Alcovo — a Rails 8.1 application (Ruby 4.0.5, app module `Alcovo`). This `docs/`
folder is the single home for both design/reference docs and the work log; see
[[CLAUDE]] for how it's maintained.

## Current state (2026-07-01)

- Project scaffolded (`Rails init.` — commit `d68544e`).
- Documentation consolidated into `docs/` (see [0003](decisions/0003-collapse-wiki-into-docs.md)); Karpathy-style, LLM-maintained.
- Still in pre-implementation research; design captured in the reference docs (modeled on Basecamp's Fizzy).

## Core vocabulary

Canonical names (see [[domain-vocabulary]] / [0002](decisions/0002-domain-vocabulary-person-user-account.md)):
**`Person`** (global login) ──< **`User`** (membership) ──< **`Account`** (tenant).
Retired: `Identity`, `Membership`, `Group`, `bucket`.

## Key references

- [Reference & design docs](index.md#reference--design-docs) — data model, authentication, multi-tenancy, database & scaling, Lexxy/ActiveRecord.
- Schema snapshot: [schema.rb](schema.rb).

## Open threads

_Nothing tracked yet. Add active workstreams here as they start._
