import crypto from "crypto";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { sendVerificationCode } from "../../services/notificationDeliveryService";
import { issueSession } from "./session";
import { AuthError, assertAgeConfirmed, assertSignupsOpen, assertVerifiedSignInAllowed, phoneToSyntheticEmail } from "./auth.service";
import { bump, clear, hashKey, helsinkiDay } from "../../lib/counters";
import { Locale } from "../../lib/i18n";
import { RESET_TARGET_PREFIX } from "./passwordReset";

const logger = pino({ name: "OtpService" });

// Codes live in Postgres (OtpCode) so every API instance sees the same state and restarts lose nothing.
const OTP_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;
// Guesses per target across codes (2.16): a new code does not give 5 new tries within 15 minutes
const GUESS_WINDOW_MS = 15 * 60_000;

/** SMS cost and toll-fraud limits (2.16): only these country prefixes, a daily total and a daily cap per number. */
function smsAllowedPrefixes() {
  return (process.env.SMS_ALLOWED_PREFIXES ?? "+358").split(",").map((p) => p.trim()).filter((p) => /^\+\d{1,4}$/.test(p));
}
function smsDailyCap() {
  const v = Number(process.env.SMS_DAILY_CAP);
  return Number.isInteger(v) && v >= 0 && process.env.SMS_DAILY_CAP !== "" && process.env.SMS_DAILY_CAP !== undefined ? v : 300;
}
const SMS_PER_NUMBER_PER_DAY = 5;

export function smsLimits() {
  return { allowedPrefixes: smsAllowedPrefixes(), dailyCap: smsDailyCap(), perNumberPerDay: SMS_PER_NUMBER_PER_DAY };
}

function normalizeTarget(target: string): string {
  const trimmed = target.trim();
  if (trimmed.includes("@")) return trimmed.toLowerCase();
  return trimmed.replace(/[^\d+]/g, "");
}

function hashCode(target: string, code: string) {
  return crypto.createHash("sha256").update(`${target}:${code}`).digest("hex");
}

/** Mask for logs: never log full phone numbers, emails or codes. */
function maskTarget(target: string) {
  return target.includes("@") ? target.replace(/^(.).*(@.*)$/, "$1***$2") : `***${target.slice(-3)}`;
}

export async function sendOtp(rawTarget: string, channel?: "sms" | "email", locale: Locale = "en") {
  const target = normalizeTarget(rawTarget);
  const isEmail = target.includes("@");
  if (isEmail ? !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(target) : !/^\+?\d{7,15}$/.test(target)) {
    throw new AuthError("Invalid phone number or email address", 400);
  }

  const existing = await prisma.otpCode.findUnique({ where: { target } });
  if (existing && Date.now() - existing.sentAt.getTime() < RESEND_COOLDOWN_MS) {
    throw new AuthError("Please wait a minute before requesting a new code", 429);
  }

  const effectiveChannel: "sms" | "email" = channel || (isEmail ? "email" : "sms");
  if (effectiveChannel === "sms" && !isEmail) {
    const prefixes = smsAllowedPrefixes();
    if (!target.startsWith("+") || !prefixes.some((p) => target.startsWith(p))) {
      throw new AuthError(`Text messages can only be sent to ${prefixes.join(", ")} numbers. Use email or Google instead.`, 400, "SMS_COUNTRY_NOT_ALLOWED");
    }
    const day = helsinkiDay();
    const total = await bump(`sms-day:${day}`, 26 * 3600_000);
    if (total.count > smsDailyCap()) {
      logger.warn({ cap: smsDailyCap() }, "Daily SMS cap reached");
      throw new AuthError("Text messages are paused, use email or Google", 503, "SMS_PAUSED");
    }
    const perNumber = await bump(`sms-num:${hashKey(target)}:${day}`, 26 * 3600_000);
    if (perNumber.count > SMS_PER_NUMBER_PER_DAY) {
      throw new AuthError("Too many codes to this number today. Use email or Google, or try again tomorrow.", 429, "SMS_NUMBER_LIMIT");
    }
  }
  const code = crypto.randomInt(100000, 1000000).toString();
  const record = { codeHash: hashCode(target, code), attempts: 0, sentAt: new Date(), expiresAt: new Date(Date.now() + OTP_TTL_MS) };
  await prisma.otpCode.upsert({ where: { target }, create: { target, ...record }, update: record });

  const { delivered } = await sendVerificationCode(target, effectiveChannel, code, locale);
  logger.info({ target: maskTarget(target), channel: effectiveChannel, delivered }, "Verification code dispatched");
  if (!delivered) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("We could not send a verification code right now. Please try again later.", 503);
  }

  return { ok: true, channel: effectiveChannel, expiresAt: new Date(Date.now() + OTP_TTL_MS).toISOString() };
}

export async function verifyOtp(rawTarget: string, code: string, opts: { ageConfirmed?: boolean } = {}) {
  const target = normalizeTarget(rawTarget);
  // Password-reset codes share the table but can never be used to sign in
  if (target.startsWith(RESET_TARGET_PREFIX)) throw new AuthError("The code has expired. Please request a new one.", 401);
  const isEmailTarget = target.includes("@");
  const accountEmail = isEmailTarget ? target : phoneToSyntheticEmail(target);
  const accountPhone = isEmailTarget ? undefined : target;
  // A code that would create a new account needs "I am 18 or older" first; checked before the code is touched, so the
  // app can ask and send the same code again (2.16)
  const existingAccount = await prisma.user.findFirst({
    where: { OR: [{ email: { equals: accountEmail, mode: "insensitive" } }, ...(accountPhone ? [{ phone: accountPhone }] : [])] },
    select: { id: true },
  });
  if (!existingAccount) {
    assertAgeConfirmed(opts.ageConfirmed);
    await assertSignupsOpen();
  }
  const stored = await prisma.otpCode.findUnique({ where: { target } });
  if (!stored || Date.now() > stored.expiresAt.getTime()) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("The code has expired. Please request a new one.", 401);
  }
  if (stored.attempts >= MAX_ATTEMPTS) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("Too many incorrect attempts. Please request a new code.", 429);
  }

  // Guesses across codes for this target: 5 per 15 minutes, however many codes were requested
  const guesses = await bump(`otp-guess:${hashKey(target)}`, GUESS_WINDOW_MS);
  if (guesses.count > MAX_ATTEMPTS) throw new AuthError("Too many incorrect attempts. Please try again in 15 minutes.", 429);
  // Use up one attempt before comparing, so parallel requests cannot each get a free guess
  const attempt = await prisma.otpCode.updateMany({
    where: { target, codeHash: stored.codeHash, attempts: { lt: MAX_ATTEMPTS } },
    data: { attempts: { increment: 1 } },
  });
  if (attempt.count !== 1) {
    await prisma.otpCode.deleteMany({ where: { target, codeHash: stored.codeHash } });
    throw new AuthError("Too many incorrect attempts. Please request a new code.", 429);
  }
  const expected = Buffer.from(stored.codeHash, "hex");
  const actual = Buffer.from(hashCode(target, code.trim()), "hex");
  if (!crypto.timingSafeEqual(expected, actual)) {
    throw new AuthError("Invalid verification code", 401);
  }
  // Single use: only the request that deletes the row may continue (guards against parallel replays)
  const consumed = await prisma.otpCode.deleteMany({ where: { target, codeHash: stored.codeHash } });
  if (consumed.count === 0) throw new AuthError("The code has already been used", 401);
  await clear(`otp-guess:${hashKey(target)}`);

  const isEmail = target.includes("@");
  const email = isEmail ? target : phoneToSyntheticEmail(target);
  const phone = isEmail ? undefined : target;

  let user = await prisma.user.findFirst({
    where: { OR: [{ email: { equals: email, mode: "insensitive" } }, ...(phone ? [{ phone }] : [])] },
  });
  if (user) {
    assertVerifiedSignInAllowed(user);
  } else {
    user = await prisma.user.create({
      data: {
        name: isEmail ? target.split("@")[0] : "Customer",
        email,
        phone,
        passwordHash: `OTP:${crypto.randomBytes(24).toString("hex")}`,
        role: "CUSTOMER",
        ageConfirmedAt: new Date(),
      },
    });
  }
  if (!user.isActive) throw new AuthError("This account is disabled", 403);

  return { ok: true, ...(await issueSession(user)) };
}

// Drop expired codes regularly (cheap: indexed on expiresAt)
setInterval(() => {
  prisma.otpCode.deleteMany({ where: { expiresAt: { lt: new Date() } } }).catch(() => {});
}, 10 * 60 * 1000).unref();
