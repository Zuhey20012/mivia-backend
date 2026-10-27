import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken, signMfaToken } from "../../utils/jwt";

const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export interface SessionUser {
  id: number;
  name: string;
  email: string;
  role: string;
  googleSub?: string | null;
  /** Only used to tell the app whether the account has a password (bcrypt hash); never sent anywhere. */
  passwordHash?: string | null;
}

/** Accounts made by /register (or that set one) sign in with a password; Google/phone/code accounts have none. */
export const hasPassword = (passwordHash?: string | null) => !!passwordHash && passwordHash.startsWith("$2");

/** Refresh tokens are stored hashed so a database leak does not leak live sessions. */
export function hashToken(token: string): string {
  return crypto.createHash("sha256").update(token).digest("hex");
}

/** What a first step (password, email code, Google, phone, Apple) returns when the account also needs its authenticator code. */
export interface MfaChallenge {
  mfaRequired: true;
  mfaToken: string;
}

export const isMfaChallenge = (s: object): s is MfaChallenge => (s as MfaChallenge).mfaRequired === true;

/**
 * Single place where access + refresh tokens are issued for every login method. An account with two-step sign-in
 * on (admins, since 2.13.0) gets no tokens from a first step: it gets a 5-minute challenge token, which
 * POST /auth/login/mfa exchanges for a session together with an authenticator or recovery code. `mfa: true` marks
 * a session that passed that second step (the code check itself, a refresh of such a session, a signed-in change).
 */
export async function issueSession(user: SessionUser, opts: { mfa?: boolean } = {}): Promise<Session | MfaChallenge> {
  if (!opts.mfa && user.role === "ADMIN") {
    const row = await prisma.user.findUnique({ where: { id: user.id }, select: { totpEnabledAt: true } });
    if (row?.totpEnabledAt) return { mfaRequired: true, mfaToken: signMfaToken(user.id) };
  }
  return issueTokens(user, !!opts.mfa);
}

export type Session = Awaited<ReturnType<typeof issueTokens>>;

async function issueTokens(user: SessionUser, mfa: boolean) {
  const safeUser = {
    id: user.id, name: user.name, email: user.email, role: user.role, googleLinked: Boolean(user.googleSub),
    hasPassword: hasPassword(user.passwordHash),
  };
  const accessToken = signAccessToken({ ...safeUser, mfa });
  const refreshToken = signRefreshToken(user.id, mfa);

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
