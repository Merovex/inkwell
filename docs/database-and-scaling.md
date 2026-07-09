# Database Choice & Scaling — SQLite vs. MariaDB, and When to Split App Servers

*Research/decision summary for Inkwell. Two linked questions: (1) how far does
SQLite go for an app like this, and (2) when do you add a second app server?
Both hinge less on "number of users" than on **write concurrency, single-machine
limits, and HA**.*

Related: [`multi-tenancy.md`](./multi-tenancy.md).

---

## 1. SQLite: how far does it go?

SQLite is a **single-writer** database — one write transaction at a time
(serialized), unlimited concurrent readers in WAL mode. The ceiling is set by
**write concurrency** and by the fact that the DB file lives on **one machine**.

Inkwell's workload (boards, docs, weekly check-ins, chat, rich text) is
**read-heavy, low-write** — about the friendliest possible profile for SQLite.

**Performance ceiling** (WAL mode, NVMe SSD, Rails 8 tuned defaults):
- **Reads:** effectively a non-issue — in-process, often faster than a
  client-server DB. Millions/day on one box is routine.
- **Writes:** comfortably **a few hundred write-tx/sec**, up to **low thousands**
  with short transactions and good disk.

| Scale | SQLite verdict |
|-------|----------------|
| Small group / self-hosted (≤ dozens) | Ideal. Faster + simpler than a server DB. |
| Hundreds concurrent active / low-thousands total | Fine on one box with WAL + short transactions. |
| ~1,000+ concurrent **writers** / sustained hundreds writes/sec | Tight; needs care (batching, short locks, separate SQLite files per concern — Rails 8 already does this for cache/queue/cable). |
| Need multiple app servers, HA/failover, heavy write contention | Wrong tool — move to MariaDB/Postgres. |

**So on raw performance, one box on SQLite could serve into the low thousands of
concurrent active users** (tens of thousands registered). Higher than most
expect.

### But the operational ceiling hits first
- **Single machine** — the DB file is local; you can't run 2+ app servers
  against one SQLite file over the network without LiteFS/replication.
- **No built-in HA/failover.** Litestream gives streaming backup/restore, not
  seamless failover.
- **Backups/PITR/ops are all on you.**

This mirrors Fizzy's own decision: they abandoned SQLite-per-tenant **for
operational reasons (failover, replication, cross-tenant features)**, not speed.

---

## 2. MariaDB — self-hosted vs. DO Managed

Both remove SQLite's two ceilings (concurrent writers + single machine):
- **DO Managed MySQL/MariaDB** (~$15/mo entry+): DO owns backups, PITR, failover,
  upgrades, patching, standby nodes, metrics. Adds ~0.5–2ms network latency per
  query (negligible here). **Right default for a small team building a SaaS.**
- **Self-hosted MariaDB**: cheaper in dollars, but you own backups, failover,
  tuning, patching, monitoring. Worth it only if you require the control.

---

## 3. When do you split app servers?

App-server capacity is **concurrent req/s vs. CPU**, not user count. Rails is
mostly CPU-bound per request (~50–150ms typical), giving **~15–25 req/s per
vCPU**.

| Single box | ≈ req/s | ≈ concurrent active users | ≈ registered* |
|---|---|---|---|
| 2 vCPU | 30–50 | 300–500 | ~5k–15k |
| 4 vCPU | 60–100 | 600–1,000 | ~10k–30k |
| 8 vCPU | 120–200 | 1,000–2,000 | ~20k–60k |

*Registered ≫ concurrent (typically 1–10% active at once); engagement-dependent.

**You'll split app servers before hitting the capacity wall — usually for these
reasons, in order:**
1. **Redundancy / zero-downtime deploys** — run **≥2 app servers behind a load
   balancer** so one can restart/fail without downtime. For a paid SaaS this is
   often a **day-one** call at ~0 load. *This, not throughput, is the usual first
   trigger.*
2. **Vertical scaling exhausted** — add workers / a bigger box before adding
   boxes; you can go far vertically first.
3. **CPU saturation / request queuing** — the real alarm: **Puma request-queue
   time** climbs at peak and p95 latency rises. Watch it; don't guess.
4. **Background jobs competing** — move Solid Queue workers to their own
   process/box before splitting the web tier.

---

## 4. The linchpin: DB choice and app-server count are coupled

- **On SQLite, "split app servers" is the thing you can't easily do** — the DB
  file is local, so your app-server count is effectively capped at 1 (plus
  vertical scaling).
- **On MariaDB, splitting is trivial** — DB is over the network; add boxes behind
  a load balancer whenever queue time climbs.

So the HA/scale decision *is* the DB decision.

---

## 5. Recommendation for Inkwell

Given Inkwell is heading toward a **multi-tenant, Fizzy-shaped SaaS**:

- **Use DO Managed MariaDB from day one.** The performance question is a red
  herring at this scale; the deciding factors are HA, managed backups, and
  painless horizontal scaling — all of which the managed client-server DB
  unlocks and SQLite blocks.
- **Run ≥2 app servers for HA** once it's a real paying product — for uptime, not
  load. Add the 3rd+ only when Puma queue latency > ~50–100ms at peak or CPU is
  pegged >70–80% sustained. **Scale up first, out second.**
- **SQLite remains the right choice** only if Inkwell ships as **self-hosted,
  single-tenant, per-customer deployments** — then it's genuinely great (Rails 8
  first-class + Litestream for backups) and no capacity wall applies.

### Deciding variables (fold in when known)
1. One shared multi-tenant SaaS, or per-customer self-hosted deployments?
2. Target scale — dozens of groups, hundreds, thousands?

## Sources
- [Behind the Fizzy Infrastructure — 37signals Dev](https://dev.37signals.com/fizzy-infrastructure/) (the SQLite-per-tenant → shared-MySQL pivot)
- Rails 8 SQLite production support (Solid Queue / Solid Cache / Solid Cable), Litestream/LiteFS for durability & replication.
