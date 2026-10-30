import crypto from "crypto";
import { env } from "../config/env";

/**
 * Unsubscribe links for optional emails (since 2.16.0). The token is `<userId>.<HMAC-SHA256>` with a key derived from
 * JWT_SECRET under its own label (or UNSUBSCRIBE_LINK_SECRET): it never expires, so a link in an old email keeps
 * working (RFC 8058 one-click and the confirmation page), and it can only switch optional emails off. Changing the
 * secret makes old links invalid; the in-app switch (PATCH /me {emailMarketing}) always works.
 */
const key = crypto
  .createHmac("sha256", process.env.UNSUBSCRIBE_LINK_SECRET || env.jwtSecret)
  .update("malvoya:email-unsubscribe:v1")
  .digest();

function sign(userId: number) {
  return crypto.createHmac("sha256", key).update(`unsubscribe|optional|${userId}`).digest("base64url");
}

export function unsubscribeToken(userId: number) {
  return `${userId}.${sign(userId)}`;
}

/** The user id of a valid token, or null (constant-time compare). */
export function verifyUnsubscribeToken(raw: unknown): number | null {
  if (typeof raw !== "string" || raw.length > 200) return null;
  const m = /^([1-9]\d{0,9})\.([A-Za-z0-9_-]{43})$/.exec(raw);
  if (!m) return null;
  const userId = Number(m[1]);
  const expected = Buffer.from(sign(userId));
  const given = Buffer.from(m[2]);
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  return userId;
}

/** The public link (GET shows a confirmation page, POST is the one-click unsubscribe). */
export function unsubscribeUrl(userId: number) {
  return `${env.publicApiUrl}/email/unsubscribe?t=${encodeURIComponent(unsubscribeToken(userId))}`;
}

/** RFC 2369 + RFC 8058 headers for an optional email. */
export function unsubscribeHeaders(userId: number): Record<string, string> {
  return {
    "List-Unsubscribe": `<${unsubscribeUrl(userId)}>`,
    "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
  };
}
