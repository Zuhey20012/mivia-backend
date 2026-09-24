import "dotenv/config";
import { defineConfig } from "prisma/config";

// Prisma 7: connection settings live here instead of schema.prisma.
// DATABASE_URL is read directly (not via env()) so `prisma generate` also works in
// build steps that have no database, e.g. the Docker build stage.
export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "ts-node prisma/seed.ts",
  },
  datasource: {
    url: process.env.DATABASE_URL ?? "",
  },
});
