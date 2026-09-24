import crypto from "crypto";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { sendVerificationCode } from "../../services/notificationDeliveryService";
import { issueSession } from "./session";
import { AuthError, phoneToSyntheticEmail } from "./auth.service";

const logger = pino({ name: "OtpService" });

// Codes live in Postgres (OtpCode) so every API instance sees the same state and restarts lose nothing.
const OTP_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

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

export async function sendOtp(rawTarget: string, channel?: "sms" | "email") {
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
  const code = crypto.randomInt(100000, 1000000).toString();
  const record = { codeHash: hashCode(target, code), attempts: 0, sentAt: new Date(), expiresAt: new Date(Date.now() + OTP_TTL_MS) };
  await prisma.otpCode.upsert({ where: { target }, create: { target, ...record }, update: record });

  const { delivered } = await sendVerificationCode(target, effectiveChannel, code);
  logger.info({ target: maskTarget(target), channel: effectiveChannel, delivered }, "Verification code dispatched");
  if (!delivered) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("We could not send a verification code right now. Please try again later.", 503);
  }

  return { ok: true, channel: effectiveChannel, expiresAt: new Date(Date.now() + OTP_TTL_MS).toISOString() };
}

export async function verifyOtp(rawTarget: string, code: string) {
  const target = normalizeTarget(rawTarget);
  const stored = await prisma.otpCode.findUnique({ where: { target } });
  if (!stored || Date.now() > stored.expiresAt.getTime()) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("The code has expired. Please request a new one.", 401);
  }
  if (stored.attempts >= MAX_ATTEMPTS) {
    await prisma.otpCode.deleteMany({ where: { target } });
    throw new AuthError("Too many incorrect attempts. Please request a new code.", 429);
  }

  const expected = Buffer.from(stored.codeHash, "hex");
  const actual = Buffer.from(hashCode(target, code.trim()), "hex");
  if (!crypto.timingSafeEqual(expected, actual)) {
    await prisma.otpCode.update({ where: { target }, data: { attempts: { increment: 1 } } });
    throw new AuthError("Invalid verification code", 401);
  }
  // Single use: only the request that deletes the row may continue (guards against parallel replays)
  const consumed = await prisma.otpCode.deleteMany({ where: { target, codeHash: stored.codeHash } });
  if (consumed.count === 0) throw new AuthError("The code has already been used", 401);

  const isEmail = target.includes("@");
  const email = isEmail ? target : phoneToSyntheticEmail(target);
  const phone = isEmail ? undefined : target;

  let user = await prisma.user.findFirst({
    where: { OR: [{ email: { equals: email, mode: "insensitive" } }, ...(phone ? [{ phone }] : [])] },
  });
  if (!user) {
    user = await prisma.user.create({
      data: {
        name: isEmail ? target.split("@")[0] : "Customer",
        email,
        phone,
        passwordHash: `OTP:${crypto.randomBytes(24).toString("hex")}`,
        role: "CUSTOMER",
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
