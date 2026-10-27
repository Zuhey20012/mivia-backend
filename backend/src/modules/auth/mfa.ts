import crypto from "crypto";
import bcrypt from "bcryptjs";
import { Router, Request, Response } from "express";
import { z } from "zod";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { ApiError, sendError } from "../../lib/errors";
import { localeOfUser } from "../../lib/i18n";
import { auth, AuthRequest, forgetSessionState } from "../../middleware/auth";
import { authLimiter } from "../../middleware/rateLimiter";
import { verifyMfaToken } from "../../utils/jwt";
import { sendTwoStepNotice, TwoStepEvent } from "../../services/notificationDeliveryService";
import { issueSession, hasPassword, revokeAllSessions } from "./session";
import { TWO_STEP_OFF } from "./twoStepFields";

const logger = pino({ name: "two-step" });

/**
 * Two-step sign-in with an authenticator app (since 2.13.0, admin accounts): RFC 6238 TOTP (HMAC-SHA1, 30-second
 * steps, 6 digits, ±1 step for clock drift), which every authenticator app (Google Authenticator, Microsoft
 * Authenticator, 1Password, Authy…) reads from the otpauth:// link or its QR code.
 *
 *  - Set-up: POST /me/mfa/setup (password again) → secret + link; POST /me/mfa/enable {code} turns it on, returns
 *    10 one-time recovery codes once, ends every other session and returns a fresh one.
 *  - Sign-in: every first step (password, email code, Google, phone, Apple) returns { mfaRequired, mfaToken } instead
 *    of tokens (session.ts#issueSession); POST /auth/login/mfa {mfaToken, code} gives the session.
 *  - A code works once (its step is stored); 5 wrong codes in a row lock the second step for 15 minutes.
 *  - The secret is encrypted (AES-256-GCM, key derived from JWT_SECRET, bound to the account); recovery codes are
 *    stored as SHA-256 (they are random, 50 bits). Turning it on/off and using a recovery code are audited and emailed.
 *  - Lost phone and recovery codes: an admin reset from the SEED_ADMIN_* settings (lib/bootstrapAdmin.ts) starts over.
 */

const ISSUER = "Malvoya";
const STEP_SECONDS = 30;
const MAX_FAILURES = 5;
const LOCK_MINUTES = 15;
const RECOVERY_CODES = 10;

// ─── TOTP (RFC 6238 / RFC 4226) ─────────────────────────────────────────────

const B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function base32Encode(buf: Buffer): string {
  let bits = 0, value = 0, out = "";
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(text: string): Buffer {
  const clean = text.replace(/[\s=]/g, "").toUpperCase();
  let bits = 0, value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const i = B32.indexOf(ch);
    if (i < 0) throw new Error("Not base32");
    value = (value << 5) | i;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

/** The 6-digit code of one 30-second step. */
export function totpAt(secret: Buffer, step: number): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const h = crypto.createHmac("sha1", secret).update(counter).digest();
  const o = h[h.length - 1] & 0x0f;
  const n = (((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3]) % 1_000_000;
  return n.toString().padStart(6, "0");
}

export const currentStep = (now = Date.now()) => Math.floor(now / 1000 / STEP_SECONDS);

/** The step a code belongs to (the current one or a neighbour, for phones whose clock is a little off), or null. */
function matchStep(secret: Buffer, code: string): number | null {
  const now = currentStep();
  let found: number | null = null;
  for (const step of [now - 1, now, now + 1]) {
    // Every candidate is compared (constant time), so timing does not tell which step matched
    if (crypto.timingSafeEqual(Buffer.from(totpAt(secret, step)), Buffer.from(code)) && found === null) found = step;
  }
  return found;
}

// ─── Secret at rest ─────────────────────────────────────────────────────────

const KEY = Buffer.from(crypto.hkdfSync("sha256", env.jwtSecret, "malvoya", "totp-secret-v1", 32));

function encryptSecret(secret: Buffer, userId: number): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", KEY, iv);
  cipher.setAAD(Buffer.from(`totp|${userId}`));
  const enc = Buffer.concat([cipher.update(secret), cipher.final()]);
  return `t1:${Buffer.concat([iv, cipher.getAuthTag(), enc]).toString("base64")}`;
}

/** null when missing or not decryptable (JWT_SECRET changed, or copied from another account). */
function decryptSecret(stored: string | null, userId: number): Buffer | null {
  if (!stored?.startsWith("t1:")) return null;
  try {
    const raw = Buffer.from(stored.slice(3), "base64");
    const decipher = crypto.createDecipheriv("aes-256-gcm", KEY, raw.subarray(0, 12));
    decipher.setAAD(Buffer.from(`totp|${userId}`));
    decipher.setAuthTag(raw.subarray(12, 28));
    return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]);
  } catch {
    return null;
  }
}

// ─── Recovery codes ─────────────────────────────────────────────────────────

const RC_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"; // no 0/o, 1/i/l
const sha256 = (v: string) => crypto.createHash("sha256").update(v).digest("hex");
const normaliseCode = (code: string) => code.replace(/[\s-]/g, "").toLowerCase();

function newRecoveryCodes() {
  const codes = Array.from({ length: RECOVERY_CODES }, () => {
    const c = Array.from({ length: 10 }, () => RC_ALPHABET[crypto.randomInt(RC_ALPHABET.length)]).join("");
    return `${c.slice(0, 5)}-${c.slice(5)}`;
  });
  return { codes, hashes: codes.map((c) => sha256(normaliseCode(c))) };
}

// ─── Checks ─────────────────────────────────────────────────────────────────

const twoStepSelect = {
  id: true, email: true, name: true, role: true, isActive: true, passwordHash: true, googleSub: true, tokensValidAfter: true,
  totpSecret: true, totpEnabledAt: true, totpLastStep: true, totpRecoveryCodes: true, totpLockedUntil: true,
} as const;

async function loadAccount(userId: number) {
  return prisma.user.findUnique({ where: { id: userId }, select: twoStepSelect });
}
type Account = NonNullable<Awaited<ReturnType<typeof loadAccount>>>;

/**
 * Checks an authenticator code (or, where allowed, a recovery code) against the account's secret. A right code
 * clears the failure count; a wrong one counts, and the fifth in a row locks the second step for 15 minutes.
 */
async function checkCode(u: Account, code: string, allowRecovery: boolean): Promise<{ usedRecovery: boolean; recoveryCodesLeft: number }> {
  if (u.totpLockedUntil && u.totpLockedUntil > new Date()) {
    throw new ApiError(`Too many wrong codes. Try again in ${LOCK_MINUTES} minutes.`, 429);
  }
  const clean = normaliseCode(code);
  if (/^\d{6}$/.test(clean)) {
    const secret = decryptSecret(u.totpSecret, u.id);
    const step = secret ? matchStep(secret, clean) : null;
    if (step !== null) {
      // Each step's code works once: a code read over someone's shoulder or from a log cannot be used again
      const r = await prisma.user.updateMany({
        where: { id: u.id, OR: [{ totpLastStep: null }, { totpLastStep: { lt: step } }] },
        data: { totpLastStep: step, totpFailures: 0, totpLockedUntil: null },
      });
      if (r.count === 1) return { usedRecovery: false, recoveryCodesLeft: u.totpRecoveryCodes.length };
    }
  } else if (allowRecovery && /^[a-z0-9]{10}$/.test(clean)) {
    const hash = sha256(clean);
    // Removed in one statement, so the same recovery code cannot open two sessions at once
    const used = await prisma.$executeRaw`UPDATE "User" SET "totpRecoveryCodes" = array_remove("totpRecoveryCodes", ${hash}), "totpFailures" = 0, "totpLockedUntil" = NULL WHERE id = ${u.id} AND ${hash} = ANY("totpRecoveryCodes")`;
    if (used === 1) return { usedRecovery: true, recoveryCodesLeft: u.totpRecoveryCodes.filter((h) => h !== hash).length };
  }

  const after = await prisma.user.update({ where: { id: u.id }, data: { totpFailures: { increment: 1 } }, select: { totpFailures: true } });
  if (after.totpFailures >= MAX_FAILURES) {
    await prisma.user.update({ where: { id: u.id }, data: { totpFailures: 0, totpLockedUntil: new Date(Date.now() + LOCK_MINUTES * 60_000) } });
    throw new ApiError(`Too many wrong codes. Try again in ${LOCK_MINUTES} minutes.`, 429);
  }
  const err = new ApiError("That code is not right. Check the time on your phone and try the newest code.", 400);
  err.extra = { attemptsLeft: MAX_FAILURES - after.totpFailures };
  throw err;
}

function audit(userId: number, action: string, newValue?: Record<string, unknown>) {
  return prisma.adminAuditLog.create({ data: { adminId: userId, action, entity: "User", entityId: userId, newValue: newValue as any } })
    .catch((e) => logger.error({ err: e?.message }, "Could not write the audit row"));
}

async function notify(u: { id: number; email: string }, event: TwoStepEvent, recoveryCodesLeft: number | null = null) {
  try {
    await sendTwoStepNotice(u.email, event, recoveryCodesLeft, await localeOfUser(u.id));
  } catch (e: any) {
    logger.error({ err: e?.message }, "Could not send the two-step notice");
  }
}

async function requirePassword(u: Account, password: string | undefined) {
  if (!hasPassword(u.passwordHash)) return; // Google / code accounts: the signed-in session is the proof
  if (!password || !(await bcrypt.compare(password, u.passwordHash))) throw new ApiError("The password is wrong", 400);
}

// ─── Sign-in: the second step ───────────────────────────────────────────────

const EXPIRED = "This sign-in has expired. Please start again.";

/** POST /auth/login/mfa: the challenge token from the first step plus an authenticator or recovery code → session. */
export async function completeTwoStepSignIn(mfaToken: string, code: string) {
  let claim: { id: number; iat: number };
  try {
    claim = verifyMfaToken(mfaToken);
  } catch {
    throw new ApiError(EXPIRED, 401);
  }
  const u = await loadAccount(claim.id);
  // A password reset or ban after the first step ends it too
  if (!u || !u.isActive || !u.totpEnabledAt || (u.tokensValidAfter && claim.iat < Math.floor(u.tokensValidAfter.getTime() / 1000))) {
    throw new ApiError(EXPIRED, 401);
  }
  const result = await checkCode(u, code, true);
  if (result.usedRecovery) {
    await audit(u.id, "mfa.recovery_code_used", { recoveryCodesLeft: result.recoveryCodesLeft });
    void notify(u, "recovery_code_used", result.recoveryCodesLeft);
  }
  const session = await issueSession(u, { mfa: true });
  return { ...session, ...(result.usedRecovery ? { recoveryCodesLeft: result.recoveryCodesLeft } : {}) };
}

// ─── Routes ─────────────────────────────────────────────────────────────────

const codeSchema = z.object({ code: z.string().trim().min(6).max(20) });

/** Two-step sign-in is for admin accounts (the keys to every order, payout and personal record). */
function adminOnly(req: AuthRequest) {
  if (req.user!.role !== "ADMIN") throw new ApiError("Two-step sign-in is available for admin accounts", 403);
}

export const mfaAuthRoutes = Router();

mfaAuthRoutes.post("/login/mfa", authLimiter, async (req: Request, res: Response) => {
  const body = z.object({ mfaToken: z.string().min(10).max(2000), code: z.string().trim().min(6).max(20) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter the 6-digit code from your authenticator app" });
  try {
    res.json({ ok: true, ...(await completeTwoStepSignIn(body.data.mfaToken, body.data.code)) });
  } catch (e) { sendError(res, e); }
});

export const mfaMeRoutes = Router();

/** Status: on/off, whether this service requires it, a set-up in progress, recovery codes left. */
mfaMeRoutes.get("/me/mfa", auth, async (req: AuthRequest, res: Response) => {
  try {
    adminOnly(req);
    const u = await loadAccount(req.user!.id);
    if (!u) throw new ApiError("Account not found", 404);
    res.json({
      ok: true,
      enabled: !!u.totpEnabledAt,
      enabledAt: u.totpEnabledAt,
      required: env.adminMfaRequired,
      pending: !u.totpEnabledAt && !!u.totpSecret,
      recoveryCodesLeft: u.totpEnabledAt ? u.totpRecoveryCodes.length : null,
      sessionVerified: !!req.user!.mfa,
      needsPassword: hasPassword(u.passwordHash),
    });
  } catch (e) { sendError(res, e); }
});

/** Step 1 of turning it on: a new secret for the authenticator app (shown once; nothing changes until /enable). */
mfaMeRoutes.post("/me/mfa/setup", authLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = z.object({ password: z.string().max(72).optional() }).safeParse(req.body ?? {});
  if (!body.success) return res.status(400).json({ ok: false, error: "Check the details" });
  try {
    adminOnly(req);
    const u = await loadAccount(req.user!.id);
    if (!u) throw new ApiError("Account not found", 404);
    if (u.totpEnabledAt) throw new ApiError("Two-step sign-in is already on", 409);
    await requirePassword(u, body.data.password);
    const secret = crypto.randomBytes(20); // 160 bits, as RFC 4226 recommends
    await prisma.user.update({
      where: { id: u.id },
      data: { totpSecret: encryptSecret(secret, u.id), totpLastStep: null, totpFailures: 0, totpLockedUntil: null },
    });
    const b32 = base32Encode(secret);
    const label = encodeURIComponent(`${ISSUER}:${u.email}`);
    res.json({
      ok: true,
      secret: b32,
      otpauthUrl: `otpauth://totp/${label}?secret=${b32}&issuer=${ISSUER}&algorithm=SHA1&digits=6&period=${STEP_SECONDS}`,
    });
  } catch (e) { sendError(res, e); }
});

/** Step 2: the first code from the app turns it on. Returns the recovery codes (only now) and a fresh session. */
mfaMeRoutes.post("/me/mfa/enable", authLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = codeSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter the 6-digit code from your authenticator app" });
  try {
    adminOnly(req);
    const u = await loadAccount(req.user!.id);
    if (!u) throw new ApiError("Account not found", 404);
    if (u.totpEnabledAt) throw new ApiError("Two-step sign-in is already on", 409);
    if (!u.totpSecret) throw new ApiError("Start the set-up first", 409);
    await checkCode(u, body.data.code, false);
    const { codes, hashes } = newRecoveryCodes();
    // Every session from before (none of which passed a second step) ends here, on every device
    await prisma.user.update({ where: { id: u.id }, data: { totpEnabledAt: new Date(), totpRecoveryCodes: hashes, tokensValidAfter: new Date() } });
    await revokeAllSessions(u.id);
    forgetSessionState(u.id);
    await audit(u.id, "mfa.enable");
    void notify(u, "enabled");
    const session = await issueSession(u, { mfa: true });
    res.json({ ok: true, recoveryCodes: codes, ...session });
  } catch (e) { sendError(res, e); }
});

/** Turning it off takes the password and a current code (or a recovery code). */
mfaMeRoutes.post("/me/mfa/disable", authLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = codeSchema.extend({ password: z.string().max(72).optional() }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter your password and a code from your authenticator app" });
  try {
    adminOnly(req);
    const u = await loadAccount(req.user!.id);
    if (!u) throw new ApiError("Account not found", 404);
    if (!u.totpEnabledAt) throw new ApiError("Two-step sign-in is not on", 409);
    await requirePassword(u, body.data.password);
    await checkCode(u, body.data.code, true);
    await prisma.user.update({ where: { id: u.id }, data: TWO_STEP_OFF });
    forgetSessionState(u.id); // sessions without the mfa claim count again at once
    await audit(u.id, "mfa.disable");
    void notify(u, "disabled");
    res.json({ ok: true, enabled: false, required: env.adminMfaRequired });
  } catch (e) { sendError(res, e); }
});

/** New recovery codes (the old ones stop working); takes a current authenticator code. */
mfaMeRoutes.post("/me/mfa/recovery-codes", authLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = codeSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter the 6-digit code from your authenticator app" });
  try {
    adminOnly(req);
    const u = await loadAccount(req.user!.id);
    if (!u) throw new ApiError("Account not found", 404);
    if (!u.totpEnabledAt) throw new ApiError("Two-step sign-in is not on", 409);
    await checkCode(u, body.data.code, false);
    const { codes, hashes } = newRecoveryCodes();
    await prisma.user.update({ where: { id: u.id }, data: { totpRecoveryCodes: hashes } });
    await audit(u.id, "mfa.recovery_codes");
    void notify(u, "recovery_codes_renewed");
    res.json({ ok: true, recoveryCodes: codes });
  } catch (e) { sendError(res, e); }
});
