import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt";

export type Role = "CUSTOMER" | "VENDOR" | "COURIER" | "ADMIN";

export interface AuthRequest extends Request {
  user?: { id: number; role: Role; email: string };
}

function readBearer(req: Request): string | null {
  const header = req.headers.authorization;
  return header?.startsWith("Bearer ") ? header.slice(7) : null;
}

export function auth(req: AuthRequest, res: Response, next: NextFunction) {
  const token = readBearer(req);
  if (!token) return res.status(401).json({ ok: false, error: "Unauthorized" });
  try {
    const payload = verifyAccessToken(token);
    req.user = { id: payload.id, role: payload.role as Role, email: payload.email };
    next();
  } catch {
    return res.status(401).json({ ok: false, error: "Invalid or expired token" });
  }
}

/** Attaches req.user when a valid token is present, but never rejects the request. */
export function optionalAuth(req: AuthRequest, _res: Response, next: NextFunction) {
  const token = readBearer(req);
  if (token) {
    try {
      const payload = verifyAccessToken(token);
      req.user = { id: payload.id, role: payload.role as Role, email: payload.email };
    } catch {
      // treat as anonymous
    }
  }
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
