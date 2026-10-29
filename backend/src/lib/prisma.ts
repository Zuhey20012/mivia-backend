import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";
import { env } from "../config/env";
import { scale } from "../config/scale";

// Prisma 7 talks to Postgres through a driver adapter (node-postgres) instead of the Rust engine. The pool is
// created here so its usage can be reported (/admin/metrics) and closed on shutdown.
// Pool size is per API instance: keep instances × DB_POOL_MAX below the database's connection limit (or put
// PgBouncer / a pooler in front; see docs/scaling/scaling-plan.md).
export const pgPool = new Pool({
  connectionString: env.databaseUrl,
  max: scale.db.poolMax,
  idleTimeoutMillis: scale.db.idleTimeoutMs,
  connectionTimeoutMillis: scale.db.connectionTimeoutMs,
  // Server-side guards: a runaway query or a transaction left open cannot hold a connection for ever (0 = off)
  ...(scale.db.statementTimeoutMs ? { statement_timeout: scale.db.statementTimeoutMs } : {}),
  ...(scale.db.idleInTransactionTimeoutMs ? { idle_in_transaction_session_timeout: scale.db.idleInTransactionTimeoutMs } : {}),
  application_name: "malvoya-api",
});
// An idle client that loses its connection (database restart, failover) must not crash the process
pgPool.on("error", () => {});

export const prisma = new PrismaClient({
  adapter: new PrismaPg(pgPool),
  // Never part of an order payload unless asked for: the pickup code belongs to the customer only, who invited
  // the customer is nobody else's business, and the courier's pay breakdown (ride km, waiting minutes, rates) is
  // for the courier, admins and payouts. Queries that need them ask with `omit: { …: false }` or `select`
  // (orders.service.ts: customer views, the store's code check, courier views; referrals; dispatch; admin).
  // Since 2.16: the handover PIN (customer only, like the pickup code), the card fingerprint (fraud checks) and the
  // receipt address (customer and admins) too.
  // The authenticator secret and recovery-code hashes (two-step sign-in) are read only by auth/mfa.ts, with `select`.
  omit: { order: { pickupCode: true, referrerId: true, courierPay: true, handoverPin: true, cardFingerprint: true, receiptEmail: true }, user: { totpSecret: true, totpRecoveryCodes: true } },
});

/** Pool usage for metrics: open connections, idle ones, and queries waiting for a connection. */
export function dbPoolStats() {
  return { max: scale.db.poolMax, total: pgPool.totalCount, idle: pgPool.idleCount, waiting: pgPool.waitingCount };
}
