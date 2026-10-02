import jwt from "jsonwebtoken";
import { randomUUID } from "crypto";
import { env } from "../config/env";

export function signAccessToken(payload: object): string {
  return jwt.sign(payload, env.jwtSecret, { expiresIn: env.jwtExpiresIn } as jwt.SignOptions);
}

export function signRefreshToken(payload: object): string {
  // jwtid keeps tokens unique: two logins in the same second would otherwise
  // produce identical tokens and hit the RefreshToken.token unique constraint.
  return jwt.sign(payload, env.jwtRefreshSecret, { expiresIn: env.jwtRefreshExpiresIn, jwtid: randomUUID() } as jwt.SignOptions);
}

export function verifyAccessToken(token: string): jwt.JwtPayload {
  return jwt.verify(token, env.jwtSecret) as jwt.JwtPayload;
}

export function verifyRefreshToken(token: string): jwt.JwtPayload {
  return jwt.verify(token, env.jwtRefreshSecret) as jwt.JwtPayload;
}
