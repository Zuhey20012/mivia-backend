import jwt from "jsonwebtoken";
import { env } from "../config/env";

export interface AccessTokenPayload {
  id: number;
  role: string;
  email: string;
}

const ALGORITHM = "HS256" as const;

export function signAccessToken(payload: AccessTokenPayload): string {
  return jwt.sign({ id: payload.id, role: payload.role, email: payload.email, typ: "access" }, env.jwtSecret, {
    algorithm: ALGORITHM,
    expiresIn: env.jwtExpiresIn,
  } as jwt.SignOptions);
}

export function signRefreshToken(userId: number): string {
  // jti makes every refresh token unique even when two are issued in the same second
  return jwt.sign({ id: userId, typ: "refresh" }, env.jwtRefreshSecret, {
    algorithm: ALGORITHM,
    expiresIn: env.jwtRefreshExpiresIn,
    jwtid: `${userId}.${Date.now()}.${Math.random().toString(36).slice(2)}`,
  } as jwt.SignOptions);
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  const payload = jwt.verify(token, env.jwtSecret, { algorithms: [ALGORITHM] }) as jwt.JwtPayload;
  if (payload.typ !== "access") throw new Error("Wrong token type");
  return { id: Number(payload.id), role: String(payload.role), email: String(payload.email) };
}

export function verifyRefreshToken(token: string): { id: number } {
  const payload = jwt.verify(token, env.jwtRefreshSecret, { algorithms: [ALGORITHM] }) as jwt.JwtPayload;
  if (payload.typ !== "refresh") throw new Error("Wrong token type");
  return { id: Number(payload.id) };
}
