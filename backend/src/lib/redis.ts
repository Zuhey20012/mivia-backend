import Redis, { RedisOptions } from "ioredis";
import pino from "pino";
import { scale } from "../config/scale";

/**
 * Optional Redis (REDIS_URL). Without it every caller falls back to what a single instance did before:
 * in-memory rate limits, local socket rooms, a local session cache, an in-memory idempotency store and
 * in-process background work. Nothing here connects unless REDIS_URL is set.
 */
const logger = pino({ name: "redis" });

const clients = new Set<Redis>();
let main: Redis | null = null;
let subscriber: Redis | null = null;
const handlers = new Map<string, Set<(message: string) => void>>();

export function redisEnabled() {
  return !!scale.redisUrl;
}

/** Full key with the deployment's prefix, so several environments can share one Redis. */
export function rkey(key: string) {
  return `${scale.redisPrefix}${key}`;
}

/**
 * A new connection. `blocking` connections (BullMQ workers, pub/sub) must never give up on a command, the others
 * fail fast so a Redis outage slows nothing down for long.
 */
export function createRedisClient(purpose: string, opts: { blocking?: boolean } = {}): Redis {
  if (!scale.redisUrl) throw new Error("REDIS_URL is not set");
  const options: RedisOptions = {
    connectionName: `malvoya-${purpose}`,
    maxRetriesPerRequest: opts.blocking ? null : 2,
    enableReadyCheck: true,
    // Reconnect forever, backing off to 5 s between attempts
    retryStrategy: (times) => Math.min(times * 200, 5_000),
  };
  const client = new Redis(scale.redisUrl, options);
  let lastLogged = 0;
  client.on("error", (err) => {
    // Never log the URL (it carries the password); at most one line per 30 s per connection
    if (Date.now() - lastLogged > 30_000) {
      lastLogged = Date.now();
      logger.error({ purpose, err: err?.message }, "Redis connection error");
    }
  });
  clients.add(client);
  client.once("end", () => clients.delete(client));
  return client;
}

/** The shared command connection, or null without REDIS_URL. */
export function redis(): Redis | null {
  if (!scale.redisUrl) return null;
  if (!main) main = createRedisClient("main");
  return main;
}

/** Publishes to every instance (including this one). No-op without Redis. */
export function publish(channel: string, message: string) {
  const r = redis();
  if (!r) return;
  r.publish(rkey(channel), message).catch(() => {});
}

/** Runs the handler for every message on the channel from any instance. No-op without Redis. */
export function subscribe(channel: string, handler: (message: string) => void) {
  if (!scale.redisUrl) return;
  const full = rkey(channel);
  if (!subscriber) {
    subscriber = createRedisClient("subscriber", { blocking: true });
    subscriber.on("message", (ch: string, msg: string) => {
      for (const h of handlers.get(ch) ?? []) {
        try { h(msg); } catch { /* a bad handler must not break the others */ }
      }
    });
  }
  if (!handlers.has(full)) {
    handlers.set(full, new Set());
    subscriber.subscribe(full).catch((err) => logger.error({ channel, err: err?.message }, "Redis subscribe failed"));
  }
  handlers.get(full)!.add(handler);
}

/** Readiness: true when Redis answers within 2 s (true when Redis is not configured). */
export async function redisReady(): Promise<boolean | null> {
  const r = redis();
  if (!r) return null;
  try {
    const pong = await Promise.race([r.ping(), new Promise<string>((_, rej) => setTimeout(() => rej(new Error("timeout")), 2_000))]);
    return pong === "PONG";
  } catch {
    return false;
  }
}

/** Closes every connection (graceful shutdown). */
export async function closeRedis() {
  await Promise.all([...clients].map((c) => c.quit().catch(() => c.disconnect())));
  clients.clear();
  main = null;
  subscriber = null;
}
