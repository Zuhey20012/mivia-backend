import { Request, Response } from "express";
import { z } from "zod";
import { registerSchema, loginSchema, refreshSchema } from "./auth.schema";
import * as authService from "./auth.service";
import * as socialService from "./social.service";
import { sendOtp, verifyOtp } from "./otp.service";
import { AuthRequest } from "../../middleware/auth";
import { localeFromHeader } from "../../lib/i18n";
import { forgotPassword, resetPassword, forgotSchema, resetSchema } from "./passwordReset";
import { acceptContext } from "../legal/agreements";

/** AuthErrors carry a safe message + status; anything else is logged and hidden. */
function sendError(res: Response, e: unknown, fallbackStatus = 500) {
  if (e instanceof authService.AuthError) return res.status(e.status).json({ ok: false, error: e.message, ...(e.code ? { code: e.code } : {}) });
  console.error(e);
  return res.status(fallbackStatus).json({ ok: false, error: fallbackStatus === 401 ? "Authentication failed" : "Something went wrong" });
}

export async function register(req: Request, res: Response) {
  const result = registerSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, error: result.error.issues[0]?.message, errors: result.error.flatten() });
  try {
    const data = await authService.registerUser(result.data, acceptContext(req));
    res.status(201).json({ ok: true, ...data });
  } catch (e) {
    sendError(res, e);
  }
}

export async function login(req: Request, res: Response) {
  const result = loginSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.loginUser(result.data);
    res.json({ ok: true, ...data });
  } catch (e) {
    sendError(res, e);
  }
}

export async function refresh(req: Request, res: Response) {
  const result = refreshSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.refreshTokens(result.data.refreshToken);
    res.json({ ok: true, ...data });
  } catch (e) {
    sendError(res, e, 401);
  }
}

export async function logout(req: Request, res: Response) {
  const { refreshToken } = req.body ?? {};
  if (typeof refreshToken === "string" && refreshToken) await authService.logoutUser(refreshToken);
  res.json({ ok: true });
}

const SIGNUP_ROLES = ["CUSTOMER", "VENDOR", "COURIER"] as const;

function tokenHandler(field: "idToken" | "firebaseToken", login: (token: string, role: socialService.SignupRole, opts: socialService.SignupOptions) => Promise<unknown>) {
  return async (req: Request, res: Response) => {
    const token = req.body?.[field];
    if (typeof token !== "string" || !token) return res.status(400).json({ ok: false, error: `${field} is required` });
    const role = SIGNUP_ROLES.includes(req.body?.role) ? (req.body.role as socialService.SignupRole) : "CUSTOMER";
    try {
      const data = await login(token, role, { ageConfirmed: req.body?.ageConfirmed === true });
      res.json({ ok: true, ...(data as object) });
    } catch (e) {
      sendError(res, e, 401);
    }
  };
}

export const googleLogin = tokenHandler("idToken", socialService.loginWithGoogle);

export async function googleLink(req: AuthRequest, res: Response) {
  const idToken = req.body?.idToken;
  if (typeof idToken !== "string" || !idToken) return res.status(400).json({ ok: false, error: "idToken is required" });
  try {
    res.json({ ok: true, ...(await socialService.linkGoogle(req.user!.id, idToken)) });
  } catch (e) {
    sendError(res, e);
  }
}

export async function googleUnlink(req: AuthRequest, res: Response) {
  try {
    res.json({ ok: true, ...(await socialService.unlinkGoogle(req.user!.id)) });
  } catch (e) {
    sendError(res, e);
  }
}
export const phoneLogin  = tokenHandler("firebaseToken", socialService.loginWithPhone);
/** Sign in with Apple: { idToken, role?, name? } (name only for new accounts, trimmed, at most 100 characters). */
export async function appleLogin(req: Request, res: Response) {
  const token = req.body?.idToken;
  if (typeof token !== "string" || !token) return res.status(400).json({ ok: false, error: "idToken is required" });
  const rawName = req.body?.name;
  if (rawName !== undefined && rawName !== null && (typeof rawName !== "string" || rawName.trim().length > 100)) {
    return res.status(400).json({ ok: false, error: "name must be text of at most 100 characters" });
  }
  const role = SIGNUP_ROLES.includes(req.body?.role) ? (req.body.role as socialService.SignupRole) : "CUSTOMER";
  try {
    res.json({ ok: true, ...(await socialService.loginWithApple(token, role, typeof rawName === "string" ? rawName.trim() || undefined : undefined, { ageConfirmed: req.body?.ageConfirmed === true })) });
  } catch (e) {
    sendError(res, e, 401);
  }
}

export async function sendOtpHandler(req: Request, res: Response) {
  const { target, phone, email, channel } = req.body ?? {};
  const destination = target || phone || email;
  if (typeof destination !== "string" || !destination) {
    return res.status(400).json({ ok: false, error: "Phone number or email address is required" });
  }
  try {
    res.json(await sendOtp(destination, channel === "email" || channel === "sms" ? channel : undefined, localeFromHeader(req.headers["accept-language"]) ?? "en"));
  } catch (e) {
    sendError(res, e);
  }
}

export async function verifyOtpHandler(req: Request, res: Response) {
  const { target, phone, email, code, ageConfirmed } = req.body ?? {};
  const destination = target || phone || email;
  if (typeof destination !== "string" || typeof code !== "string" || !destination || !code) {
    return res.status(400).json({ ok: false, error: "Destination and verification code are required" });
  }
  try {
    res.json(await verifyOtp(destination, code, { ageConfirmed: ageConfirmed === true }));
  } catch (e) {
    sendError(res, e, 401);
  }
}

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(72),
  // Same rules as registration (at least 10 characters since 2.16.0)
  newPassword: z.string().min(10, "Password must be at least 10 characters").max(72),
});

export async function changePasswordHandler(req: AuthRequest, res: Response) {
  const body = changePasswordSchema.safeParse(req.body);
  if (!body.success) {
    return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Check the details", errors: body.error.flatten() });
  }
  try {
    res.json({ ok: true, ...(await authService.changePassword(req.user!.id, body.data.currentPassword, body.data.newPassword, req.user!.mfa)) });
  } catch (e) {
    sendError(res, e);
  }
}

/** Always 200 for a well-formed address, whether or not an account exists (no account enumeration). */
export async function forgotPasswordHandler(req: Request, res: Response) {
  const body = forgotSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter a valid email address" });
  try {
    forgotPassword(body.data.email, localeFromHeader(req.headers["accept-language"]));
    res.json({ ok: true });
  } catch (e) {
    sendError(res, e);
  }
}

export async function resetPasswordHandler(req: Request, res: Response) {
  const body = resetSchema.safeParse(req.body);
  if (!body.success) {
    return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Check the details", errors: body.error.flatten() });
  }
  try {
    await resetPassword(body.data.email, body.data.code, body.data.password);
    res.json({ ok: true });
  } catch (e) {
    sendError(res, e);
  }
}

export async function exportMyData(req: AuthRequest, res: Response) {
  try {
    const data = await authService.exportUserData(req.user!.id);
    res.setHeader("Content-Disposition", 'attachment; filename="malvoya-my-data.json"');
    res.json({ ok: true, exportedAt: new Date().toISOString(), data });
  } catch (e) {
    sendError(res, e);
  }
}

export async function deleteMe(req: AuthRequest, res: Response) {
  try {
    await authService.deleteUserAccount(req.user!.id);
    res.json({
      ok: true,
      message: "Your account has been deleted. Order records required by Finnish bookkeeping law are kept in anonymised form.",
    });
  } catch (e) {
    sendError(res, e);
  }
}
