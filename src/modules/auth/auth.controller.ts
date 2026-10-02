import { Request, Response } from "express";
import { registerSchema, loginSchema, refreshSchema, firebaseSignInSchema, firebaseLinkSchema } from "./auth.schema";
import * as authService from "./auth.service";
import { AuthRequest } from "../../middleware/auth";

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

export async function firebaseLogin(req: Request, res: Response) {
  const result = firebaseSignInSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await authService.firebaseSignIn(result.data);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    if (e instanceof authService.AuthError) return res.status(e.status).json({ ok: false, error: e.message });
    console.error(e);
    res.status(500).json({ ok: false, error: "Internal server error" });
  }
}

export async function firebaseLink(req: AuthRequest, res: Response) {
  const result = firebaseLinkSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const user = await authService.linkFirebase(req.user!.id, result.data.idToken);
    res.json({ ok: true, user });
  } catch (e: any) {
    if (e instanceof authService.AuthError) return res.status(e.status).json({ ok: false, error: e.message });
    console.error(e);
    res.status(500).json({ ok: false, error: "Internal server error" });
  }
}
