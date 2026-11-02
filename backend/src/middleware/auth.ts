import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt";
import { prisma } from "../lib/prisma";
import { localeFromHeader } from "../lib/i18n";
import { publish, subscribe } from "../lib/redis";
import { env } from "../config/env";

export type Role = "CUSTOMER" | "VENDOR" | "COURIER" | "ADMIN";

export interface AuthRequest extends Request {
  /** mfa: this session passed two-step sign-in (authenticator code) */
  user?: { id: number; role: Role; email: string; mfa?: boolean; sid?: number };
}

function readBearer(req: Request): string | null {
  const header = req.headers.authorization;
  return header?.startsWith("Bearer ") ? header.slice(7) : null;
}

/**
 * Per-user facts every signed-in request needs: whether the account is still active, which access tokens a
 * password reset has ended (User.tokensValidAfter), and the stored language. Read from the database at most every
 * 30 seconds per user and instance, so a reset or ban reaches every instance within 30 s (at once on this one).
 */
// twoStep: two-step sign-in is on, so only sessions that passed it (mfa claim) count
// revoked: sign-ins (UserSession ids) ended in the last 20 minutes, so their access tokens stop working at once
type SessionState = { active: boolean; validAfterSec: number; locale: string | null; twoStep: boolean; revoked: Set<number>; at: number };
const STATE_TTL_MS = 30_000;
const MAX_STATES = 20_000;
const states = new Map<number, SessionState>();

async function sessionState(userId: number): Promise<SessionState | null> {
  const hit = states.get(userId);
  if (hit && Date.now() - hit.at < STATE_TTL_MS) return hit;
  try {
    const [u, ended] = await Promise.all([
      prisma.user.findUnique({ where: { id: userId }, select: { isActive: true, tokensValidAfter: true, locale: true, totpEnabledAt: true } }),
      prisma.userSession.findMany({ where: { userId, revokedAt: { gte: new Date(Date.now() - 20 * 60_000) } }, select: { id: true }, take: 200 }),
    ]);
    const state: SessionState = {
      revoked: new Set(ended.map((e) => e.id)),
      active: !!u?.isActive,
      validAfterSec: u?.tokensValidAfter ? Math.floor(u.tokensValidAfter.getTime() / 1000) : 0,
      locale: u?.locale ?? null,
      twoStep: !!u?.totpEnabledAt,
      at: Date.now(),
    };
    if (states.size >= MAX_STATES) states.delete(states.keys().next().value!);
    states.set(userId, state);
    return state;
  } catch {
    return null; // database hiccup: the signed token alone decides, as before
  }
}

/**
 * Called after a password reset, ban or deletion so this instance stops accepting old tokens right away. With
 * REDIS_URL every other instance drops its cached copy too (pub/sub), so the change applies everywhere at once
 * instead of within 30 s.
 */
export function forgetSessionState(userId: number) {
  states.delete(userId);
  publish(SESSION_FORGET_CHANNEL, String(userId));
}
const SESSION_FORGET_CHANNEL = "session-forget";
subscribe(SESSION_FORGET_CHANNEL, (message) => states.delete(Number(message)));

/** The same session checks for a live (socket) connection: active account, not ended, two-step state respected. */
export async function sessionAllows(payload: { id: number; iat: number; mfa?: boolean; sid?: number }) {
  const state = await sessionState(payload.id);
  if (!state) return true; // database hiccup: the signed token alone decides, as for HTTP
  return state.active && payload.iat >= state.validAfterSec && !(state.twoStep && !payload.mfa) && !(payload.sid && state.revoked.has(payload.sid));
}

/** The apps send Accept-Language on every request; the user's language is written only when it changes. */
function rememberLocale(req: Request, userId: number, state: SessionState) {
  const locale = localeFromHeader(req.headers["accept-language"]);
  if (!locale || locale === state.locale) return;
  state.locale = locale;
  prisma.user.updateMany({ where: { id: userId, OR: [{ locale: null }, { locale: { not: locale } }] }, data: { locale } }).catch(() => {});
}

/**
 * While ADMIN_MFA_REQUIRED is on (the production default), an admin session that has not passed two-step sign-in
 * opens only what it needs to turn it on: its own account (GET /me) and /me/mfa. Everything else answers
 * 403 MFA_SETUP_REQUIRED, so the admin panel can send the admin to the set-up page.
 */
const MFA_SETUP_PATHS = /^\/api\/v1\/me(\/mfa(\/[a-z-]+)?)?\/?$/;
export function adminNeedsMfa(user: { role: string; mfa?: boolean }) {
  return env.adminMfaRequired && user.role === "ADMIN" && !user.mfa;
}
const MFA_SETUP_REQUIRED = {
  status: 403, code: "MFA_SETUP_REQUIRED",
  error: "Turn on two-step sign-in (an authenticator app) before using the admin tools.",
};

/** The signed-in user, or null (no token, bad token, ended session or inactive account). */
async function authenticate(req: Request): Promise<{ user: NonNullable<AuthRequest["user"]> } | { error: string; status?: number; code?: string } | null> {
  const token = readBearer(req);
  if (!token) return null;
  let payload: ReturnType<typeof verifyAccessToken>;
  try {
    payload = verifyAccessToken(token);
  } catch {
    return { error: "Invalid or expired token" };
  }
  const state = await sessionState(payload.id);
  if (state) {
    // A token from before two-step sign-in was turned on lacks the mfa claim: ended too, even if issued in the same second
    if (!state.active || payload.iat < state.validAfterSec || (state.twoStep && !payload.mfa) || (payload.sid && state.revoked.has(payload.sid))) {
      return { error: "Your session has ended. Please sign in again." };
    }
    rememberLocale(req, payload.id, state);
  }
  const user = { id: payload.id, role: payload.role as Role, email: payload.email, mfa: payload.mfa, sid: payload.sid };
  if (adminNeedsMfa(user) && !MFA_SETUP_PATHS.test(req.originalUrl.split("?")[0])) return MFA_SETUP_REQUIRED;
  return { user };
}

export async function auth(req: AuthRequest, res: Response, next: NextFunction) {
  const result = await authenticate(req);
  if (!result) return res.status(401).json({ ok: false, error: "Unauthorized" });
  if ("error" in result) return res.status(result.status ?? 401).json({ ok: false, error: result.error, ...(result.code ? { code: result.code } : {}) });
  req.user = result.user;
  next();
}

/** Attaches req.user when a valid token is present, but never rejects the request. */
export async function optionalAuth(req: AuthRequest, _res: Response, next: NextFunction) {
  const result = await authenticate(req);
  if (result && "user" in result) req.user = result.user;
  next();
}

export function requireRole(...roles: Role[]) {
  return (req: AuthRequest, res: Response, next: NextFunction) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ ok: false, error: "Forbidden" });
    }
    next();
  };
}
