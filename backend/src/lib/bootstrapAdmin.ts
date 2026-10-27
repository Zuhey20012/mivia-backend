import bcrypt from "bcryptjs";
import pino from "pino";
import { prisma } from "./prisma";
import { env } from "../config/env";

const logger = pino({ name: "admin-bootstrap" });

const mask = (email: string) => email.replace(/^(.).*(@.*)$/, "$1***$2");

/**
 * Creates (or resets) the admin from SEED_ADMIN_EMAIL / SEED_ADMIN_PASSWORD at start-up: the same settings
 * as `prisma db seed`, for when Render's Shell is not usable. It does nothing while the stored password already
 * matches, so restarts are harmless; a reset ends the account's other sessions. Remove both settings on Render
 * once you have signed in. The password is never logged.
 */
export async function bootstrapAdmin() {
  const email = process.env.SEED_ADMIN_EMAIL?.trim().toLowerCase();
  const password = process.env.SEED_ADMIN_PASSWORD ?? "";
  if (!email && !password) return { action: "off" as const };
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 14) {
    logger.error("SEED_ADMIN_EMAIL needs a valid address and SEED_ADMIN_PASSWORD at least 14 characters; no admin was created");
    return { action: "invalid" as const };
  }

  const existing = await prisma.user.findUnique({ where: { email }, select: { id: true, role: true, isActive: true, passwordHash: true } });
  const remind = () => {
    if (env.isProduction) logger.warn("SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD are still set on this service: remove them now that the admin exists");
  };
  if (existing?.role === "ADMIN" && existing.isActive && existing.passwordHash.startsWith("$2") && (await bcrypt.compare(password, existing.passwordHash))) {
    logger.info({ email: mask(email) }, "Admin account already set up");
    remind();
    return { action: "unchanged" as const, userId: existing.id };
  }

  if (existing && existing.role !== "ADMIN") {
    logger.warn({ email: mask(email), previousRole: existing.role }, "An existing account with this email is being made the admin");
  }
  const passwordHash = await bcrypt.hash(password, 12);
  const user = await prisma.$transaction(async (tx) => {
    const u = await tx.user.upsert({
      where: { email },
      // A reset: sessions issued before now stop working
      update: { role: "ADMIN", passwordHash, isActive: true, tokensValidAfter: new Date() },
      create: { name: "Malvoya Admin", email, passwordHash, role: "ADMIN" },
      select: { id: true },
    });
    if (existing) await tx.refreshToken.deleteMany({ where: { userId: u.id } });
    return u;
  });
  logger.info({ email: mask(email) }, existing ? "Admin password reset from SEED_ADMIN_* settings" : "Admin account created from SEED_ADMIN_* settings");
  remind();
  return { action: existing ? ("reset" as const) : ("created" as const), userId: user.id };
}
