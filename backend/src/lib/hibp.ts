import crypto from "crypto";
import pino from "pino";

const logger = pino({ name: "hibp" });

/**
 * Breached-password check (since 2.16.0) with the Have I Been Pwned k-anonymity range API: only the first 5 hex
 * characters of the password's SHA-1 leave the server, never the password or its full hash. 2-second timeout and fail
 * open (an outage never blocks a sign-up). HIBP_DISABLED=true switches it off (tests, offline development).
 */
export async function isBreachedPassword(password: string): Promise<boolean> {
  if (process.env.HIBP_DISABLED === "true") return false;
  const sha1 = crypto.createHash("sha1").update(password).digest("hex").toUpperCase();
  const prefix = sha1.slice(0, 5);
  const suffix = sha1.slice(5);
  try {
    const res = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
      headers: { "Add-Padding": "true", "User-Agent": "Malvoya-API" },
      signal: AbortSignal.timeout(2000),
    });
    if (!res.ok) return false;
    const body = await res.text();
    return body.split("\n").some((line) => {
      const [hash, count] = line.trim().split(":");
      return hash === suffix && Number(count) > 0;
    });
  } catch (e: any) {
    logger.warn({ err: e?.message }, "Breached-password check unavailable; allowed");
    return false;
  }
}

export const BREACHED_PASSWORD = "This password appears in known data breaches. Choose another.";
