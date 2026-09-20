import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken } from "../../utils/jwt";
import { dispatchNotifications } from "../../services/notificationDeliveryService";
import pino from "pino";

const logger = pino({ name: "OtpService" });

interface StoredOtp {
  code: string;
  expiresAt: number;
  attempts: number;
  channel: "sms" | "email";
}

// In-memory OTP storage with 10-minute TTL
const otpStore = new Map<string, StoredOtp>();

function normalizeTarget(target: string): string {
  const trimmed = target.trim();
  if (trimmed.includes("@")) {
    return trimmed.toLowerCase();
  }
  // Normalize phone number (keep + and digits)
  return trimmed.replace(/[^\d+]/g, "");
}

/**
 * Generates and dispatches a dynamic 6-digit cryptographic verification code
 */
export async function sendOtp(rawTarget: string, channel?: "sms" | "email") {
  const target = normalizeTarget(rawTarget);
  if (!target || target.length < 5) {
    throw new Error("Invalid phone number or email address");
  }

  const effectiveChannel: "sms" | "email" = channel || (target.includes("@") ? "email" : "sms");
  
  // Secure 6-digit random code (100000 - 999999)
  const code = crypto.randomInt(100000, 999999).toString();
  const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

  otpStore.set(target, {
    code,
    expiresAt,
    attempts: 0,
    channel: effectiveChannel,
  });

  logger.info({ target, channel: effectiveChannel, code }, "🔐 Generated Dynamic Verification OTP");

  // Real multi-channel dispatch via notificationDeliveryService (Twilio SMS or Nodemailer Email)
  try {
    await dispatchNotifications({
      event: "VERIFICATION_CODE",
      channel: effectiveChannel.toUpperCase(),
      phone: effectiveChannel === "sms" ? target : undefined,
      email: effectiveChannel === "email" ? target : undefined,
      code,
    });
  } catch (err: any) {
    logger.error({ err, target }, "Failed to dispatch OTP notification");
  }

  return {
    ok: true,
    target,
    channel: effectiveChannel,
    expiresAt: new Date(expiresAt).toISOString(),
  };
}

/**
 * Validates the 6-digit OTP and authenticates or registers the customer
 */
export async function verifyOtp(rawTarget: string, code: string) {
  const target = normalizeTarget(rawTarget);
  const trimmedCode = code.trim();

  const stored = otpStore.get(target);
  if (!stored) {
    throw new Error("No active verification code found for this destination. Please request a new code.");
  }

  if (Date.now() > stored.expiresAt) {
    otpStore.delete(target);
    throw new Error("Verification code has expired. Please request a new code.");
  }

  if (stored.attempts >= 5) {
    otpStore.delete(target);
    throw new Error("Too many incorrect attempts. Please request a new code.");
  }

  if (stored.code !== trimmedCode) {
    stored.attempts += 1;
    throw new Error("Invalid verification code. Please check your SMS or email.");
  }

  // OTP is valid - remove from store (single use)
  otpStore.delete(target);

  const isEmail = target.includes("@");
  const emailToUse = isEmail ? target.toLowerCase() : `${target.replace(/[^0-9]/g, "")}@phone.malvoya.app`;
  const phoneToUse = isEmail ? undefined : target;

  // Find or create customer
  let user = await prisma.user.findFirst({
    where: {
      OR: [
        { email: { equals: emailToUse, mode: "insensitive" } },
        ...(phoneToUse ? [{ phone: phoneToUse }] : []),
      ],
    },
  });

  if (!user) {
    const dummyPasswordHash = await crypto.randomBytes(32).toString("hex");
    const name = isEmail ? target.split("@")[0] : "Customer";
    user = await prisma.user.create({
      data: {
        name,
        email: emailToUse,
        phone: phoneToUse,
        passwordHash: dummyPasswordHash,
        role: "CUSTOMER",
      },
    });
  }

  const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
  const accessToken = signAccessToken(safeUser);
  const refreshToken = signRefreshToken(safeUser);

  // Store refresh token
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 30);
  await prisma.refreshToken.create({
    data: { token: refreshToken, userId: user.id, expiresAt },
  });

  return {
    ok: true,
    user: safeUser,
    accessToken,
    refreshToken,
  };
}
