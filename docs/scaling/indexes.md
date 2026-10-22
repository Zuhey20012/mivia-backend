# Database indexes: audit and recommendations

**Status:** recommendations only. The scaling work did not change `backend/prisma/schema.prisma` or the migrations
(another agent owns them). Whoever adds these should create one migration for them, check it with
`npx prisma migrate diff`, and run the e2e suite.

## How this was measured

- **Data.** `backend/loadtest/seed-scale.js` filled a throwaway database (`malvoya_scale`). It has 2 000 customers,
  500 approved shops, 20 000 products (15 000 size options), 300 couriers, 50 000 orders over 90 days (100 001 order
  items, 79 986 payouts) and 3 000 drops. The script refuses to run against anything except a local database whose name
  contains "scale" or "loadtest".
- **Queries.** `backend/loadtest/explain-hot-queries.js` calls the real service functions from `dist/`: the order lists
  for each role, the courier job board, the drops feed, product search, the store list, analytics, the order watchdog
  and payouts due. It records the exact SQL that Prisma sends and prints `EXPLAIN (ANALYZE, BUFFERS)` for each
  statement. Set `SHOW_PLAN_MS=10` to also print the full plan of every slow statement.
- **Machine.** A Windows laptop with Postgres 15 in Docker (2.8 GB RAM for Docker). Timings are noisy and only
  relative comparisons count.
- **Candidate indexes.** Each one was created inside a transaction on the seeded database, the plan was run again, and
  the transaction was rolled back.

## Results per hot path

| Path | Plan today (50k orders / 20k products) | Verdict |
|---|---|---|
| Order list, customer (`userId, createdAt`) | Bitmap index scan, 1–15 ms | OK |
| Order list, store (`storeId, paymentStatus, createdAt`) | Index, 2–24 ms | OK |
| Order list, courier (`courierId, status`) | Index, 1–21 ms | OK |
| Courier job board (unassigned paid orders) | Index `status, paymentStatus, courierId`, under 24 ms | OK |
| Payouts due (`status, releaseAt`) | Index, under 1 ms | OK |
| Store list (`isVerified, rating`) | Index, under 1 ms | OK. An `id` tiebreaker was added so pages are stable when ratings tie |
| Drops feed candidates (`status, publishedAt`) | Index on Drop, but a **seq scan of Product** (hash join for `product.isAvailable`), 20–150 ms | OK at this size. Watch it as the product count grows (see "later") |
| **Watchdog: paid orders waiting for the store** | Walks the **primary key** and discards 49 923 rows, **35–45 ms every minute** | **Add an index (1)** |
| **Watchdog: unpaid checkouts** | Same pattern | **Add an index (1)** |
| **Product search `q=`** | **Seq scan of Product** joined to Store, `ILIKE '%term%'` on 5 columns, 120–360 ms | **Code fixed + indexes (2)** |
| **Product search, count** | Same seq scan, 100–250 ms | Same fix |
| **Email lookups** (sign-in, codes, password reset, Google, email language) | `email ILIKE $1` = **seq scan of User** | **Index (3)**. The language lookup was also fixed in code |
| Analytics, "first order of each customer" | **Seq scan of all orders** (GROUP BY userId), 30–55 ms | Fine for now (admin only). See "later" |
| Analytics, daily series (`deliveredAt`, `paidAt`, `cancelledAt`) | Index | OK |

## Recommended now

### (1) Order watchdog scans

The watchdog runs every minute on one instance. Today its "paid but not answered" and "unpaid checkout" scans read the
whole Order table through the primary key, so their cost grows with every order ever made. With these indexes the scan
took **0.45 ms instead of 45 ms**, measured on the seeded data.

```prisma
model Order {
  // …
  @@index([status, paymentStatus, paidAt])    // watchdog: store reminder / store timeout (status PENDING, paid)
  @@index([status, paymentStatus, createdAt]) // watchdog: unpaid checkouts past CHECKOUT_HOLD_MINUTES
}
```

### (2) Product search (pg_trgm)

`contains` with `mode: "insensitive"` becomes `ILIKE '%term%'`, which an ordinary B-tree index cannot serve. Trigram GIN
indexes can.

The search query also had a join problem. One branch of its OR was on the joined Store row
(`store.name ILIKE …`), which stopped Postgres from combining indexes. **The code is fixed:**
`products.service.ts#searchProducts` now looks up the matching shop ids first and uses `storeId IN (…)`. The results are
the same.

With the fix and the indexes below:

| Search | Before | After |
|---|---|---|
| Rare term, single statement | 170 ms | **1.6 ms** |
| Common term ("wool", 5 400 hits) | 133 ms | **29 ms** |
| Search load test | 54 req/s, p50 352 ms | **128 req/s, p50 146 ms** (`load-test-results.md`) |

The extension must exist first. Create the migration with `npx prisma migrate dev --create-only --name search_trgm`,
then add this line at the top of the generated SQL file:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

pg_trgm is available on Render Postgres. Add these lines to the schema:

```prisma
model Product {
  // …
  @@index([name(ops: raw("gin_trgm_ops"))], type: Gin)
  @@index([description(ops: raw("gin_trgm_ops"))], type: Gin)
  @@index([category(ops: raw("gin_trgm_ops"))], type: Gin)   // drop this one if `category` (text) is replaced by categoryId
  @@index([tags], type: Gin)                                   // tags: { has: term }
}

model Store {
  // …
  @@index([name(ops: raw("gin_trgm_ops"))], type: Gin)
}
```

Notes:
- GIN indexes make product writes slightly slower. That is fine for a catalogue that is read far more often than it is
  written.
- Very short terms (1–2 letters) cannot use trigrams and still scan, so the app should search from three letters.
- At hundreds of thousands of products, move ranking to Postgres full-text search (`tsvector` + GIN, Finnish and
  English configurations) or to a search service. See the scaling plan.

### (3) Case-insensitive email lookups

Every sign-in path compares emails with `mode: "insensitive"`: login, register, one-time codes, password reset, Google
and Apple. At 1 million accounts each of those would be a full scan of User. All code paths already store emails in
lower case, so there are two good options.

- **Index (no code change).** Trigram GIN, which supports `ILIKE` equality:
  ```prisma
  model User {
    // …
    @@index([email(ops: raw("gin_trgm_ops"))], type: Gin)
  }
  ```
- **Better long-term.** First run a one-off data migration that lowercases every email (check for collisions first).
  Then change these lookups to exact `email: value.toLowerCase()`, which uses the existing unique index.

`lib/i18n.ts#localeOfEmail`, which runs for every email sent, now tries the exact lower-case match first, so it no
longer scans. It falls back to the case-insensitive match only for addresses that are not accounts.

## Later (watch, not needed yet)

```prisma
model Courier {
  // Dispatch now reads only couriers inside a box around the shop (services/dispatchService.ts). Add this once
  // thousands of couriers are online at the same time:
  @@index([isApproved, isActive, latitude, longitude])
}

model Order {
  // Analytics "new vs repeat customers" groups all orders by customer. Past ~1M orders, store the customer's first
  // paid order on User instead, or add:
  @@index([userId, paidAt])
}
```

- **Drops feed.** Each request reads up to 1 000 candidate drops, joined to Product. Past roughly 100k products,
  consider keeping `isAvailable` and the shop's `isVerified` on Drop, or caching the candidate list for 30–60 seconds.
- **Search `count(*)`.** Every search page runs a count. At very large catalogues, return "more results" instead of an
  exact total.
- **Plain `findMany` calls without `take`** (checked across `src/`). Only bounded or admin-only lists remain: system
  status, the launch-demand list, data export, and DAC7 (once a year). The admin courier list (`GET /admin/couriers`)
  has no cap. Add `take: 500` and paging when it is next edited. That file was being changed by another agent and was
  left alone.
