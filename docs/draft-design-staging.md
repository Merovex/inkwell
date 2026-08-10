# Draft designs + staging host — status / handoff

Status as of **2026-08-10**. Pivoting away mid-stream; this captures exactly
where things stand so the work can resume cold. Related: [[site-designer]],
[[0022-sitedesigner-design-json-sovereignty]].

## Goal

Let an author redesign their public site, share a **draft** at a staging URL for
a second opinion, and promote to production only when ready. "Save" no longer
publishes — deploys are explicit.

## Decisions locked (in this session)

- **Versioned design**, not a single blob: `site_design_versions` table
  (`drafted` / `published` / `archived`; one drafted + one published per account
  via partial-unique indexes). Replaces `accounts.design`.
- **Save ≠ publish.** Designer Save writes the draft only. Two explicit deploys.
- **Staging host = `preview.kindredquill.com`** (`config.x.cloudflare.preview_host`).
  Serves the DRAFT from a preview build channel, `X-Robots-Tag: noindex`,
  **no token** (drafts aren't secret — owner's call).
- **Preview shows draft design + current PUBLISHED content** (design-only staging).
- **Platform path (`sites.kindredquill.com/<handle>/`) MIRRORS production.**
  Staging is a separate host, so the deferred **#3 redirect** (platform path →
  custom domain when connected) stays possible.

## Done and green (code only — NOTHING committed, per house rule)

Full suite: 741 runs, 0 errors; the one failure is a **pre-existing**
`designer.css:396` oklch violation from commit f4da14a, unrelated to this work.

- **Migration** `db/migrate/20260810123527_create_site_design_versions.rb` —
  creates the table, backfills a published + drafted row per account from
  `accounts.design`, then **drops `accounts.design`**. (Down-migration restores
  from the published row.)
- **Model** `app/models/site_design_version.rb`; `Account` gains
  `draft_design` / `published_design` scopes, `seed_design_versions` on create,
  and `publish_design!(by:)` (archive live → promote draft → fork fresh draft →
  `SiteBuildJob`). Removed the "design change auto-publishes" trigger.
- **Pipeline** — `Publisher` gained `channel: :production|:preview` (preview
  builds land under `sites/<slug>/preview/`); `PreviewBuildJob` builds the draft
  to the preview host; `Exporter` default design now reads `published_design`.
- **Controllers/routes** — `Designers#update` writes the draft;
  `resource :preview_deployment` (deploy draft → staging) and
  `resource :publication` (promote → production), both admin-gated.
- **UI** — designer toolbar: Save, Deploy to preview, View preview link, Publish
  (Stimulus `deployPreview` / `publish` save-then-POST).
- **Worker** `edge/src/index.js` — `preview.kindredquill.com` lane reads the
  preview pointer, serves `noindex`, reuses the trailing-slash redirect.
  Node harness `edge/test/worker.test.mjs` (4 cases, wired to `pnpm test`).
- **Tests** — publish transaction, seeding, both deploy endpoints + gating,
  Save→draft, fresh-install FK cleanup, `site_design_versions` fixture.

Underpinned by the earlier fix — see [[relativeurls-trailing-slash-fix]] (Hugo
`relativeURLs` for path-prefixed sites + the Worker trailing-slash 301).

## NOT done — pick up here

1. **Revert / rollback UI (open, the pivot point).** The model already keeps
   `archived` versions, so rollback is data-ready but has **no UI**. The verbs
   are forward-only (Save → Deploy to preview → Publish); there's no undo.
   Design agreed in principle, semantics unconfirmed:
   - **#1 Roll back production** — republish the previous (`archived`) design.
     Mirror of publish: `DELETE site_publication` (destroy) restores the last
     archived → live, rebuild. **(This is the one most wanted.)**
   - **#2 Fix "Discard changes"** — today it resets the draft to theme
     *defaults*; it should reset to the *live* design ("back to live", not
     "back to blank"). Likely confusing as-is.
   Awaiting: confirm #1 only, or #1 + #2.
2. **Cloudflare infra for `preview.kindredquill.com`** (not code, owner's to run):
   DNS + TLS + Worker binding. Safest = add it as a Worker **Custom Domain**
   (dashboard: Workers & Pages → kindredquill-edge → Domains & Routes → Add
   Custom Domain → `preview.kindredquill.com`; auto-provisions DNS + cert, does
   not touch the `sites` route). Open question raised: routing is
   dashboard-managed, not IaC — consider moving edge hostnames into
   `wrangler.toml` `routes` (must include `sites` too or a deploy orphans it).
3. **Deploys** — `wrangler deploy` (ships the preview-lane Worker code) and the
   Rails deploy (runs the migration: backfill + drops `accounts.design`).

## Resume checklist

- [ ] Confirm revert semantics (#1 / #1+#2), build the revert action(s) + button.
- [ ] Stand up `preview.kindredquill.com` (custom domain) + decide IaC question.
- [ ] Deploy Worker + Rails; verify `curl -sI https://preview.kindredquill.com/`
      and a real draft deploy end to end.
- [ ] Commit (Ben commits his own work — 21 files, see `git status`).
