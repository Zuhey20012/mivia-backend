import jwt from "jsonwebtoken";
import { env } from "../config/env";

export function signAccessToken(payload: object): string {
  return jwt.sign(payload, env.jwtSecret, { expiresIn: env.jwtExpiresIn } as jwt.SignOptions);
}

export function signRefreshToken(payload: object): string {
  return jwt.sign(payload, env.jwtRefreshSecret, { expiresIn: env.jwtRefreshExpiresIn } as jwt.SignOptions);
}

export function verifyAccessToken(token: string): jwt.JwtPayload {
  return jwt.verify(token, env.jwtSecret) as jwt.JwtPayload;
}

export function verifyRefreshToken(token: string): jwt.JwtPayload {
  return jwt.verify(token, env.jwtRefreshSecret) as jwt.JwtPayload;
}
