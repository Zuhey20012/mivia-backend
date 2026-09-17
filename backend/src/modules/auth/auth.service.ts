import bcrypt from "bcryptjs";
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken, verifyRefreshToken } from "../../utils/jwt";
import { RegisterInput, LoginInput } from "./auth.schema";
import { env } from "../../config/env";

export async function registerUser(input: RegisterInput) {
  const identifier = input.email.trim();
  const isPhone = !identifier.includes('@') && /^[0-9+ ]+$/.test(identifier);
  const emailToUse = isPhone ? `${identifier.replace(/[^0-9]/g, '')}@phone.malvoya.app` : identifier.toLowerCase();
  const phoneToUse = isPhone ? identifier : input.phone;

  const existing = await prisma.user.findFirst({
    where: {
      OR: [
        { email: { equals: emailToUse, mode: "insensitive" } },
        ...(phoneToUse ? [{ phone: phoneToUse }] : []),
      ]
    }
  });

  if (existing) {
    if (input.role && input.role !== "CUSTOMER") {
      await prisma.user.update({
        where: { id: existing.id },
        data: { role: input.role }
      });
    }
    const safeUser = { id: existing.id, name: existing.name, email: existing.email, role: input.role || existing.role };
    const tokens = generateTokens(safeUser);
    await saveRefreshToken(existing.id, tokens.refreshToken);
    return { user: safeUser, ...tokens };
  }

  const passwordHash = await bcrypt.hash(input.password, 12);
  const user = await prisma.user.create({
    data: { name: input.name, email: emailToUse, phone: phoneToUse, passwordHash, role: input.role },
    select: { id: true, name: true, email: true, role: true, createdAt: true },
  });

  const tokens = generateTokens(user);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user, ...tokens };
}

export async function loginUser(input: LoginInput) {
  const identifier = input.email.trim();
  const user = await prisma.user.findFirst({
    where: {
      OR: [
        { email: { equals: identifier, mode: "insensitive" } },
        { phone: identifier },
        { phone: identifier.replace(/[^0-9+]/g, '') },
        { email: `${identifier.replace(/[^0-9]/g, '')}@phone.malvoya.app` },
      ]
    }
  });
  if (!user) throw new Error("Invalid credentials");

  const valid = await bcrypt.compare(input.password, user.passwordHash);
  if (!valid) throw new Error("Invalid credentials");

  const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
  const tokens = generateTokens(safeUser);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user: safeUser, ...tokens };
}

export async function refreshTokens(refreshToken: string) {
  const payload = verifyRefreshToken(refreshToken);
  const stored = await prisma.refreshToken.findUnique({ where: { token: refreshToken } });
  if (!stored || stored.expiresAt < new Date()) throw new Error("Refresh token expired or invalid");

  await prisma.refreshToken.delete({ where: { token: refreshToken } });

  const user = await prisma.user.findUniqueOrThrow({
    where: { id: stored.userId },
    select: { id: true, name: true, email: true, role: true },
  });
  const tokens = generateTokens(user);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user, ...tokens };
}

export async function logoutUser(refreshToken: string) {
  await prisma.refreshToken.deleteMany({ where: { token: refreshToken } });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function generateTokens(user: { id: number; email: string; role: string }) {
  const accessToken  = signAccessToken({ id: user.id, email: user.email, role: user.role });
  const refreshToken = signRefreshToken({ id: user.id });
  return { accessToken, refreshToken };
}

async function saveRefreshToken(userId: number, token: string) {
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
  await prisma.refreshToken.create({ data: { token, userId, expiresAt } });
}
