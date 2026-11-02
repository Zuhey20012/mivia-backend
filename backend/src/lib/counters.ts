import crypto from "crypto";
import { prisma } from "./prisma";

/**
 * Shared fixed-window counters in Postgres (Counter table, since 2.16.0): every API instance sees the same numbers,
 * with or without Redis. A window starts with the first hit and ends `windowMs` later; the next hit after that starts
 * a new window. Expired rows are deleted by the scheduler (expired-sign-in-codes job).
 */
export async function bump(key: string, windowMs: number, by = 1): Promise<{ count: number; expiresAt: Date }> {
  const exp = new Date(Date.now() + windowMs);
  const rows = await prisma.$queryRaw<{ count: number; expiresAt: Date }[]>`
    INSERT INTO "Counter" ("key", "count", "expiresAt") VALUES (${key}, ${by}, ${exp})
    ON CONFLICT ("key") DO UPDATE SET
      "count" = CASE WHEN "Counter"."expiresAt" < NOW() THEN ${by} ELSE "Counter"."count" + ${by} END,
      "expiresAt" = CASE WHEN "Counter"."expiresAt" < NOW() THEN ${exp} ELSE "Counter"."expiresAt" END
    RETURNING "count", "expiresAt"`;
  return { count: Number(rows[0]?.count ?? by), expiresAt: rows[0]?.expiresAt ?? exp };
}

/** The current count of a live window (0 when none or expired). */
export async function peek(key: string): Promise<{ count: number; expiresAt: Date | null }> {
  const row = await prisma.counter.findUnique({ where: { key } });
  if (!row || row.expiresAt < new Date()) return { count: 0, expiresAt: null };
  return { count: row.count, expiresAt: row.expiresAt };
}

/** Sets a flag that lasts `ms` (e.g. a lock); peek(key).count > 0 while it lasts. */
export async function setFlag(key: string, ms: number) {
  const exp = new Date(Date.now() + ms);
  await prisma.counter.upsert({ where: { key }, create: { key, count: 1, expiresAt: exp }, update: { count: 1, expiresAt: exp } });
  return exp;
}

export async function clear(key: string) {
  await prisma.counter.deleteMany({ where: { key } });
}

/** Keys never hold an address or phone number in clear. */
export const hashKey = (value: string) => crypto.createHash("sha256").update(value.trim().toLowerCase()).digest("hex").slice(0, 40);

/** Today's date in Finland (daily caps reset at Finnish midnight). */
export function helsinkiDay(d = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Helsinki", year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
}

export async function purgeExpiredCounters() {
  return prisma.counter.deleteMany({ where: { expiresAt: { lt: new Date() } } });
}
