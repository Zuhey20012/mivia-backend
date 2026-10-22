import crypto from "crypto";
import { Router, Request, Response, NextFunction } from "express";
import pino from "pino";
import { scale } from "../config/scale";
import { redis, rkey } from "../lib/redis";
import { verifyAccessToken } from "../utils/jwt";

/**
 * `Idempotency-Key` header on the money-moving and state-changing POST/PATCH routes: a retried request (flaky mobile
 * network, double tap) with the same key gets the first response again instead of doing the work twice.
 *  - Keys are scoped per signed-in user and per exact path (a key used on order 12 does nothing on order 13).
 *  - The same key with a different body → 422. A key whose first request is still running → 409.
 *  - Successful responses (2xx/3xx) are kept for IDEMPOTENCY_TTL_SECONDS (24 h); a 4xx or 5xx is not kept, so a retry runs again.
 *  - Storage: Redis when REDIS_URL is set (shared by every instance). Without Redis an in-memory LRU is used, which is
 *    correct ONLY while a single instance runs (a retry landing on another instance would not see the first response).
 * Requests without the header behave exactly as before.
 */
const logger = pino({ name: "idempotency" });

type Rec = { state: "pending" | "done"; fp: string; status?: number; body?: unknown };
const PENDING_TTL_SEC = 120; // a crashed request frees its key after this

interface Store {
  get(key: string): Promise<Rec | null>;
  reserve(key: string, rec: Rec): Promise<boolean>;
  complete(key: string, rec: Rec): Promise<void>;
  release(key: string): Promise<void>;
}

/** Single-instance store: least-recently-used entries are dropped beyond IDEMPOTENCY_MEMORY_MAX. */
class MemoryStore implements Store {
  private map = new Map<string, { rec: Rec; expires: number }>();
  private live(key: string) {
    const hit = this.map.get(key);
    if (!hit) return null;
    if (hit.expires < Date.now()) { this.map.delete(key); return null; }
    this.map.delete(key); // refresh LRU position
    this.map.set(key, hit);
    return hit;
  }
  private put(key: string, rec: Rec, ttlSec: number) {
    this.map.delete(key);
    this.map.set(key, { rec, expires: Date.now() + ttlSec * 1000 });
    while (this.map.size > scale.idempotencyMemoryMax) this.map.delete(this.map.keys().next().value!);
  }
  async get(key: string) { return this.live(key)?.rec ?? null; }
  async reserve(key: string, rec: Rec) {
    if (this.live(key)) return false;
    this.put(key, rec, PENDING_TTL_SEC);
    return true;
  }
  async complete(key: string, rec: Rec) { this.put(key, rec, scale.idempotencyTtlSec); }
  async release(key: string) { this.map.delete(key); }
}

class RedisStore implements Store {
  async get(key: string) {
    const raw = await redis()!.get(key);
    return raw ? (JSON.parse(raw) as Rec) : null;
  }
  async reserve(key: string, rec: Rec) {
    return (await redis()!.set(key, JSON.stringify(rec), "EX", PENDING_TTL_SEC, "NX")) === "OK";
  }
  async complete(key: string, rec: Rec) {
    await redis()!.set(key, JSON.stringify(rec), "EX", scale.idempotencyTtlSec);
  }
  async release(key: string) {
    await redis()!.del(key);
  }
}

let store: Store | null = null;
function getStore(): Store {
  if (!store) store = redis() ? new RedisStore() : new MemoryStore();
  return store;
}

/** JSON with object keys sorted, so {a,b} and {b,a} are the same request. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value as object).sort().map((k) => `${JSON.stringify(k)}:${canonical((value as any)[k])}`).join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

const sha256 = (s: string) => crypto.createHash("sha256").update(s).digest("hex");
const VALID_KEY = /^[\x21-\x7e]{1,255}$/; // printable ASCII, no spaces (UUIDs, ULIDs, …)

function userIdOf(req: Request): number | null {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) return null;
  try { return verifyAccessToken(header.slice(7)).id; } catch { return null; }
}

function decide(res: Response, rec: Rec, fp: string) {
  if (rec.fp !== fp) {
    return res.status(422).json({ ok: false, error: "This Idempotency-Key was already used with a different request." });
  }
  if (rec.state === "pending") {
    return res.status(409).json({ ok: false, error: "A request with this Idempotency-Key is still being processed. Try again shortly." });
  }
  res.setHeader("Idempotent-Replayed", "true");
  return res.status(rec.status ?? 200).json(rec.body);
}

export async function idempotency(req: Request, res: Response, next: NextFunction) {
  const rawKey = req.header("Idempotency-Key");
  if (rawKey === undefined) return next();
  if (!VALID_KEY.test(rawKey)) return res.status(400).json({ ok: false, error: "Idempotency-Key must be 1–255 printable characters" });
  const userId = userIdOf(req);
  if (!userId) return next(); // the route's own auth answers 401

  const path = req.originalUrl.split("?")[0];
  const key = rkey(`idem:${userId}:${sha256(`${req.method} ${path} ${rawKey}`)}`);
  const fp = sha256(canonical(req.body ?? null));
  const s = getStore();
  try {
    const existing = await s.get(key);
    if (existing) return decide(res, existing, fp);
    if (!(await s.reserve(key, { state: "pending", fp }))) {
      const now = await s.get(key);
      return now ? decide(res, now, fp) : res.status(409).json({ ok: false, error: "Please try again." });
    }
  } catch (err: any) {
    // Store unreachable: serve the request as if no key had been sent rather than failing it
    logger.warn({ err: err?.message }, "Idempotency store unavailable");
    return next();
  }

  let body: unknown;
  let captured = false;
  const json = res.json.bind(res);
  res.json = (b: unknown) => { body = b; captured = true; return json(b); };
  let settled = false;
  const settle = (finished: boolean) => {
    if (settled) return;
    settled = true;
    // Successful answers are kept; a refused request (4xx, e.g. 428 "accept the terms first") or a failure (5xx) frees
    // the key, so the corrected retry runs
    const keep = finished && captured && res.statusCode < 400;
    (keep ? s.complete(key, { state: "done", fp, status: res.statusCode, body }) : s.release(key))
      .catch((err: any) => logger.warn({ err: err?.message }, "Idempotency store write failed"));
  };
  res.on("finish", () => settle(true));
  res.on("close", () => settle(res.writableFinished));
  next();
}

/**
 * Routes that honour Idempotency-Key (mounted under /api/v1 before the routes themselves). Paths that do not exist
 * (yet) are harmless: the middleware only runs when a request matches.
 */
export const idempotencyRoutes = Router();
const routes: [("post" | "patch"), string][] = [
  ["post", "/orders"],                              // checkout: creates the order and the PaymentIntent
  ["post", "/orders/:id(\\d+)/collect"],            // Reserve & collect handover (completes the order, payout)
  ["post", "/orders/:id(\\d+)/cancel"],             // customer cancel (refund)
  ["patch", "/orders/:id(\\d+)/status"],            // store accept/decline (decline refunds), courier/admin steps
  ["post", "/orders/:id(\\d+)/return-to-store"],    // items refund + courier payout
  ["post", "/orders/:id(\\d+)/deliver"],            // completes the order (payouts are created)
  ["post", "/returns"],
  ["patch", "/returns/:id(\\d+)/status"],           // REFUNDED issues a Stripe refund
  ["post", "/rentals"],
  ["post", "/payouts/onboarding"],
  ["post", "/admin/payouts/:id(\\d+)/retry"],       // payout transfer
  ["post", "/me/agreements/accept"],                // agreement acceptance (when the route exists)
];
for (const [method, path] of routes) idempotencyRoutes[method](path, idempotency);
