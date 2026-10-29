import jwt from "jsonwebtoken";
import { env } from "../config/env";

export interface AccessTokenPayload {
  id: number;
  role: string;
  email: string;
  /** The session passed two-step sign-in (authenticator code). */
  mfa?: boolean;
  /** The sign-in (UserSession id) this token belongs to (since 2.16.0; absent on older tokens). */
  sid?: number;
}

const ALGORITHM = "HS256" as const;

export function signAccessToken(payload: AccessTokenPayload): string {
  return jwt.sign({ id: payload.id, role: payload.role, email: payload.email, typ: "access", ...(payload.mfa ? { mfa: true } : {}), ...(payload.sid ? { sid: payload.sid } : {}) }, env.jwtSecret, {
    algorithm: ALGORITHM,
    expiresIn: env.jwtExpiresIn,
  } as jwt.SignOptions);
}

export function signRefreshToken(userId: number, mfa = false): string {
  // jti makes every refresh token unique even when two are issued in the same second; mfa carries the
  // two-step sign-in over to the refreshed session
  return jwt.sign({ id: userId, typ: "refresh", ...(mfa ? { mfa: true } : {}) }, env.jwtRefreshSecret, {
    algorithm: ALGORITHM,
    expiresIn: env.jwtRefreshExpiresIn,
    jwtid: `${userId}.${Date.now()}.${Math.random().toString(36).slice(2)}`,
  } as jwt.SignOptions);
}

export function verifyAccessToken(token: string): AccessTokenPayload & { iat: number } {
  const payload = jwt.verify(token, env.jwtSecret, { algorithms: [ALGORITHM] }) as jwt.JwtPayload;
  if (payload.typ !== "access") throw new Error("Wrong token type");
  return {
    id: Number(payload.id), role: String(payload.role), email: String(payload.email), mfa: payload.mfa === true, iat: Number(payload.iat ?? 0),
    ...(Number.isInteger(payload.sid) ? { sid: Number(payload.sid) } : {}),
  };
}

export function verifyRefreshToken(token: string): { id: number; mfa: boolean } {
  const payload = jwt.verify(token, env.jwtRefreshSecret, { algorithms: [ALGORITHM] }) as jwt.JwtPayload;
  if (payload.typ !== "refresh") throw new Error("Wrong token type");
  return { id: Number(payload.id), mfa: payload.mfa === true };
}

/**
 * Between the password (or another first step) and the authenticator code: proves the first step for 5 minutes
 * and nothing else. Its own type and audience, so it never works as an access or refresh token.
 */
export function signMfaToken(userId: number): string {
  return jwt.sign({ id: userId, typ: "mfa" }, env.jwtSecret, { algorithm: ALGORITHM, expiresIn: "5m", audience: "mfa" } as jwt.SignOptions);
}

export function verifyMfaToken(token: string): { id: number; iat: number } {
  const payload = jwt.verify(token, env.jwtSecret, { algorithms: [ALGORITHM], audience: "mfa" }) as jwt.JwtPayload;
  if (payload.typ !== "mfa") throw new Error("Wrong token type");
  return { id: Number(payload.id), iat: Number(payload.iat ?? 0) };
}
