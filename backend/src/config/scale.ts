import { env } from "./env";

/**
 * Settings for running at scale. Every paid component is OPTIONAL and switched on only by its env var, so a single
 * Render instance with one Postgres (today's setup) keeps working exactly as before with none of them set.
 * See docs/scaling/scaling-plan.md for when to switch each one on.
 */

function int(name: string, fallback: number, min = 0, max = Number.MAX_SAFE_INTEGER) {
  const raw = process.env[name];
  const v = Number(raw);
  return raw !== undefined && raw !== "" && Number.isInteger(v) && v >= min && v <= max ? v : fallback;
}

function num(name: string, fallback: number, min: number, max: number) {
  const raw = process.env[name];
  const v = Number(raw);
  return raw !== undefined && raw !== "" && Number.isFinite(v) && v >= min && v <= max ? v : fallback;
}

/** "inline" (default): this process serves HTTP and also runs background jobs and the scheduler.
 *  "api": this process only serves HTTP and enqueues work; a separate `node dist/worker.js` runs the jobs and the
 *  scheduler. Needs REDIS_URL (without it the queue is in-process, so "api" falls back to "inline"). */
const rawWorkerMode = (process.env.WORKER_MODE || "inline").trim().toLowerCase();

export const scale = {
  // ── Redis (optional): shared rate limits, socket rooms across instances, session revocation, idempotency, queue
  redisUrl: env.redisUrl,
  redisPrefix: (process.env.REDIS_PREFIX || "malvoya:").trim(),

  // ── Postgres connection pool (per instance; keep instances × DB_POOL_MAX below the database's connection limit)
  db: {
    poolMax: int("DB_POOL_MAX", 10, 1, 500),
    // Any single SQL statement running longer than this is cancelled by Postgres (0 = no limit). Set 0 behind
    // PgBouncer in transaction mode and put the timeout on the database role instead (docs/scaling/scaling-plan.md).
    statementTimeoutMs: int("DB_STATEMENT_TIMEOUT_MS", 30_000, 0, 3_600_000),
    // A transaction left open and idle this long is ended by Postgres (protects the pool from leaks; 0 = off)
    idleInTransactionTimeoutMs: int("DB_IDLE_IN_TX_TIMEOUT_MS", 60_000, 0, 3_600_000),
    // Idle pooled connections are closed after this
    idleTimeoutMs: int("DB_IDLE_TIMEOUT_MS", 30_000, 1_000, 3_600_000),
    connectionTimeoutMs: int("DB_CONNECTION_TIMEOUT_MS", 10_000, 500, 120_000),
  },

  // ── Error tracking (optional, Sentry)
  sentry: {
    dsn: process.env.SENTRY_DSN || "",
    environment: process.env.SENTRY_ENVIRONMENT || env.nodeEnv,
    tracesSampleRate: num("SENTRY_TRACES_SAMPLE_RATE", 0, 0, 1),
  },

  // ── Metrics: GET /api/v1/admin/metrics for admins, or with `Authorization: Bearer <METRICS_TOKEN>` for a scraper
  metricsToken: process.env.METRICS_TOKEN || "",
  // p50/p95/p99 per route written to the log every this many ms (default 5 minutes; 0 = off)
  latencyLogIntervalMs: int("LATENCY_LOG_INTERVAL_MS", 5 * 60_000, 0, 24 * 3_600_000),

  // ── Background work
  workerMode: (rawWorkerMode === "api" && env.redisUrl ? "api" : "inline") as "inline" | "api",
  workerModeRequested: rawWorkerMode,
  queueConcurrency: int("QUEUE_CONCURRENCY", 5, 1, 100),

  // ── Idempotency-Key responses are kept this long (Redis, or an in-memory LRU on a single instance)
  idempotencyTtlSec: int("IDEMPOTENCY_TTL_SECONDS", 24 * 3600, 60, 7 * 24 * 3600),
  idempotencyMemoryMax: int("IDEMPOTENCY_MEMORY_MAX", 10_000, 100, 1_000_000),

  // ── Graceful shutdown: how long in-flight requests get after SIGTERM (Render waits 30 s by default)
  shutdownTimeoutMs: int("SHUTDOWN_TIMEOUT_MS", 25_000, 1_000, 300_000),

  // ── HTTP caching of public GETs (seconds). A CDN in front of the API can serve these.
  publicCacheSeconds: int("PUBLIC_CACHE_SECONDS", 30, 0, 86_400),
  publicStaleSeconds: int("PUBLIC_STALE_SECONDS", 120, 0, 86_400),
};
