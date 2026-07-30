# Static Site Build Pipeline: Rails + Hugo + R2

**Status:** Accepted ([ADR 0021](decisions/0021-hugo-static-site-generator.md)); revised
**Date:** 2026-07-28 (drafted) / 2026-07-29 (accepted) / 2026-07-30 (revised: Docker binary provisioning, design axes §6.1–6.2, purge step reinstated, open questions re-opened)
**Decision:** Rails orchestrates; Hugo renders; R2 serves. Templates live in Hugo themes, not in Rails. Data crosses the boundary as JSON only.

*This doc is the build-pipeline design for Phase 2
([phase-2-static-serving.md](phase-2-static-serving.md)). It supersedes that
plan's ERB-extraction language (§2.1–2.2, amended in place) and its
manifest-last deploy (§2.3–2.4) in favor of the pointer-flip scheme below.
Themes are being pre-built separately (owner-authored, own repo). §11 lists
the deltas against the phase-2 draft and the remaining open calls.*

---

## 1. Summary

Rails is the system of record and the admin surface. When an author publishes, a Solid Queue job serializes that tenant's current records to JSON, invokes Hugo against a pre-baked theme, and syncs the output to a per-account prefix in Cloudflare R2. A Cloudflare Worker serves the result at the author's domain. The public site never touches the Rails server.

The build is a pure function: `f(theme, JSON) -> HTML`. Rails knows nothing about presentation. Hugo knows nothing about the database. The JSON contract between them is the only coupling, and it is versioned.

Target build cost: under one second per site. Even a worst-case storm (every author publishing in the same hour) is a queue backlog measured in minutes on a single VM.

---

## 2. Goals and Non-Goals

**Goals**

- Publish-to-live latency under 60 seconds for a single author.
- Zero reader traffic on the Rails VM.
- Templates fully outside Rails; a designer can modify a theme without touching Ruby.
- Deterministic builds: same JSON + same theme version = byte-identical output.
- One build pipeline serves every tier (Lite author pages through full sites).

**Non-Goals**

- Author-authored custom templates. Go templates are not a sandbox. Themes are pre-baked and versioned by us. If author-supplied templates ever become a requirement, that is a separate design (and a different engine — Liquid).
- Per-request rendering of any public page. Dynamic behavior (subscribe forms, click tracking) is handled by the Worker or by API endpoints, not by rendering.
- Preview environments per draft. v1 previews render the draft JSON through the same pipeline to a private R2 prefix; nothing fancier.

---

## 3. Architecture

```
┌─────────────────────────── VM (Kamal) ───────────────────────────┐
│                                                                  │
│  Rails admin ──▶ publish! ──▶ Solid Queue: SiteBuildJob          │
│                                   │                              │
│                                   ▼                              │
│                    1. Export: records ──▶ JSON + assets          │
│                    2. Render: hugo --source <workspace>          │
│                    3. Sync:   rclone/aws-cli ──▶ R2              │
│                    4. Flip:   pointer.json                       │
│                    5. Purge:  Cloudflare cache API               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
              R2 bucket: sites/<account_slug>/builds/<id>/...
                                    │
                                    ▼
         Cloudflare Worker (serves R2 object for Host header)
                                    │
                                    ▼
                        authorname.com (reader)
```

Components:

| Component | Role | Technology |
|---|---|---|
| Exporter | Serialize tenant records to the JSON contract | Rails (POROs, no gems) |
| Renderer | JSON + theme → static HTML | Hugo (single binary, pinned version) |
| Publisher | Sync output to R2, flip the live pointer, purge cache | rclone (or aws cli, S3 API) |
| Server | Map Host header → R2 prefix, serve objects | Cloudflare Worker + custom hostnames |

---

## 4. The JSON Contract

The contract is the load-bearing interface. It gets a version number (`contract_version`) and a documented schema. Hugo templates read it; Rails writes it; neither side changes it unilaterally.

This is the interface the pre-built themes are written against — a theme and the exporter meet only here.

### 4.1 Files

The exporter writes a Hugo workspace per build:

```
/rails/builds/<account_slug>/<build_id>/    # host: /var/cache/inkwell/builds (bind mount)
├── hugo.toml                  # generated: baseURL, theme, params
├── data/
│   ├── site.json              # identity: name, tagline, contact, socials
│   ├── author.json            # active pen-name persona (versioned record)
│   ├── books.json             # all published books + distributor links
│   ├── series.json            # series + ordered installments
│   └── posts.json             # blog/broadcast posts (rendered HTML bodies)
├── assets/
│   └── images/                # covers, author photo (pulled from storage)
└── themes/
    └── <theme_name>/          # symlink to pinned theme version (read-only)
```

### 4.2 Page generation via content adapters

Hugo content adapters (`content/books/_content.gotmpl` in the theme) read `data/books.json` and materialize one page per book; same for series and posts. Rails emits **no markdown files and no per-page stubs**. Adding a book to the JSON adds a page to the site. This is the property that keeps structural knowledge out of Rails.

Content adapters require **Hugo ≥ 0.126**; the pinned version (§5.2) sits comfortably above that floor, but any future pin change must respect it.

### 4.3 Body content

Post and book-description bodies are exported as sanitized, pre-rendered HTML fragments inside the JSON (`"body_html"`), not as markdown. Rationale: Rails already owns rich-text rendering for the admin preview; rendering once in Ruby guarantees admin preview and published page agree, and it removes any dependency on Hugo's markdown pipeline matching ours.

### 4.4 Example: `books.json` (abridged)

```json
{
  "contract_version": 1,
  "books": [
    {
      "slug": "riders-of-the-long-silence",
      "title": "Riders of the Long Silence",
      "series_slug": "postal-marines",
      "position": 4,
      "cover": "images/riders-cover.jpg",
      "description_html": "<p>...</p>",
      "distributors": [
        { "name": "Amazon", "url": "https://...", "track_id": "d_8FKQ2" }
      ],
      "offers": [
        { "kind": "direct", "checkout_url": "https://..." }
      ]
    }
  ]
}
```

`track_id` matters: distributor links route through the Worker (`/out/d_8FKQ2`) so click counts keep working from a static page. The static site carries the ID; the Worker does the counting and the 302. *(But see §11 — the existing `/buy/:id` proxy may make this scheme redundant.)*

---

## 5. Build Job Design

### 5.1 SiteBuildJob

```ruby
class SiteBuildJob < ApplicationJob
  queue_as :builds
  limits_concurrency to: 1, key: ->(account) { account.id }  # one build per tenant at a time

  def perform(account)
    build = account.site_builds.create!(status: :running)
    workspace = Exporter.new(account).export!(build)          # 1. JSON + assets
    Renderer.new(workspace).render!                            # 2. hugo
    Publisher.new(account, workspace).publish!                 # 3. sync + flip + purge
    build.succeed!
  rescue => e
    build&.fail!(error: e.message)
    raise
  end
end
```

Design points:

- **Coalescing.** Rapid successive publishes should not queue N builds. On enqueue, discard if a build for this account is already pending (`enqueued_at` newer than the triggering change loses nothing — the pending build reads current state at execution time, not enqueue time). The concurrency limit handles the running case.
- **Snapshot semantics.** The exporter reads only records where `published` is true at execution time, via the Record/Recordable current-version query. A build is a snapshot of "published now," which is the correct behavior for coalesced builds.
- **Timeout.** Hugo is killed at 30 seconds. A brochure site that takes 30 seconds to build is a bug, not a workload.

### 5.2 Renderer: how Hugo is executed

Hugo is not a daemon, a service, or a library. It has no runtime state and no
instance. Every build is one short-lived OS process: the worker assembles a
workspace, execs the binary against it, the process writes HTML and exits.
Concurrent builds are simply concurrent processes; Hugo shares nothing between
runs, which is why concurrency control lives in Solid Queue, not in Hugo.

**Binary provisioning.** A single static executable (the *extended* build, in
case a theme uses SCSS), installed **into the Docker image at build time** —
not committed to the repo (50MB binaries bloat git history) and not installed
from apt (Ubuntu's Hugo lags too far behind for content adapters):

```dockerfile
ARG HUGO_VERSION=0.148.2
ARG HUGO_SHA256=a1b2...
RUN curl -sL https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz \
    | tar xz -C /usr/local/bin hugo \
    && echo "${HUGO_SHA256}  /usr/local/bin/hugo" | sha256sum -c -
ENV HUGO_BIN=/usr/local/bin/hugo
```

```ruby
# config/initializers/hugo.rb
HUGO_BIN = ENV.fetch("HUGO_BIN", "/usr/local/bin/hugo")
```

Since Kamal deploys images, the image is the only location guaranteed
identical across the app container, the worker container, and any future
dedicated job host. The version and checksum live in the Dockerfile, so a
Hugo upgrade is a one-line reviewable diff that rebuilds the image; a
mismatch fails the build, never a running container. Fetching at image build
time (not boot time) puts GitHub availability in the correct failure domain:
it can block building a new image, never running the current one. The ENV
default lets dev machines use a Homebrew-installed Hugo. An SSG version bump
changes build output and gets tested like a product change.

**Invocation.** Plain `Open3` exec, no shell interpolation, `nice`d so web
requests always win the scheduler:

```ruby
def render!
  out, err, status = Open3.capture3(
    { "HUGO_ENVIRONMENT" => "production" },
    "nice", "-n", "10",
    HUGO_BIN, "build",
    "--source", workspace.path.to_s,
    "--destination", workspace.output_path.to_s,
    "--quiet", "--minify", "--panicOnWarning",
    chdir: workspace.path.to_s
  )
  raise BuildError, err unless status.success?
end
```

`--panicOnWarning` is load-bearing: template warnings (missing key, nil
access) become hard build failures instead of silently rendering broken
pages, and the failed build never flips the pointer (§5.4). The 30-second
kill is enforced by a `Timeout` wrapper around the wait.

**Configuration.** `hugo.toml` is generated per build from an ERB stub — the
one place Rails writes Hugo-facing config. It carries `baseURL`, the theme
name, disabled page kinds, and the small declared set of presentation params
(accent color, fonts, `contract_version`).

**Isolation and cleanup.** The build runs as the app user against a read-only
theme symlink. The workspace is deleted in an `ensure` on success and
retained on failure for post-mortem.

### 5.3 Process model: where the work actually runs

"Rails calls Hugo" conflates three processes. Keeping them straight is the
answer to the overhead question:

| Process | Role in a publish | Hugo involvement |
|---|---|---|
| Puma (web) | Writes records, enqueues `SiteBuildJob`. Request completes in milliseconds. | None, ever. |
| Solid Queue worker | Picks up the job; performs export → render → sync. | Spawns Hugo as a child process. |
| Hugo | Renders the workspace to HTML, exits. | Is the child process. |

The build is therefore already offloaded from the web tier by construction:
the only thing the author's request pays for is a queue insert. The spawn
itself (fork/exec) costs single-digit milliseconds — noise against a
50–300ms build. There is no Rails runtime inside Hugo; the worker thread
just waits on a child.

The real shared resource is the VM's CPU and disk. Escalation ladder if
monitoring ever shows builds contending with web traffic:

1. **`nice`/`ionice` the child** (already in the invocation above). Free.
2. **Cap worker concurrency** on the `builds` queue (already required for
   per-tenant limits). Free.
3. **Dedicated job host.** Kamal `roles: [job]` on a second small VM, same
   codebase. This is real architecture: the worker needs the database, so it
   forces the SQLite-to-Postgres question. Do not take this step ahead of
   measurement.

A step 4 exists — a standalone build agent (Go/Rust) consuming the queue
directly, taking builds off Rails entirely — and it is deliberately out of
scope: clean, appealing, and premature at brochure-site scale.

### 5.4 Publisher: atomic-enough deploys

R2 has no atomic directory swap. The approach:

1. Sync build output to `sites/<slug>/builds/<build_id>/` (immutable, content-complete).
2. Write `sites/<slug>/pointer.json` containing the live `build_id` (single-object write: atomic).
3. Worker resolves Host → slug, reads pointer (cached ~30s), serves from that build prefix.
4. Purge Cloudflare cache for the hostname.
5. Reaper job deletes build prefixes older than the last 3 (instant rollback = rewrite pointer).

This costs one small read on cache miss and buys atomic cutover, trivial rollback, and no mid-sync readers seeing a half-deployed site.

---

## 6. Theme Management

- Themes live in their own repo, versioned with tags. The deploy vendors specific tags. Theme v1 is being pre-built (owner-authored) against the §4 contract, in parallel with the Rails-side pipeline work.
- Each account references `theme_name` + `theme_version`. A theme upgrade is a migration: bump the version on cohorts, rebuild, spot-check.
- **A theme version change triggers rebuilds** for every account on that theme — this is the one bulk-rebuild scenario, and the queue design (single worker pool, per-tenant concurrency of 1) handles 10K sequential sub-second builds in a few hours without special machinery. If that ever matters, parallelize the pool, not the architecture.
- The `settings` singleton grows a `design` section persisting the account's axis/preset choices (§6.1). Presentation config crosses the boundary inside `site.json`'s `design` block, so a theme exposes a small, declared set of knobs rather than arbitrary customization.

### 6.1 Design axes and the theme manifest

The `inkwell-author` theme is a **permutation engine**, not a fixed design.
Every visual decision is factored into an independent design axis with a
small closed set of values, applied as a `data-*` attribute on `<html>`. All
~127 axis-conditional rules in `site.css` key off those attributes —
`html[data-palette="grimoire"]` swaps CSS custom properties,
`html[data-hero="name"] .fk-hero-art { display: none }` restructures the
hero. JavaScript never touches layout; it only flips attributes. That is
what makes the axes truly independent: any combination composes without
special-casing or per-combination stylesheets.

The seven axes as built:

| Axis | Attribute | Options |
|---|---|---|
| Palette | `data-palette` | nebula, manuscript, mission, pulp, grimoire (5) |
| Book cards | `data-cards` | spread, shelf, grid, dossier, panel (5) |
| Hero | `data-hero` | split, centered, name, scrim, blur, fan, duet (7) |
| Font pairing | `data-font` | 13 Verkilo genre pairings (epic, classical, inscribed, thriller, noir, procedural, romance, commercial, ya-soft, ya-modern, ya-grotesque, gothic, clinical) |
| Portrait shape | `data-avatar` | frame, round, square, organic (4) |
| Portrait side | `data-avatar-side` | left, right (2) |
| Newsletter band | `data-newsletter` | photo, quiet (2) |

5 × 5 × 7 × 13 × 4 × 2 × 2 = **18,200 combinations.** Fonts stay cheap
despite the 13 pairings: one Google Fonts stylesheet declares all 26
families, but browsers download only the faces actually rendered, so unused
pairings cost one CSS request and zero font bytes.

**Presets are derived, not stored.** The five named designs (Nebula,
Bookshelf, Mission, Noir, Grimoire) in the theme's `data/presets.yml` each
pin one value per axis. The preset label is computed by comparing current
attributes against each preset's axes (`matchingPreset()`); no exact match
displays "Custom." Consequence for the contract: the `design` block needs to
carry **only the seven axis values** — persisting a `preset` name would
create a second source of truth that can drift. Rails stores axes; the label
is always derivable.

```json
"design": {
  "palette": "grimoire",
  "cards": "dossier",
  "hero": "scrim",
  "font": "gothic",
  "avatar": "frame",
  "avatar_side": "left",
  "newsletter": "quiet"
}
```

**One source of truth for axis vocabulary.** The canonical `AXES` array
lives in `switcher.js` (key, attribute, option list), and `presets.yml` is
injected into the page as a JSON island so JS and Hugo share preset data.
The Rails exporter needs that same vocabulary for validation — so the theme
must additionally export it as a data file (e.g. `data/axes.yml`) that both
`switcher.js` generation and the exporter's manifest validation read.
Vocabulary defined once, consumed three times (CSS by convention, JS, Rails).

**Manifest validation (required).** CSS attribute selectors fail silently:
an unknown axis value renders the default styling with no warning, so
`--panicOnWarning` cannot catch it — the site ships looking subtly wrong.
The Rails exporter validates the `design` block against `axes.yml` for the
pinned `theme_version` **at export time**; an invalid value fails the build
loudly, per the §7 invariant. Axis vocabulary changes between theme versions
are caught at the same gate as contract-version drift.

**Design changes are the cheapest rebuild.** A design change alters only the
`<html>` attribute string; pages, media, and CSS are unchanged. Same
pipeline, near-instant build, minimal sync delta.

### 6.2 Preview vs reader builds

One theme, two build modes, distinguished by a single exporter flag
(`preview: true` in the generated Hugo config).

The switcher, as built, is a floating gear FAB opening a popover of cycler
buttons — one for the preset plus one per axis. Clicking cycles to the next
option and applies it instantly by flipping the `<html>` attribute; no
reload. Its moving parts, all theme-side: `switcher.js` (canonical `AXES`
array, cycler wiring, FAB open/close with Escape and click-outside), the
`switcher.html` partial (panel markup plus the `presets.yml` JSON island), a
single `fk_prefs` cookie holding all seven axis values (1-year,
`SameSite=Lax`), an inline pre-paint bootstrap in `baseof.html`'s `<head>`
that applies the cookie before first paint (no flash on navigation), and an
`aria-live="polite"` status region announcing each change.

| | Preview build | Reader build |
|---|---|---|
| Switcher (FAB, panel, `switcher.js`, JSON island) | Included | Omitted |
| Pre-paint bootstrap in `baseof.html` | Included | **Omitted** — design is baked into the attributes at build time; the cookie-reading script is dead weight and a flash risk with no payoff. Gate it on the same `preview` param as the switcher partial, since it lives in `baseof.html`, not the switcher partial. |
| `fk_prefs` cookie | Read + written | Never read |
| Design source | Cookie (author experimenting) | `site.json` `design` block seeds the `<html>` attributes |
| Destination | Private prefix / signed URL (Open Question 3) | `sites/<slug>/builds/<id>/` |

**The switcher's save path.** The preview site is static; `fk_prefs`
persists the author's experiment in their browser only. Rails is the system
of record, so the selection must travel back before it exists in any reader
build. Two candidate mechanisms, one to be chosen at implementation:

1. Preview rendered inside the admin (iframe); switcher `postMessage`s the
   seven axis values to the parent, which saves via a normal authenticated
   endpoint. Keeps the preview build fully static, no CORS, no session on
   the preview origin. **Default choice.**
2. Switcher POSTs directly to an authenticated Rails endpoint. Requires CORS
   and a cross-origin session story on a static site. Held in reserve.

Saving updates the `design` section of `settings`, which flows into the next
reader build's `site.json` and seeds the default `<html>` attributes at
build time.

---

## 7. Failure Modes

| Failure | Behavior |
|---|---|
| Hugo build error | Build marked failed with stderr captured; live site untouched (old pointer intact); Honeybadger alert; author sees "publish failed" in admin. |
| R2 sync partial failure | Pointer never flips to an incomplete build; retry syncs the same immutable prefix (idempotent). |
| Purge API failure | Site is correct but stale up to edge TTL; retry purge; non-fatal. |
| Worker cannot read pointer | Serve last cached pointer; alert. |
| Contract drift (theme expects v2, exporter writes v1) | Hugo adapter asserts `contract_version` and fails the build loudly rather than rendering wrong pages. |
| Invalid design axis value (would silently render default styling) | Exporter validates `design` block against the theme's axis manifest (§6.1) and fails at export, before Hugo runs. |

The invariant throughout: **a failed build can never degrade a live site.** The pointer only moves forward to a fully-synced prefix.

---

## 8. Capacity Math (10K accounts)

- Single-site build: export ~100ms (SQLite reads, JSON write) + Hugo ~50–300ms + sync ~1–3s (dominated by R2 round trips; incremental sync of changed files keeps this low) + purge ~200ms. Call it **under 5 seconds wall-clock, under 1 second CPU**.
- Storm case, 500 publishes/hour: trivially inside one worker's capacity.
- Full-fleet rebuild (theme upgrade), 10K sites × 5s: ~14 hours serial, ~2 hours with 8 workers. Acceptable for a deliberate migration; not a daily event.
- Disk: workspaces are ephemeral (deleted on success), builds live in R2, not on the VM.
- The build queue gets its own Solid Queue queue (`builds`) so newsletter fan-out and site builds never starve each other.

---

## 9. Decisions and Alternatives

| Decision | Alternative rejected | Why |
|---|---|---|
| Hugo | ERB extraction of Rails views | See [ADR 0021](decisions/0021-hugo-static-site-generator.md) — the engine decision proper. |
| Hugo | Jekyll | 10–50× build speed; single binary; no Ruby gem env on the build path. Jekyll's Liquid sandbox only matters for author-authored templates, which are a non-goal. |
| Hugo | Zola | Zola has no content-adapter equivalent; Rails would emit per-page stubs, moving structure back into Rails. Tera is nicer than Go templates, but the coupling cost wins. |
| Build on VM | Cloudflare Pages builds | Pages requires git-repo-per-project, ignores POST bodies on deploy hooks, and quotas collapse at multi-tenant scale. Cloudflare is the serving layer only. |
| Pre-rendered HTML bodies in JSON | Markdown in JSON | One renderer (Rails) means admin preview and public page cannot disagree; no sanitizer on the Hugo side. |
| Pointer-flip deploys | Sync-over-live | Atomic cutover, instant rollback, no torn deploys. |
| Pinned Hugo binary | System package | Build output is a product surface; upgrades are deliberate. |

---

## 10. Open Questions

1. **Incremental sync tooling:** rclone `sync --checksum` vs aws-cli against R2's S3 API. Needs a benchmark on a representative site with images.
2. **Worker pointer caching:** 30s TTL vs Durable Object per hostname. Start with TTL; measure.
3. **Preview builds:** private prefix + signed URL, or a `preview.<slug>.inkwell.press` hostname? Leaning signed URL for simplicity.
4. **Image pipeline:** Hugo can resize/convert covers at build time. Doing it in Hugo keeps Rails out of presentation; doing it in Rails (variants) reuses existing storage. Undecided.

---

## 11. Reconciliation with phase-2-static-serving.md

Where this doc and the phase-2 draft diverged, and how each resolves:

- **Cut-over verification (phase-2 §2.6.1).** The byte-level HTML diff against Rails-rendered output dies with ERB — Hugo output is structurally different by construction. Replacement: a **semantic diff** over the full sitemap — extracted text content, link graph, meta tags, feed entries, sitemap coverage. Weaker than a byte diff; still catches missing pages, broken links, and dropped content.
- **Cache strategy.** Phase-2 §2.4 deliberately chose short max-age (60s) on HTML *to avoid purge machinery*; the 07-29 acceptance resolved to keep that (no purge). The 07-30 revision reinstates the per-publish purge step (§5.4), **re-opening this question**: purge-per-publish vs 60s max-age self-healing (worst-case staleness without purge = HTML max-age + pointer TTL, ~90s, inside the two-minute publish-to-live exit criterion). Decide when the Worker is built.
- **Deploy scheme.** This doc's pointer-flip (§5.4) **supersedes** phase-2's `current/` prefix + manifest-last upload (§2.3–2.4, amended). The manifest survives as build metadata (file list + hashes drives incremental sync), but the pointer, not the manifest, is the atomicity mechanism.
- **Worker allowlist.** The canonical dynamic-island list lives in phase-2 §2.5 (newsletter routes, contact, `/buy/:id`, `/webhooks/ses`, `/ahoy/*`, apex slug-path routing) and is unchanged by the engine choice. Open: this doc's `/out/:track_id` Worker-side click counting vs simply keeping the existing `/buy/:id` proxy — the count has to land in Rails either way, so the proxy is likely sufficient; decide when the Worker is built. If `/buy/:id` wins, the JSON carries those URLs and `track_id` is dropped from the contract.
