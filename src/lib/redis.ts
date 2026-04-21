import Redis from "ioredis";
import { env } from "../config/env";
export const redis = env.redisUrl ? new Redis(env.redisUrl) : new Redis({ lazyConnect: true });
redis.on("error", (err) => {
  console.warn("[redis] connection error (continuing without redis):", err?.message || err);
});
