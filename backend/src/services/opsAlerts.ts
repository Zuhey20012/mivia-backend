import crypto from "crypto";
import pino from "pino";
import { prisma } from "../lib/prisma";
import { alertAdmins } from "../lib/adminAlerts";
import { systemSnapshot } from "../modules/admin/system";

const logger = pino({ name: "ops-alerts" });

/**
 * Every 5 minutes (scheduler `ops-alerts`, 2.17): admins are pushed and emailed about NEW items in System → attention.
 * Each item is remembered by a hash of its text (counts and "N min ago" left out, so a growing queue is one item);
 * an item that has been gone for 6 hours and comes back is new again.
 */
const FORGET_AFTER_MS = 6 * 3600_000;

export function alertKey(line: string) {
  const norm = line.replace(/\(reported \d+ min ago\)/g, "").replace(/^\d+ /, "N ").replace(/\s+/g, " ").trim();
  return crypto.createHash("sha256").update(norm).digest("hex");
}

export async function runOpsAlerts() {
  const snap = await systemSnapshot();
  const now = new Date();
  const keyed = new Map(snap.attention.map((l) => [alertKey(l), l]));
  const known = keyed.size ? await prisma.opsAlert.findMany({ where: { hash: { in: [...keyed.keys()] } }, select: { hash: true } }) : [];
  const knownSet = new Set(known.map((k) => k.hash));
  const fresh = [...keyed.entries()].filter(([h]) => !knownSet.has(h));
  if (fresh.length) {
    await prisma.opsAlert.createMany({ data: fresh.map(([hash, text]) => ({ hash, text: text.slice(0, 500), firstSeenAt: now, lastSeenAt: now })), skipDuplicates: true });
    await alertAdmins(fresh.length === 1 ? "Malvoya needs attention" : `Malvoya: ${fresh.length} new things need attention`, fresh.map(([, l]) => `• ${l}`));
    logger.info({ count: fresh.length }, "Admins alerted");
  }
  if (knownSet.size) await prisma.opsAlert.updateMany({ where: { hash: { in: [...knownSet] } }, data: { lastSeenAt: now } });
  await prisma.opsAlert.deleteMany({ where: { lastSeenAt: { lt: new Date(now.getTime() - FORGET_AFTER_MS) } } });
  return fresh.length;
}
