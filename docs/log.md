# Work Log

Append-only. Newest first. Format defined in [[CLAUDE]] (`CLAUDE.md`).

## [2026-07-01] decision | Collapse wiki into docs/
- Merged the `wiki/` machinery into `docs/` as the single documentation folder; kept the CLAUDE.md contract, index, log, decisions, templates, and raw/. Registered the design docs in the index. Retired the `wiki/` folder.
- pages touched: [[0003-collapse-wiki-into-docs]], [[0001-adopt-work-tracking-wiki]], [[index]], [[overview]], [[CLAUDE]]
- refs: docs/

## [2026-07-01] refactor | Reconcile docs to Person / User / Account
- Swept the design docs to the new vocabulary (ADR 0002): rewrote data-model.md, schema.rb, and account-creation-concern.md (renamed from group-creation-concern.md); fixed the Alcovo-facing mapping tables/prose in both Fizzy docs (verbatim Fizzy source left intact). Renamed placeholder "Writer Group" → "Alcovo" throughout.
- pages touched: [[0002-domain-vocabulary-person-user-account]]
- refs: data-model.md, schema.rb, account-creation-concern.md, fizzy-authentication.md, fizzy-user-account-model.md

## [2026-07-01] decision | Domain vocabulary: Person / User / Account
- Chose plain names for the three core models: keep Fizzy's `User`/`Account`, rename `Identity` → `Person`. Retired `Membership`, `Group`, `bucket`.
- pages touched: [[0002-domain-vocabulary-person-user-account]], [[domain-vocabulary]], [[index]], [[overview]]
- refs: data-model.md, fizzy-authentication.md

## [2026-07-01] note | Executive summary of docs research
- Alcovo is a multi-tenant "writer group" app modeled on Basecamp's Fizzy — delegated-type content spine, passwordless identity-centric auth, shared-DB row-level tenancy, Lexxy/Action Text rich text, MariaDB+HA for SaaS. Key open decision: shared multi-tenant SaaS vs. per-customer self-hosted.
- refs: (all reference docs)

## [2026-07-01] decision | Adopt a work-tracking wiki
- Established a Karpathy-style, LLM-maintained work log + knowledge base (initially in `wiki/`; later merged into `docs/` — see [[0003-collapse-wiki-into-docs]]).
- pages touched: [[0001-adopt-work-tracking-wiki]], [[index]], [[overview]]
- refs: CLAUDE.md
