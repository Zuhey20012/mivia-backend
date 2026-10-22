# Load-test results

**Measured:** 17–18 October 2026. These are real numbers from runs on the developer laptop. They are not production
figures.

## Machine caveat (read this first)

- **Everything ran on one laptop:** a Windows 11 machine with 12 logical CPUs. That one machine ran:
  - one API process (Node 24, a single event loop, so effectively one CPU core);
  - Postgres 15 in Docker, with 2.8 GB of RAM for all containers;
  - stripe-mock;
  - the load generator itself.
- **These parts competed for the same CPUs.** On Render, the database is a separate machine.
- **A Render Standard instance is not the same as this laptop.** It has 1 CPU and 2 GB, and a single core of it is
  typically slower than one laptop core. So treat these numbers as a ceiling for **one instance**, and compare runs
  with each other rather than with production.
- **The payment provider was stripe-mock, running locally.** Real Stripe adds about 200–400 ms to checkout.
- **The concurrency was modest:** 20 connections and 20-second runs, after a 5-second warm-up. The database was
  seeded with 50 000 orders and 20 000 products (`loadtest/seed-scale.js`).
- **autocannon reports p50, p90, p97.5 and p99.** The **p95 lies between the p90 and p97.5 columns.** The table shows
  both, so nothing is invented.

## How to run

```bash
cd backend
npm run build
# throwaway database on the test container, migrated, then seeded
docker exec malvoya-test-db psql -U postgres -c "CREATE DATABASE malvoya_scale"
DATABASE_URL=postgresql://postgres:test@localhost:56432/malvoya_scale npx prisma migrate deploy
DATABASE_URL=postgresql://postgres:test@localhost:56432/malvoya_scale node loadtest/seed-scale.js
# API on :4565 with the test env, DATABASE_URL pointing at malvoya_scale, REDIS_URL empty, DISABLE_SCHEDULER=true
node loadtest/run.js all --connections 20 --duration 20     # or: browse | search | order | telemetry | sockets
```

The load tests refuse to run against anything that is not local, or against a database whose name does not contain
"scale" or "loadtest".

## Results (shipped code, single instance, no Redis)

| Scenario | What it does | req/s | p50 | p90 | p97.5 | p99 | Errors |
|---|---|---:|---:|---:|---:|---:|---:|
| browse | Store list (with distance), store page, store products, product page, drops feed (mixed) | **172** | 101 ms | 195 ms | 283 ms | 342 ms | 0 |
| search | `q=` text search (60 %), size filter, price sort with deep pages | **50** | 386 ms | 545 ms | 670 ms | 748 ms | 0 |
| search **with the recommended indexes** (`indexes.md` (2)) | Same mix | **128** | 146 ms | 207 ms | 284 ms | 357 ms | 0 |
| quote | `POST /orders/quote` (prices a basket, writes nothing) | **482** | 36 ms | 57 ms | 88 ms | 113 ms | 0 |
| order | `POST /orders` with Idempotency-Key: reserves stock, creates a PaymentIntent on stripe-mock, cancels the customer's previous unpaid checkout | **63** | 298 ms | 405 ms | 487 ms | 843 ms | 0 |
| courier telemetry | `POST /courier/telemetry` (HTTP fallback for location) | **501** | 36 ms | 55 ms | 75 ms | 90 ms | 0 |

**Sockets:**
- 500 customer sockets were opened at the same moment, and **500 connected, with 0 failures.**
- Connection time was 595 ms at p50, 672 ms at p95 and 729 ms at the slowest. All 500 were up within 943 ms.
- Then 100 courier sockets each sent a location every second for 15 seconds (1 400 events). Nothing was dropped and no
  socket disconnected.

## Bottlenecks found and fixed

1. **Store list and store pages: `Intl.DateTimeFormat` created on every call.**
   - Problem: `utils/openingHours.ts#helsinkiClock` was the biggest single cost in the app's own code, at **8.6 % of
     all CPU** in a CPU profile of the browse scenario. It runs once per store per request.
   - Fix: the formatter is now created once.
   - Result: under identical profiling, browse went from **106 to 125 req/s** (+18 %), and the function dropped out of
     the profile.
2. **Product search could not use indexes.** One branch of the OR was on the joined shop name.
   - Fix: the matching shop ids are now looked up first (`storeId IN (…)`).
   - Result: with the trigram indexes, search went from **54 to 128 req/s** and its p50 from **352 to 146 ms** (both
     measured in the same session).
   - The index lines are in `indexes.md` and need a migration by the schema owner.
3. **Checkout ran out of database connections.**
   - Problem: during the order scenario, `/admin/metrics` showed the pool full: 10 of 10 connections in use and
     **7–9 queries waiting**. Each checkout uses two transactions and about 15 statements.
   - With `DB_POOL_MAX=25`, nothing waited. Throughput stayed at about 60 orders/s, because this laptop's CPU (API and
     Postgres together) was the limit.
   - Recommendation: set `DB_POOL_MAX` to 15–20 on production instances. Keep instances × `DB_POOL_MAX` below the
     database's connection limit (`scaling-plan.md`).
4. **Unstable store-list pages.**
   - Problem: when ratings tied, the order changed between requests. Pages could repeat or skip stores, and ETags never
     matched.
   - Fix: an `id` tiebreaker. Repeat requests now get **304 Not Modified**.
5. **The order watchdog scanned the whole Order table every minute** (35–45 ms, and growing with every order).
   - This needs the two indexes in `indexes.md` (1), which brought it to 0.45 ms on the seeded data.
6. **Dispatch read every online courier for every offer.**
   - Fix: it now reads only couriers inside a box around the shop. The exact 7.5 km check and the "everyone" fallback
     are unchanged, and the fallback reads at most 2 000 couriers.
   - This could not be load-tested meaningfully with 300 couriers. It matters at thousands.

## Where the time goes now

The CPU profile was taken after the fixes, with the browse scenario.

| Share of CPU | What |
|---:|---|
| 33 % | Prisma's query engine (building queries and parsing results) |
| 24 % | Node itself (sockets, buffers, JSON) |
| 6 % | Our own code |
| 5 % | Garbage collection |

There is no single hot spot left in the application code. One instance is now limited by CPU in Prisma and in Node.
The way to grow is **more instances** (they now work together with `REDIS_URL`), plus **caching of public GETs**
(Cache-Control and ETag are now sent, so a CDN can absorb browse traffic).

## What one Render Standard instance can roughly take

This is extrapolated, and should be confirmed by repeating these scripts against a Render preview environment.
Assume about half the laptop's per-core throughput:

- roughly 80 browse requests a second;
- roughly 30 checkouts a second (with real Stripe latency added).

A day with 10 000 orders averages under 0.2 orders a second, and its peak is maybe 2–3 orders a second. Checkout
capacity is therefore not the constraint for a long time. Browse and search traffic is the constraint, and caching and
more instances deal with it.
