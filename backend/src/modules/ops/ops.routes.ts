import crypto from "crypto";
import { Router, Request, Response, NextFunction } from "express";
import { prisma, dbPoolStats } from "../../lib/prisma";
import { redisEnabled, redisReady } from "../../lib/redis";
import { metricsSnapshot } from "../../lib/metrics";
import { localSocketConnections } from "../../lib/socket";
import { queueStats } from "../../lib/queue";
import { sentryEnabled } from "../../lib/sentry";
import { scale } from "../../config/scale";
import { auth, requireRole } from "../../middleware/auth";
import { env } from "../../config/env";

/**
 * Operations endpoints: liveness, readiness and metrics.
 *  GET /health          liveness: the process is up (Render's health check)
 *  GET /health/ready    readiness: the database (and Redis, when configured) answer; 503 while shutting down
 *  GET /api/v1/admin/metrics  this instance's numbers, for admins or `Authorization: Bearer <METRICS_TOKEN>`
 *  GET /.well-known/security.txt  where to report a vulnerability (RFC 9116)
 */
export const opsRoutes = Router();
const VERSION = "2.16.0";

let draining = false;
/** Called on SIGTERM: readiness turns 503 so a load balancer stops sending new requests here. */
export function markDraining() {
  draining = true;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Where security researchers report problems: SECURITY_CONTACT (comma-separated; an email address, mailto: or
 * https: link), otherwise SUPPORT_EMAIL. Empty when neither is set (security.txt then answers 404 and System says so).
 */
export function securityContacts(): string[] {
  const given = (process.env.SECURITY_CONTACT || "").split(",").map((c) => c.trim()).filter(Boolean)
    .map((c) => (EMAIL_RE.test(c) ? `mailto:${c}` : c))
    .filter((c) => (c.startsWith("mailto:") && EMAIL_RE.test(c.slice(7))) || /^https:\/\/[^\s]+$/.test(c));
  if (given.length) return given;
  const support = (process.env.SUPPORT_EMAIL || "").trim();
  return EMAIL_RE.test(support) ? [`mailto:${support}`] : [];
}

/** RFC 9116 security.txt. Expires rolls forward (180 days, whole days so caches agree). */
opsRoutes.get("/.well-known/security.txt", (_req, res) => {
  const contacts = securityContacts();
  if (!contacts.length) return res.status(404).type("text/plain").send("Not found\n");
  const day = 24 * 60 * 60 * 1000;
  const expires = new Date(Math.floor(Date.now() / day) * day + 180 * day).toISOString().replace(".000Z", "Z");
  res.set("Cache-Control", "public, max-age=86400");
  res.type("text/plain; charset=utf-8").send([
    ...contacts.map((c) => `Contact: ${c}`),
    `Expires: ${expires}`,
    "Preferred-Languages: en, fi",
    `Canonical: ${env.publicApiUrl}/.well-known/security.txt`,
    "",
  ].join("\n"));
});

opsRoutes.get("/health", (_req, res) => res.json({ ok: true, status: "healthy", version: VERSION }));

opsRoutes.get("/health/ready", async (_req, res) => {
  const database = await Promise.race([
    prisma.$queryRaw`SELECT 1`.then(() => "up", () => "down"),
    new Promise<string>((r) => setTimeout(() => r("down"), 3_000)),
  ]);
  const r = await redisReady();
  const redisState = r === null ? "not configured" : r ? "up" : "down";
  const ok = !draining && database === "up" && r !== false;
  res.status(ok ? 200 : 503).json({ ok, database, redis: redisState, ...(draining ? { draining: true } : {}) });
});

function tokenMatches(req: Request) {
  if (!scale.metricsToken) return false;
  const given = req.headers.authorization?.startsWith("Bearer ") ? req.headers.authorization.slice(7) : "";
  const a = Buffer.from(crypto.createHash("sha256").update(given).digest("hex"));
  const b = Buffer.from(crypto.createHash("sha256").update(scale.metricsToken).digest("hex"));
  return crypto.timingSafeEqual(a, b);
}

/** METRICS_TOKEN for a scraper, otherwise a signed-in admin. */
function metricsAccess(req: Request, res: Response, next: NextFunction) {
  if (tokenMatches(req)) return next();
  auth(req as any, res, () => requireRole("ADMIN")(req as any, res, next));
}

opsRoutes.get("/api/v1/admin/metrics", metricsAccess, async (_req, res) => {
  res.set("Cache-Control", "no-store");
  res.json({
    ok: true,
    version: VERSION,
    instance: process.env.RENDER_INSTANCE_ID || process.env.HOSTNAME || null,
    ...metricsSnapshot(),
    db: { pool: dbPoolStats() },
    sockets: { connectionsThisInstance: localSocketConnections() },
    queue: await queueStats(),
    features: { redis: redisEnabled(), sentry: sentryEnabled(), workerMode: scale.workerMode },
  });
});
