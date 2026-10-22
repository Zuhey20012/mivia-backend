# Malvoya scaling plan

*Written for the owner. Last updated 22 October 2026.*

## The short version

- **Today:** Malvoya runs on one Render server (the "API") and one Postgres database. That is the right setup for
  launch, and it costs almost nothing.
- **The code is now ready to grow** without being rewritten. Every extra component is **optional** and is switched on
  by adding one setting (an "environment variable") on Render. If you add nothing, everything keeps working exactly as
  it does today, at today's cost.
- **As orders grow, you add things in this order:**
  1. a bigger database plan;
  2. a second API server plus Redis;
  3. error alerts (Sentry);
  4. a free CDN;
  5. a separate background worker;
  6. then bigger plans and database read copies.
- **When to consider leaving Render:** probably above roughly 100 000 orders a day, or when Render's largest database
  plan is no longer enough. See the last section.

## What was built

All of this is in `backend/`. **Bold** settings cost money only because they need a paid service.

| Setting (env var) | What it switches on | Without it |
|---|---|---|
| **`REDIS_URL`** | Several API servers working as one. Live updates (sockets) reach a phone connected to any server. Rate limits count across servers. A password reset or ban signs the person out on every server at once. Retry protection (`Idempotency-Key`) is shared. Background jobs survive restarts. | One server, as today: everything kept in memory |
| `REDIS_PREFIX` | Lets two environments share one Redis | `malvoya:` |
| `DB_POOL_MAX` | Database connections per server | 10 |
| `DB_STATEMENT_TIMEOUT_MS` | A runaway database query is stopped after this time | 30 000 (30 s); 0 = off |
| `DB_IDLE_IN_TX_TIMEOUT_MS`, `DB_IDLE_TIMEOUT_MS`, `DB_CONNECTION_TIMEOUT_MS` | Connection housekeeping | 60 s / 30 s / 10 s |
| **`SENTRY_DSN`** | Error alerts with stack traces. Emails, phone numbers, tokens and codes are removed before anything is sent. | Errors are only in the logs |
| `SENTRY_ENVIRONMENT`, `SENTRY_TRACES_SAMPLE_RATE` | Labels and optional performance tracing | `production`, 0 |
| `METRICS_TOKEN` | Lets a monitoring tool read `/api/v1/admin/metrics` (admins can always read it) | Admins only |
| `LATENCY_LOG_INTERVAL_MS` | How often the logs get a "slowest routes" summary (p50/p95/p99 per route) | 5 minutes |
| `WORKER_MODE=api` + **a worker service** | The web servers only answer requests. A separate `node dist/worker.js` sends pushes and emails, runs imports, and runs the timed jobs (watchdog, payouts, reminders). Needs `REDIS_URL`. | The API does it all, as today |
| `QUEUE_CONCURRENCY` | Jobs a worker runs at once | 5 |
| `IDEMPOTENCY_TTL_SECONDS`, `IDEMPOTENCY_MEMORY_MAX` | How long a first answer is kept for retries | 24 h, 10 000 entries |
| `SHUTDOWN_TIMEOUT_MS` | Time given to finish requests during a deploy | 25 s |
| `PUBLIC_CACHE_SECONDS`, `PUBLIC_STALE_SECONDS` | How long phones and a CDN may reuse public pages (shops, products, drops, legal pages) | 30 s, 120 s |

Always on, at no cost:
- **Health checks:** `/health` and `/health/ready`. The second checks the database, and Redis when it is configured.
- **Request ids:** every request carries an `X-Request-Id`, which you can look up in the logs.
- **Performance summary in the logs** every 5 minutes.
- **Admin metrics page** at `/api/v1/admin/metrics`, showing:
  - how busy the server is (event-loop lag) and its memory;
  - database connection use;
  - requests per second and error rates;
  - connected phones.
- **Clean shutdown on deploys:** no request is cut off.
- **Compression and caching:** responses are compressed (br or gzip), and public pages carry ETag and Cache-Control
  headers.
- **Retry protection** (`Idempotency-Key`) on:
  - checkout;
  - pickup handover;
  - cancellations and refunds;
  - agreement acceptance;
  - payout triggers.

  Every Stripe "create" call has its own idempotency key too, so a retry never charges, refunds or pays twice.
- **Retries with backoff** for pushes and emails, and a dead-letter log for jobs that fail every time.
- **Image URLs** come out with `f_auto,q_auto`, so phones get the best format and quality.

The tests are in `backend/test/e2e/scale.e2e.js`. They run with and without Redis, including two servers sharing
Redis.

## The stages

"Orders a day" is the main yardstick. Browse traffic grows with it.

| Stage | Switch on | Render API | Worker | Postgres | Redis | Sentry | CDN |
|---|---|---|---|---|---|---|---|
| **Launch** (under ~100/day) | Nothing new. Optionally `SENTRY_DSN` on the free plan | 1 × Standard (1 CPU, 2 GB) | — | 1 GB plan, 7-day PITR | — | Free (5k errors) | — |
| **1k/day** | `REDIS_URL`, second API instance, `DB_POOL_MAX=15`, `SENTRY_DSN`, the indexes in `indexes.md` | 2 × Standard | — | 1 CPU / 4 GB | 256 MB | Team | Cloudflare Free in front of the API |
| **10k/day** | Autoscaling (2–6 instances), the worker with `WORKER_MODE=api`, Postgres high availability | 2–6 × Standard | 1 × Standard | 2 CPU / 8 GB + HA standby | 1 GB | Team + extra events | Cloudflare Free or Pro |
| **100k/day** | Bigger instances, a read replica for analytics/DAC7/reports, PgBouncer (Render's connection pooler) | 4–12 × Pro (2 CPU, 4 GB) | 2 × Pro | 8 CPU / 32 GB + HA + 1 read replica | 5 GB | Business | Cloudflare Pro/Business |
| **1M+/day** | Plan the move described in the last section | 20–60 large instances | Several | At or past Render's largest plans | Cluster | Business/Enterprise | Business/Enterprise |

Things to check at each stage:

- **Database connections.** Instances × `DB_POOL_MAX` (plus the worker's) must stay under the database's connection
  limit: 100 on small plans, 200–500 on larger ones. Past that, use PgBouncer. Behind PgBouncer in "transaction" mode:
  - set `DB_STATEMENT_TIMEOUT_MS=0`;
  - put the timeout on the database user instead:
    `ALTER ROLE <user> SET statement_timeout = '30s'; ALTER ROLE <user> SET idle_in_transaction_session_timeout = '60s';`

  PgBouncer refuses those settings when they are sent at connect time. The app uses no named prepared statements or
  session locks, so transaction pooling is safe.
- **Search.** At about 100k products, move product search to Postgres full-text search, or to a search service
  (Meilisearch or Typesense), as described in `indexes.md`.
- **Read replica.** Point the admin's heavy reports at it (analytics, DAC7, statements) when they start to slow the main
  database. That is a small code change at that stage. DAC7 and statement generation are read-only queries, so they move
  easily.
- **CDN.** Put Cloudflare in front of `api.malvoya.<domain>`, and keep the default "respect origin headers". Public GETs
  are cacheable for 30 seconds. Signed-in requests are marked `private`, so a CDN never shares them.

## Monthly cost estimate per stage (USD)

Prices were taken from the providers' pages on **22 October 2026**:
- Render: <https://render.com/pricing.md>
- Sentry: <https://sentry.io/pricing/>
- Cloudflare: <https://www.cloudflare.com/plans/network-cdn.md>

Render changed its plans on 1 August 2026. The Pro workspace is now a $25/month flat fee with 25 GB of bandwidth, then
$0.15/GB ([summary](https://jwatte.com/blog/render-com-platform-review.md), 15 Jul / 6 Aug 2026). All amounts exclude
VAT. Photos and videos are served by Cloudinary (billed separately) and are not in these numbers.

Render list prices used:

| Item | Price |
|---|---|
| Web or worker instance, Starter (0.5 CPU, 512 MB) | $7 |
| Web or worker instance, Standard (1 CPU, 2 GB) | $25 |
| Web or worker instance, Pro (2 CPU, 4 GB) | $85 |
| Web or worker instance, 4 CPU / 8 GB | $175 |
| Postgres 256 MB | $6 |
| Postgres 1 GB | $19 |
| Postgres 1 CPU / 4 GB | $55 |
| Postgres 2 CPU / 8 GB | $100 |
| Postgres 8 CPU / 32 GB | $400 |
| Postgres 16 CPU / 64 GB | $800 |
| Postgres storage | $0.30/GB |
| Key Value (Redis) 256 MB | $10 |
| Key Value (Redis) 1 GB | $20 |
| Key Value (Redis) 5 GB | $100 |
| Workspace: Hobby | $0 (5 GB bandwidth) |
| Workspace: Pro | $25 (25 GB bandwidth) |
| Workspace: Scale | $499 (1 TB bandwidth) |

High availability and read replicas each run another database instance of the same size, so assume each costs the same
again (check in the dashboard before switching on).

Sentry and Cloudflare list prices used:

| Item | Price |
|---|---|
| Sentry Developer | Free (5k errors) |
| Sentry Team | $29 a month ($26 billed annually), 50k errors |
| Sentry Business | $89 a month ($80 billed annually) |
| Cloudflare Free | $0 |
| Cloudflare Pro | $25 a month ($20 billed annually) |
| Cloudflare Business | $250 a month ($200 billed annually) |

**Launch** (about $72, or $13 at the bare minimum)

| Item | Cost |
|---|---:|
| API, Standard | $25 |
| Postgres 1 GB + 10 GB storage | $19 + $3 |
| Workspace Pro (for 7-day point-in-time recovery; Hobby keeps 3 days) | $25 |
| Sentry Developer | $0 |
| **Total** | **≈ $72** |

The bare minimum is today's Starter API ($7) + 256 MB Postgres ($6) + Hobby workspace ($0) ≈ $13. That works, but has
3-day recovery and little headroom.

**1k orders/day** (about $185)

| Item | Cost |
|---|---:|
| 2 × Standard API | $50 |
| Postgres 1 CPU / 4 GB + 20 GB | $55 + $6 |
| Redis 256 MB | $10 |
| Sentry Team | $29 |
| Workspace Pro | $25 |
| Bandwidth (~100 GB of API JSON) | ~$11 |
| Cloudflare Free | $0 |
| **Total** | **≈ $185** |

**10k orders/day** (about $480–590)

| Item | Cost |
|---|---:|
| 2–6 × Standard API (autoscaling, about 3 on average) | ~$75 |
| Worker, Standard | $25 |
| Postgres 2 CPU / 8 GB + 50 GB | $100 + $15 |
| High-availability standby | ~$100 |
| Redis 1 GB | $20 |
| Sentry Team + extra events | ~$80 |
| Workspace Pro | $25 |
| Bandwidth (~400 GB) | ~$56 |
| Cloudflare Pro (optional) | $0–25 |
| **Total** | **≈ $480–590** |

**100k orders/day** (about $3 900–4 600)

| Item | Cost |
|---|---:|
| 4–12 × Pro API (about 8 on average) | ~$680 |
| 2 × Pro workers | $170 |
| Postgres 8 CPU / 32 GB + 300 GB | $400 + $90 |
| High-availability standby | ~$400 |
| Read replica | ~$400 |
| Redis 5 GB | $100 |
| Sentry Business + events | ~$300 |
| Workspace Scale (1 TB included, then ~2 TB more at $0.15/GB) | $499 + ~$300 |
| Cloudflare Business | $250 |
| **Total** | **≈ $3 900–4 600** |

At this stage, Render's "Enterprise" or a committed-spend deal is worth asking about.

**1M+ orders/day** (about $25 000–60 000)

| Item | Cost |
|---|---:|
| Largest Render databases (16+ CPU) with standby and replicas | $3 200 – $11 000+ |
| Tens of large API instances | $5 000 – 20 000 |
| Bandwidth in the tens of TB | $3 000 – 10 000 |
| Sentry/Cloudflare enterprise contracts | — |
| **Total** | **roughly $25 000–60 000** |

At this volume, a bigger cloud with committed discounts is usually cheaper and more flexible. See the last section.

These figures are estimates for planning, not quotes. Check the live price pages before buying.

## Backups and restore

**What Render does for you.** Paid Render Postgres plans have **point-in-time recovery (PITR)**. Render docs:
<https://render.com/docs/postgresql-backups> (read 22 Oct 2026).

- **Retention:** you can restore to any moment in the last **7 days** on a Pro (or higher) workspace, or **3 days** on
  Hobby. Free databases have no recovery.
- **A restore never overwrites the live database.** It creates a **new** database as it was at the chosen time. You
  check it, then point the API at it.
- **Earliest restore point:** you cannot restore to the last 10 minutes.
- **Exports:** you can also create a logical export (download) on the database's **Recovery** page. Render keeps exports
  for 7 days.

**What you should add:**

1. **Upgrade to a Pro workspace before real customers arrive**, for 7 days instead of 3.
2. **A monthly off-Render copy.** Download an export (or run `pg_dump`) and store it encrypted somewhere else in the EU.
   The Accounting Act requires order records to be kept for years, and 7 days of PITR does not cover that.
3. **Practise a restore once a quarter** (checklist below).

### Restore drill checklist (about 30 minutes, every quarter)

1. [ ] In Render → `malvoya-db-eu` → **Recovery** → **Point-in-Time Recovery** → **Restore Database**.
2. [ ] Name it `malvoya-db-drill-<date>`, pick a time about one hour ago, and keep **Copy Existing Settings** ticked.
   Click **Start Recovery**.
3. [ ] Wait for the status to go from *Recovery In Progress* to *Creating* to *Available*. Note how long it took.
4. [ ] Open its **Info** page, copy the PSQL command, and check:
   - `SELECT count(*), max("createdAt") FROM "Order";` — the latest order should be close to the chosen time;
   - `SELECT count(*) FROM "User";`
   - `SELECT max("processedAt") FROM "StripeEvent";`
5. [ ] Optional full check: create a **preview** or temporary web service from the same code, set its `DATABASE_URL` to
   the drill database, and open `/health/ready`. It should say `"database":"up"`.
6. [ ] **Delete** the drill database (it costs money while it exists). Never point the live API at a drill copy.
7. [ ] Write down the date, the restore time and any problems in `docs/ops-log.md`.

### For a real restore

1. Pause the damage first: set `MAINTENANCE_MESSAGE` so the apps show a maintenance screen.
2. Do steps 1–4 above, choosing the moment just before the problem.
3. Change `DATABASE_URL` on the API (and the worker) to the new database, and redeploy.
4. Check `/health/ready` and place a test order.
5. Remove `MAINTENANCE_MESSAGE`.
6. Stripe payments made after the restore point are still at Stripe. Its dashboard lists the payments and refunds made
   in the gap, and webhooks can be re-sent from the Stripe dashboard so the orders come back.

## Incident runbook

**Where to look first**
- Render → service → **Logs**. Search for the `X-Request-Id` a user or the admin panel shows, or for `"level":50`
  (errors).
- **Metrics:** `GET /api/v1/admin/metrics` as an admin. It shows:
  - event-loop lag (above 100 ms means the server is overloaded);
  - `db.pool.waiting` (above 0 for long means the database connections are used up);
  - the 5xx error rate;
  - the slowest routes.
- Sentry (if switched on): new issues, with request ids.
- **Health:** `/health` (is the process up) and `/health/ready` (database and Redis).

**What to do, by symptom**

1. **API down or `/health` failing.**
   - Look in Render → Events for a failed deploy, and roll back to the previous deploy.
   - If the database is down (`/health/ready` says `"database":"down"`), check the Render status page and the
     database's own dashboard.
2. **Slow, but up** (lag over 100 ms, latencies rising).
   - Add an instance, or raise the autoscaling maximum. This is safe with `REDIS_URL` set.
   - If `db.pool.waiting` stays above 0, raise `DB_POOL_MAX` (within the connection limit) or the database plan.
   - Check the "Latency summary" log lines for the slowest route.
3. **Errors after a deploy** (5xx rate up). Roll back first, then look at Sentry or the logs.
4. **Redis down** (`/health/ready` says `"redis":"down"`).
   - The API keeps serving, and rate limits fail open.
   - Live updates between servers and the job queue pause until Redis is back. Jobs that cannot be queued run on the
     server that made them.
   - If it lasts, scale down to one instance and remove `REDIS_URL` (this is today's mode).
5. **Payments: a customer paid, but the order says unpaid.** Stripe dashboard → Developers → Webhooks → re-send the
   event. Each event is processed only once, so re-sending is safe.
6. **Pushes or emails not arriving.**
   - Look for `"Job failed on every attempt (dead letter)"` in the logs.
   - With Redis, `/admin/metrics` → `queue.deadLetters` counts them.
   - Check `FIREBASE_SERVICE_ACCOUNT` and `SMTP_*`.
7. **A bad actor or a traffic spike.** The per-IP limits apply on every instance (shared with Redis). Cloudflare can
   block countries, IPs or bots in its dashboard.
8. **Data was deleted or broken by mistake.** Follow "For a real restore" above.

**Afterwards:** write a short note (what happened, when, the impact, the fix, what to change) in `docs/ops-log.md`.

## When moving to a bigger cloud makes sense

Render is simple and EU-hosted (Frankfurt). Stay while it is comfortable. Consider AWS, Google Cloud or Azure, in
their EU regions (for example eu-north-1 Stockholm, europe-north1 Finland or Frankfurt), when **two or more** of these
are true:

- **The database:** you need more than Render's largest Postgres plans, more than a couple of read replicas, or
  cross-region failover.
- **The bill:** monthly spend passes about **$10 000–20 000**. Committed-use discounts (30–60 %) and managed services
  such as Aurora or Cloud SQL then usually beat list prices.
- **Infrastructure needs:** you need things Render doesn't offer:
  - private links to partners;
  - your own Kubernetes;
  - many regions with low latency (expansion beyond the Nordics);
  - compliance certifications that customers or banks ask for.
- **Growth rate:** traffic regularly needs more than about 50 web instances.

The code is ready for such a move, and there is no Render-specific code. It needs:

- Postgres;
- Redis-compatible storage (ElastiCache or Memorystore);
- a container or Node host;
- the same env vars.

The move is mostly infrastructure work: copy the database with a final short downtime, then switch DNS.
Before that point, a move would cost more in engineering time than it saves.

## render.yaml blueprint (optional worker and Redis)

`docs/scaling/render.scale.example.yaml` is a documented sketch with:

- the API on two instances (or autoscaling);
- a Render Key Value (Redis) instance;
- the optional `node dist/worker.js` background worker, all in Frankfurt.

It is **not applied**. Copy the relevant parts into the root `render.yaml` when you reach the 1k/day stage, or create
the same services by hand in the dashboard. The essentials are:

```yaml
- type: keyvalue
  name: malvoya-redis
  region: frankfurt
  plan: starter            # 256 MB, $10/month
  maxmemoryPolicy: noeviction
  ipAllowList: []
- type: worker
  name: malvoya-worker
  region: frankfurt
  plan: standard           # $25/month
  rootDir: backend
  buildCommand: npm ci --include=dev && npx prisma generate && npm run build
  startCommand: node dist/worker.js
  # same env vars as the API, plus REDIS_URL from malvoya-redis
# and on the web service: REDIS_URL (from malvoya-redis), WORKER_MODE=api, DB_POOL_MAX=15
```

## Owner checklist

- [ ] **Check that `REDIS_URL` is *not* set on the live Render service** unless you have created a Redis. The code now
      uses it. The local `backend/.env` contains an old `REDIS_URL=redis://127.0.0.1:6379`; remove it, or run a local
      Redis, before using `npm run dev`.
- [ ] Before launch, move to a Pro workspace (7-day recovery), and take the database and API off the smallest plans.
- [ ] Ask the developer who owns the database schema to add the indexes in `docs/scaling/indexes.md`.
- [ ] Optional: create a free Sentry account (EU data region) and set `SENTRY_DSN`.
- [ ] Do the first restore drill, and put a quarterly reminder in the calendar.
