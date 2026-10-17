import crypto from "crypto";
import { env } from "../../config/env";
import { monthRange } from "./statements";

/**
 * Short-lived links to a store's printable statement, so it opens in a normal browser (no bearer token there).
 * The link carries the store, the month and an expiry, signed with HMAC-SHA256. The key is derived from
 * JWT_SECRET with its own label (a link can never be used as, or made from, a token), or STATEMENT_LINK_SECRET
 * when that is set. Signatures are compared in constant time. Links are valid for 10 minutes.
 */
export const STATEMENT_LINK_TTL_SECONDS = 10 * 60;

const key = crypto
  .createHmac("sha256", process.env.STATEMENT_LINK_SECRET || env.jwtSecret)
  .update("malvoya:statement-link:v1")
  .digest();

function sign(storeId: number, month: string, exp: number) {
  return crypto.createHmac("sha256", key).update(`statement|${storeId}|${month}|${exp}`).digest("base64url");
}

export function statementLink(storeId: number, month: string) {
  monthRange(month); // validates the month (400)
  const exp = Math.floor(Date.now() / 1000) + STATEMENT_LINK_TTL_SECONDS;
  const sig = sign(storeId, month, exp);
  return {
    url: `${env.publicApiUrl}/api/v1/stores/statements/${storeId}/${month}.html?exp=${exp}&sig=${sig}`,
    expiresAt: new Date(exp * 1000),
  };
}

/** "ok", or why the link cannot be used. */
export function checkStatementLink(storeId: number, month: string, expRaw: unknown, sigRaw: unknown): "ok" | "expired" | "invalid" {
  const exp = Number(expRaw);
  if (typeof sigRaw !== "string" || !Number.isInteger(exp)) return "invalid";
  const expected = Buffer.from(sign(storeId, month, exp));
  const given = Buffer.from(sigRaw);
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return "invalid";
  return exp * 1000 < Date.now() ? "expired" : "ok";
}
