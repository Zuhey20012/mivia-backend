import crypto from "crypto";
import bcrypt from "bcryptjs";
import { Router, Response, NextFunction } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { auth, AuthRequest, forgetSessionState } from "../../middleware/auth";
import { authLimiter } from "../../middleware/rateLimiter";
import { hasPassword, revokeSession } from "./session";
import { checkAuthenticatorCode } from "./mfa";

/**
 * Signed-in devices and re-authentication (since 2.16.0).
 *  - GET /me/sessions: every sign-in (refresh-token family) that is still open, with a readable device name.
 *  - DELETE /me/sessions/:id ends one; DELETE /me/sessions ends every other one (this device stays signed in).
 *  - POST /me/reauth {password} | {code}: the password again (or an authenticator code, or a one-time sign-in code
 *    for accounts without a password) opens sensitive actions for 10 minutes on this device: payout links.
 */
const REAUTH_MS = 10 * 60_000;
const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export const accountSecurityRoutes = Router();

accountSecurityRoutes.get("/me/sessions", auth, async (req: AuthRequest, res: Response) => {
  try {
    const rows = await prisma.userSession.findMany({
      where: { userId: req.user!.id, revokedAt: null, lastUsedAt: { gte: new Date(Date.now() - REFRESH_TTL_MS) } },
      orderBy: { lastUsedAt: "desc" },
      take: 50,
    });
    res.json({
      ok: true,
      sessions: rows.map((r) => ({ id: r.id, device: r.device ?? "Unknown device", createdAt: r.createdAt, lastUsedAt: r.lastUsedAt, current: r.id === req.user!.sid })),
    });
  } catch (e) { sendError(res, e); }
});

accountSecurityRoutes.delete("/me/sessions/:id(\\d+)", auth, async (req: AuthRequest, res: Response) => {
  try {
    const id = positiveId(req.params.id)!;
    if (!(await revokeSession(req.user!.id, id))) throw new ApiError("Session not found", 404);
    forgetSessionState(req.user!.id);
    res.json({ ok: true, ended: 1, current: id === req.user!.sid });
  } catch (e) { sendError(res, e); }
});

/** Signs out every other device; the current one stays signed in (nothing is set for it). */
accountSecurityRoutes.delete("/me/sessions", auth, async (req: AuthRequest, res: Response) => {
  try {
    const others = await prisma.userSession.findMany({
      where: { userId: req.user!.id, revokedAt: null, ...(req.user!.sid ? { id: { not: req.user!.sid } } : {}) },
      select: { id: true },
      take: 500,
    });
    for (const o of others) await revokeSession(req.user!.id, o.id);
    // Tokens from before 2.16 have no sign-in family: they are ended by their refresh tokens going
    if (req.user!.sid) await prisma.refreshToken.deleteMany({ where: { userId: req.user!.id, sessionId: null } });
    forgetSessionState(req.user!.id);
    res.json({ ok: true, ended: others.length });
  } catch (e) { sendError(res, e); }
});

const reauthSchema = z.object({
  password: z.string().min(1).max(72).optional(),
  code: z.string().trim().min(6).max(20).optional(),
}).refine((d) => !!d.password || !!d.code, { message: "Enter your password or a code" });

const otpHash = (target: string, code: string) => crypto.createHash("sha256").update(`${target}:${code}`).digest("hex");

/** A one-time sign-in code (POST /auth/otp/send) for the account's own email address or phone number. */
async function consumeSignInCode(user: { email: string; phone: string | null }, code: string) {
  const targets = [user.email.toLowerCase(), ...(user.phone ? [user.phone.replace(/[^\d+]/g, "")] : [])];
  for (const target of targets) {
    const stored = await prisma.otpCode.findUnique({ where: { target } });
    if (!stored || stored.expiresAt < new Date() || stored.attempts >= 5) continue;
    const attempt = await prisma.otpCode.updateMany({ where: { target, codeHash: stored.codeHash, attempts: { lt: 5 } }, data: { attempts: { increment: 1 } } });
    if (attempt.count !== 1) continue;
    const ok = crypto.timingSafeEqual(Buffer.from(stored.codeHash, "hex"), Buffer.from(otpHash(target, code.trim()), "hex"));
    if (ok && (await prisma.otpCode.deleteMany({ where: { target, codeHash: stored.codeHash } })).count === 1) return true;
  }
  return false;
}

accountSecurityRoutes.post("/me/reauth", authLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = reauthSchema.safeParse(req.body ?? {});
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter your password or a code" });
  try {
    if (!req.user!.sid) throw new ApiError("Please sign in again first", 401);
    const user = await prisma.user.findUnique({ where: { id: req.user!.id }, select: { passwordHash: true, email: true, phone: true, totpEnabledAt: true } });
    if (!user) throw new ApiError("Account not found", 404);
    let ok = false;
    if (body.data.password) {
      ok = hasPassword(user.passwordHash) && (await bcrypt.compare(body.data.password, user.passwordHash));
      if (!ok) throw new ApiError("The password is wrong", 400);
    } else {
      const code = body.data.code!;
      ok = (user.totpEnabledAt && /^\d{6}$/.test(code) && (await checkAuthenticatorCode(req.user!.id, code).catch((e) => { throw e; })))
        || (await consumeSignInCode(user, code));
      if (!ok) throw new ApiError("That code is not right", 400);
    }
    const reauthUntil = new Date(Date.now() + REAUTH_MS);
    const updated = await prisma.userSession.updateMany({ where: { id: req.user!.sid, userId: req.user!.id, revokedAt: null }, data: { reauthUntil } });
    if (!updated.count) throw new ApiError("Please sign in again first", 401);
    res.json({ ok: true, reauthUntil });
  } catch (e) { sendError(res, e); }
});

/**
 * Sensitive partner actions (payout links): the password again within 10 minutes on this device, or a session that
 * passed two-step sign-in. Otherwise 403 { code: "REAUTH_REQUIRED" }.
 */
export async function requireRecentAuth(req: AuthRequest, res: Response, next: NextFunction) {
  try {
    if (req.user?.mfa) return next();
    const sid = req.user?.sid;
    const session = sid ? await prisma.userSession.findFirst({ where: { id: sid, userId: req.user!.id, revokedAt: null }, select: { reauthUntil: true } }) : null;
    if (session?.reauthUntil && session.reauthUntil > new Date()) return next();
    return res.status(403).json({ ok: false, code: "REAUTH_REQUIRED", error: "Enter your password again to open payout settings." });
  } catch (e) { sendError(res, e); }
}
