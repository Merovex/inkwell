# Overview — Alcovo

> Living synthesis of the current state of the project. Update this whenever the
> shape of the work changes. Keep it short — details live in linked pages.

## What this is

Alcovo — a Rails 8.1 application (Ruby 4.0.5, app module `Alcovo`). This `docs/`
folder is the single home for both design/reference docs and the work log; see
[[CLAUDE]] for how it's maintained.

## Current state (2026-07-03)

- Project scaffolded (`Rails init.` — commit `d68544e`).
- Documentation consolidated into `docs/` (see [0003](decisions/0003-collapse-wiki-into-docs.md)); Karpathy-style, LLM-maintained.
- Passwordless auth (magic links), first-run Setup, basic UI/design system shipped.
- **Record/Recordable spine implemented** ([0006](decisions/0006-record-recordable-generic-spine.md)):
  tenant-agnostic `Record` envelope + `Recordable` concern, first recordable
  `Post` (drafted/published, pinning, trash) with full CRUD UI, Action Text +
  Active Storage, **Lexxy** editor. Alcovo's real tools (Chat, Discussions,
  Questions, Wordcounts) still to come on these bones.
- **Version history shipped** ([0007](decisions/0007-versioned-recordables.md)):
  recordables are immutable event-tagged versions behind a record-keyed
  identity (`/posts/:id` = Record id); drafts mutate, published content
  versions on every save; Basecamp-style change feed ("Change Log") +
  tracked-changes diffs at `/posts/:id/events` and
  `/posts/:id/changes/:version_id`. Scheduled publishing added: a `scheduled`
  status/event keeps the post mutable until `Post::PublishLaterJob` publishes
  it at the appointed time (native-popover scheduler panel in the composer).

## Core vocabulary

Canonical names (see [[domain-vocabulary]] / [0002](decisions/0002-domain-vocabulary-person-user-account.md)):
**`Person`** (global login) ──< **`User`** (membership) ──< **`Account`** (tenant).
Retired: `Identity`, `Membership`, `Group`, `bucket`.

## Key references

- [Reference & design docs](index.md#reference--design-docs) — data model, authentication, multi-tenancy, database & scaling, Lexxy/ActiveRecord.
- Schema snapshot: [schema.rb](schema.rb).

## Open threads

- Reconcile [data-model.md](data-model.md) / [schema.rb](schema.rb) with ADRs
  0006/0007 (naming `Record`, versioned recordables, no envelope status or
  account_id, Vault dropped) when Alcovo's real tools land.
- Trash purge job (30-day incineration of `records.trashed_at`, cascading
  versions + bodies).
- Alcovo tenancy: add `Account` + `records.account_id` as a host-app extension
  of the spine; then the ADR 0002 Person/User split (deferred 2026-07-02).
