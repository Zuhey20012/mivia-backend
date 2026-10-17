import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt";
import { prisma } from "../lib/prisma";
import { localeFromHeader } from "../lib/i18n";

export type Role = "CUSTOMER" | "VENDOR" | "COURIER" | "ADMIN";

export interface AuthRequest extends Request {
  user?: { id: number; role: Role; email: string };
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
type SessionState = { active: boolean; validAfterSec: number; locale: string | null; at: number };
const STATE_TTL_MS = 30_000;
const MAX_STATES = 20_000;
const states = new Map<number, SessionState>();

async function sessionState(userId: number): Promise<SessionState | null> {
  const hit = states.get(userId);
  if (hit && Date.now() - hit.at < STATE_TTL_MS) return hit;
  try {
    const u = await prisma.user.findUnique({ where: { id: userId }, select: { isActive: true, tokensValidAfter: true, locale: true } });
    const state: SessionState = {
      active: !!u?.isActive,
      validAfterSec: u?.tokensValidAfter ? Math.floor(u.tokensValidAfter.getTime() / 1000) : 0,
      locale: u?.locale ?? null,
      at: Date.now(),
    };
    if (states.size >= MAX_STATES) states.delete(states.keys().next().value!);
    states.set(userId, state);
    return state;
  } catch {
    return null; // database hiccup: the signed token alone decides, as before
  }
}

/** Called after a password reset, ban or deletion so this instance stops accepting old tokens right away. */
export function forgetSessionState(userId: number) {
  states.delete(userId);
}

/** The apps send Accept-Language on every request; the user's language is written only when it changes. */
function rememberLocale(req: Request, userId: number, state: SessionState) {
  const locale = localeFromHeader(req.headers["accept-language"]);
  if (!locale || locale === state.locale) return;
  state.locale = locale;
  prisma.user.updateMany({ where: { id: userId, OR: [{ locale: null }, { locale: { not: locale } }] }, data: { locale } }).catch(() => {});
}

/** The signed-in user, or null (no token, bad token, ended session or inactive account). */
async function authenticate(req: Request): Promise<{ user: NonNullable<AuthRequest["user"]> } | { error: string } | null> {
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
    if (!state.active || payload.iat < state.validAfterSec) return { error: "Your session has ended. Please sign in again." };
    rememberLocale(req, payload.id, state);
  }
  return { user: { id: payload.id, role: payload.role as Role, email: payload.email } };
}

export async function auth(req: AuthRequest, res: Response, next: NextFunction) {
  const result = await authenticate(req);
  if (!result) return res.status(401).json({ ok: false, error: "Unauthorized" });
  if ("error" in result) return res.status(401).json({ ok: false, error: result.error });
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
