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
});
