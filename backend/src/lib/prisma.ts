import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { env } from "../config/env";

// Prisma 7 talks to Postgres through a driver adapter (node-postgres) instead of the Rust engine.
// Pool size is per API instance: keep instances × DB_POOL_MAX below the database's connection limit.
export const prisma = new PrismaClient({
  adapter: new PrismaPg({
    connectionString: env.databaseUrl,
    max: Number(process.env.DB_POOL_MAX) || 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
  }),
  // Never part of an order payload unless asked for: the pickup code belongs to the customer only, who invited
  // the customer is nobody else's business, and the courier's pay breakdown (ride km, waiting minutes, rates) is
  // for the courier, admins and payouts. Queries that need them ask with `omit: { …: false }` or `select`
  // (orders.service.ts: customer views, the store's code check, courier views; referrals; dispatch; admin).
  omit: { order: { pickupCode: true, referrerId: true, courierPay: true } },
});
