import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken } from "../../utils/jwt";

const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export interface SessionUser {
  id: number;
  name: string;
  email: string;
  role: string;
}

/** Refresh tokens are stored hashed so a database leak does not leak live sessions. */
export function hashToken(token: string): string {
  return crypto.createHash("sha256").update(token).digest("hex");
}

/** Single place where access + refresh tokens are issued for every login method. */
export async function issueSession(user: SessionUser) {
  const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
  const accessToken = signAccessToken(safeUser);
  const refreshToken = signRefreshToken(user.id);

  await prisma.refreshToken.create({
    data: { token: hashToken(refreshToken), userId: user.id, expiresAt: new Date(Date.now() + REFRESH_TTL_MS) },
  });
  // Opportunistic cleanup of this user's expired sessions
  await prisma.refreshToken.deleteMany({ where: { userId: user.id, expiresAt: { lt: new Date() } } });

  return { user: safeUser, accessToken, refreshToken };
}

export async function revokeAllSessions(userId: number) {
  await prisma.refreshToken.deleteMany({ where: { userId } });
}
