import { Request, Response } from "express";
import { registerSchema, loginSchema, refreshSchema } from "./auth.schema";
import * as authService from "./auth.service";
import * as socialService from "./social.service";

export async function register(req: Request, res: Response) {
  const result = registerSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.registerUser(result.data);
    res.status(201).json({ ok: true, ...data });
  } catch (e: any) {
    res.status(409).json({ ok: false, error: e.message });
  }
}

export async function login(req: Request, res: Response) {
  const result = loginSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.loginUser(result.data);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(401).json({ ok: false, error: e.message });
  }
}

export async function refresh(req: Request, res: Response) {
  const result = refreshSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.refreshTokens(result.data.refreshToken);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(401).json({ ok: false, error: e.message });
  }
}

export async function logout(req: Request, res: Response) {
  const { refreshToken } = req.body;
  if (refreshToken) await authService.logoutUser(refreshToken);
  res.json({ ok: true });
}

export async function googleLogin(req: Request, res: Response) {
  const { idToken } = req.body;
  if (!idToken) return res.status(400).json({ ok: false, error: "idToken is required" });
  try {
    const data = await socialService.loginWithGoogle(idToken);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(401).json({ ok: false, error: e.message });
  }
}

export async function phoneLogin(req: Request, res: Response) {
  const { firebaseToken } = req.body;
  if (!firebaseToken) return res.status(400).json({ ok: false, error: "firebaseToken is required" });
  try {
    const data = await socialService.loginWithPhone(firebaseToken);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(401).json({ ok: false, error: e.message });
  }
}

export async function appleLogin(req: Request, res: Response) {
  const { idToken } = req.body;
  if (!idToken) return res.status(400).json({ ok: false, error: "idToken is required" });
  try {
    const data = await socialService.loginWithApple(idToken);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(401).json({ ok: false, error: e.message });
  }
}

export async function sendOtpHandler(req: Request, res: Response) {
  const { target, phone, email, channel } = req.body;
  const destination = target || phone || email;
  if (!destination) {
    return res.status(400).json({ ok: false, error: "Phone number or email address is required" });
  }
  try {
    const { sendOtp } = await import("./otp.service");
    const data = await sendOtp(destination, channel);
    res.json(data);
  } catch (e: any) {
    res.status(400).json({ ok: false, error: e.message });
  }
}

export async function verifyOtpHandler(req: Request, res: Response) {
  const { target, phone, email, code } = req.body;
  const destination = target || phone || email;
  if (!destination || !code) {
    return res.status(400).json({ ok: false, error: "Target destination and verification code are required" });
  }
  try {
    const { verifyOtp } = await import("./otp.service");
    const data = await verifyOtp(destination, code);
    res.json(data);
  } catch (e: any) {
    res.status(401).json({ ok: false, error: e.message });
  }
}

