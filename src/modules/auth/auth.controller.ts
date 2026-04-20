import { Request, Response } from "express";
import { registerSchema, loginSchema, refreshSchema } from "./auth.schema";
import * as authService from "./auth.service";

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
