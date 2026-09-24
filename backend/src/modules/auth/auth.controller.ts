import { Request, Response } from "express";
import { registerSchema, loginSchema, refreshSchema } from "./auth.schema";
import * as authService from "./auth.service";
import * as socialService from "./social.service";
import { sendOtp, verifyOtp } from "./otp.service";
import { AuthRequest } from "../../middleware/auth";

/** AuthErrors carry a safe message + status; anything else is logged and hidden. */
function sendError(res: Response, e: unknown, fallbackStatus = 500) {
  if (e instanceof authService.AuthError) return res.status(e.status).json({ ok: false, error: e.message });
  console.error(e);
  return res.status(fallbackStatus).json({ ok: false, error: fallbackStatus === 401 ? "Authentication failed" : "Something went wrong" });
}

export async function register(req: Request, res: Response) {
  const result = registerSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.registerUser(result.data);
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

function tokenHandler(field: "idToken" | "firebaseToken", login: (token: string, role: socialService.SignupRole) => Promise<unknown>) {
  return async (req: Request, res: Response) => {
    const token = req.body?.[field];
    if (typeof token !== "string" || !token) return res.status(400).json({ ok: false, error: `${field} is required` });
    const role = SIGNUP_ROLES.includes(req.body?.role) ? (req.body.role as socialService.SignupRole) : "CUSTOMER";
    try {
      const data = await login(token, role);
      res.json({ ok: true, ...(data as object) });
    } catch (e) {
      sendError(res, e, 401);
    }
  };
}

export const googleLogin = tokenHandler("idToken", socialService.loginWithGoogle);
export const phoneLogin  = tokenHandler("firebaseToken", socialService.loginWithPhone);
export const appleLogin  = tokenHandler("idToken", socialService.loginWithApple);

export async function sendOtpHandler(req: Request, res: Response) {
  const { target, phone, email, channel } = req.body ?? {};
  const destination = target || phone || email;
  if (typeof destination !== "string" || !destination) {
    return res.status(400).json({ ok: false, error: "Phone number or email address is required" });
  }
  try {
    res.json(await sendOtp(destination, channel === "email" || channel === "sms" ? channel : undefined));
  } catch (e) {
    sendError(res, e);
  }
}

export async function verifyOtpHandler(req: Request, res: Response) {
  const { target, phone, email, code } = req.body ?? {};
  const destination = target || phone || email;
  if (typeof destination !== "string" || typeof code !== "string" || !destination || !code) {
    return res.status(400).json({ ok: false, error: "Destination and verification code are required" });
  }
  try {
    res.json(await verifyOtp(destination, code));
  } catch (e) {
    sendError(res, e, 401);
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
