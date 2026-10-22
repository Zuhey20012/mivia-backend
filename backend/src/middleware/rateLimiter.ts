import crypto from "crypto";
import rateLimit, { Options } from "express-rate-limit";
import { RedisStore } from "rate-limit-redis";
import { redis, rkey } from "../lib/redis";

/**
 * Where the counters live. With REDIS_URL they are shared by every instance (a client gets the same limit however
 * many instances run); without it each instance counts in memory, as before. If Redis stops answering, requests
 * are let through (passOnStoreError) rather than failing the whole API.
 */
export function rateLimitStore(name: string): Pick<Partial<Options>, "store" | "passOnStoreError"> {
  const r = redis();
  if (!r) return {};
  return {
    store: new RedisStore({
      prefix: rkey(`rl:${name}:`),
      sendCommand: (command: string, ...args: string[]) => r.call(command, ...args) as any,
    }),
    passOnStoreError: true,
  };
}

export const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 600,                 // per client IP (requires app.set("trust proxy") behind Render)
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many requests, please try again later." },
  ...rateLimitStore("global"),
});

export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20, // stricter for login / register / OTP
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many attempts, please try again later." },
  ...rateLimitStore("auth"),
});


const tooMany = { ok: false, error: "Too many attempts, please try again later." };

/** Forgot password, per client address. */
export const passwordForgotIpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: tooMany,
  ...rateLimitStore("pwforgot-ip"),
});

/**
 * Forgot password, per email address (whether or not it has an account, so the limit reveals nothing):
 * 3 requests an hour. The key is a hash, so addresses are not kept in memory in clear.
 */
export const passwordForgotEmailLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
  message: tooMany,
  keyGenerator: (req) => {
    const email = typeof req.body?.email === "string" ? req.body.email.trim().toLowerCase() : "";
    return `pw:${crypto.createHash("sha256").update(email).digest("hex")}`;
  },
  ...rateLimitStore("pwforgot-email"),
});

/** Setting the new password with the code, per client address (each code also allows only 5 tries). */
export const passwordResetLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: tooMany,
  ...rateLimitStore("pwreset"),
});
