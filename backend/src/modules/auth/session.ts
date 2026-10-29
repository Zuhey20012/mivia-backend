import crypto from "crypto";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken, signMfaToken } from "../../utils/jwt";
import { currentRequestMeta } from "../../lib/requestContext";
import { deviceName } from "../../lib/userAgent";
import { localeOfUser } from "../../lib/i18n";
import { sendNewSignInEmail } from "../../services/notificationDeliveryService";

const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const logger = pino({ name: "session" });

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

/** Partners and admins hear about every new sign-in (2.16): their accounts move money. Customers do not. */
const SIGN_IN_EMAIL_ROLES = new Set(["VENDOR", "COURIER", "ADMIN"]);

/**
 * Single place where access + refresh tokens are issued for every login method. An account with two-step sign-in
 * on (admins since 2.13.0; stores and couriers may turn it on since 2.16.0) gets no tokens from a first step: it gets
 * a 5-minute challenge token, which POST /auth/login/mfa exchanges for a session together with an authenticator or
 * recovery code. `mfa: true` marks a session that passed that second step.
 *
 * Every fresh sign-in starts a UserSession (one device, a refresh-token family); `sessionId` continues one (refresh).
 */
export async function issueSession(user: SessionUser, opts: { mfa?: boolean; sessionId?: number } = {}): Promise<Session | MfaChallenge> {
  if (!opts.mfa && !opts.sessionId) {
    const row = await prisma.user.findUnique({ where: { id: user.id }, select: { totpEnabledAt: true } });
    if (row?.totpEnabledAt) return { mfaRequired: true, mfaToken: signMfaToken(user.id) };
  }
  return issueTokens(user, !!opts.mfa, opts.sessionId);
}

export type Session = Awaited<ReturnType<typeof issueTokens>>;

async function issueTokens(user: SessionUser, mfa: boolean, existingSessionId?: number) {
  const safeUser = {
    id: user.id, name: user.name, email: user.email, role: user.role, googleLinked: Boolean(user.googleSub),
    hasPassword: hasPassword(user.passwordHash),
  };
  let sessionId = existingSessionId;
  if (!sessionId) {
    const device = deviceName(currentRequestMeta().userAgent);
    const created = await prisma.userSession.create({ data: { userId: user.id, device, mfa } });
    sessionId = created.id;
    if (SIGN_IN_EMAIL_ROLES.has(user.role)) {
      localeOfUser(user.id).then((locale) => sendNewSignInEmail(user.email, device, created.createdAt, locale))
        .catch((e) => logger.warn({ err: e?.message }, "Sign-in email not sent"));
    }
  } else {
    await prisma.userSession.update({ where: { id: sessionId }, data: { lastUsedAt: new Date() } }).catch(() => {});
  }
  const accessToken = signAccessToken({ ...safeUser, mfa, sid: sessionId });
  const refreshToken = signRefreshToken(user.id, mfa);

  await prisma.refreshToken.create({
    data: { token: hashToken(refreshToken), userId: user.id, sessionId, expiresAt: new Date(Date.now() + REFRESH_TTL_MS) },
  });
  // Opportunistic cleanup of this user's expired tokens and long-dead sessions
  await prisma.refreshToken.deleteMany({ where: { userId: user.id, expiresAt: { lt: new Date() } } });
  await prisma.userSession.deleteMany({
    where: { userId: user.id, OR: [{ revokedAt: { lt: new Date(Date.now() - 86_400_000) } }, { lastUsedAt: { lt: new Date(Date.now() - REFRESH_TTL_MS - 86_400_000) } }] },
  }).catch(() => {});

  return { user: safeUser, accessToken, refreshToken };
}

/** Ends every sign-in of the user (password change/reset, ban, deletion, two-step turned on). */
export async function revokeAllSessions(userId: number) {
  await prisma.refreshToken.deleteMany({ where: { userId } });
  await prisma.userSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
}

/** Ends one sign-in (device): its refresh tokens go, and its access tokens are refused from now on (auth middleware). */
export async function revokeSession(userId: number, sessionId: number) {
  const r = await prisma.userSession.updateMany({ where: { id: sessionId, userId, revokedAt: null }, data: { revokedAt: new Date() } });
  await prisma.refreshToken.deleteMany({ where: { sessionId, userId } });
  return r.count > 0;
}
