import bcrypt from "bcryptjs";
import crypto from "crypto";
import pino from "pino";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { Locale, asLocale } from "../../lib/i18n";
import { emailAvailable, sendNoPasswordNote, sendPasswordResetCode, SignInMethod } from "../../services/notificationDeliveryService";
import { forgetSessionState } from "../../middleware/auth";
import { AuthError, isSyntheticEmail } from "./auth.service";
import { revokeAllSessions } from "./session";

const logger = pino({ name: "password-reset" });

/**
 * Forgot password. Codes live in the one-time-code table (OtpCode) under "pwreset:<email>", hashed like sign-in
 * codes (SHA-256 of target:code), valid 15 minutes with 5 tries, and can never be used to sign in.
 * The answer to "send me a code" is the same whether or not the address has an account, and the work happens
 * after the response, so neither the status nor the timing reveals accounts.
 */
export const RESET_TARGET_PREFIX = "pwreset:";
const RESET_TTL_MS = 15 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const email = z.string().trim().toLowerCase().max(254).regex(EMAIL_RE, "Enter a valid email address");
export const forgotSchema = z.object({ email });
export const resetSchema = z.object({
  email,
  code: z.string().trim().regex(/^\d{6}$/, "Enter the 6-digit code from the email"),
  // Same rules as registration (bcrypt only uses the first 72 bytes)
  password: z.string().min(8, "Password must be at least 8 characters").max(72),
});

const targetOf = (address: string) => `${RESET_TARGET_PREFIX}${address.trim().toLowerCase()}`;
const hashCode = (target: string, code: string) => crypto.createHash("sha256").update(`${target}:${code}`).digest("hex");

/** How an account without a password signs in, for the "no password needed" note. */
function signInMethod(user: { passwordHash: string; googleSub: string | null; phone: string | null }): SignInMethod {
  if (user.googleSub) return "google";
  if (user.passwordHash.startsWith("OTP:")) return "email_code";
  return user.phone ? "phone" : "apple";
}

/** Validates, then answers at once; the code (or the "no password needed" note) is sent in the background. */
export function forgotPassword(address: string, requestLocale: Locale | null) {
  if (isSyntheticEmail(address)) throw new AuthError("Enter a valid email address", 400);
  if (!emailAvailable()) throw new AuthError("Password reset by email is not available yet. Contact support.", 503);
  setImmediate(() => {
    sendResetEmail(address, requestLocale).catch((err) => logger.error({ err: err?.message }, "Password reset email failed"));
  });
}

async function sendResetEmail(address: string, requestLocale: Locale | null) {
  const user = await prisma.user.findFirst({
    where: { email: { equals: address, mode: "insensitive" } },
    select: { id: true, email: true, passwordHash: true, googleSub: true, phone: true, isActive: true, locale: true },
  });
  if (!user || !user.isActive) return;
  const locale = user.locale ? asLocale(user.locale) : requestLocale ?? "en";

  if (!user.passwordHash.startsWith("$2")) {
    await sendNoPasswordNote(user.email, signInMethod(user), locale);
    return;
  }

  const target = targetOf(user.email);
  const existing = await prisma.otpCode.findUnique({ where: { target } });
  if (existing && Date.now() - existing.sentAt.getTime() < RESEND_COOLDOWN_MS) return; // the last code is still on its way

  const code = crypto.randomInt(100000, 1000000).toString();
  const record = { codeHash: hashCode(target, code), attempts: 0, sentAt: new Date(), expiresAt: new Date(Date.now() + RESET_TTL_MS) };
  await prisma.otpCode.upsert({ where: { target }, create: { target, ...record }, update: record });
  const { delivered } = await sendPasswordResetCode(user.email, code, locale);
  if (!delivered) await prisma.otpCode.deleteMany({ where: { target, codeHash: record.codeHash } });
  logger.info({ userId: user.id, delivered }, "Password reset code sent");
}

const WRONG = "The code is wrong or has expired. Request a new one.";

/**
 * Sets the new password. The old password stops working at once, every refresh token is revoked and access
 * tokens issued before now are refused (User.tokensValidAfter), so every other device is signed out.
 */
export async function resetPassword(address: string, code: string, password: string) {
  const target = targetOf(address);
  const stored = await prisma.otpCode.findUnique({ where: { target } });
  if (!stored || Date.now() > stored.expiresAt.getTime()) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError(WRONG, 400);
  }
  if (stored.attempts >= MAX_ATTEMPTS) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("Too many wrong codes. Request a new one.", 400);
  }
  // Use up one attempt before comparing, so parallel requests cannot each get a free guess
  const attempt = await prisma.otpCode.updateMany({
    where: { target, codeHash: stored.codeHash, attempts: { lt: MAX_ATTEMPTS } },
    data: { attempts: { increment: 1 } },
  });
  if (attempt.count !== 1) {
    await prisma.otpCode.deleteMany({ where: { target, codeHash: stored.codeHash } });
    throw new AuthError("Too many wrong codes. Request a new one.", 400);
  }
  const expected = Buffer.from(stored.codeHash, "hex");
  const actual = Buffer.from(hashCode(target, code.trim()), "hex");
  if (!crypto.timingSafeEqual(expected, actual)) {
    throw new AuthError(WRONG, 400);
  }
  // Single use: only the request that deletes the row continues
  const consumed = await prisma.otpCode.deleteMany({ where: { target, codeHash: stored.codeHash } });
  if (consumed.count === 0) throw new AuthError(WRONG, 400);

  const user = await prisma.user.findFirst({
    where: { email: { equals: address, mode: "insensitive" }, isActive: true },
    select: { id: true, passwordHash: true },
  });
  if (!user || !user.passwordHash.startsWith("$2")) throw new AuthError(WRONG, 400);

  const passwordHash = await bcrypt.hash(password, 12);
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash, tokensValidAfter: new Date() } });
  await revokeAllSessions(user.id);
  forgetSessionState(user.id);
  logger.info({ userId: user.id }, "Password reset; all sessions ended");
}
