import bcrypt from "bcryptjs";
import { Prisma } from "@prisma/client";
import { DecodedIdToken } from "firebase-admin/auth";
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken, verifyRefreshToken } from "../../utils/jwt";
import { FirebaseNotConfiguredError, verifyFirebaseIdToken } from "../../lib/firebase";
import { RegisterInput, LoginInput, FirebaseSignInInput } from "./auth.schema";
import { env } from "../../config/env";

export class AuthError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const safeUserSelect = { id: true, name: true, email: true, phone: true, role: true, createdAt: true } as const;

export async function registerUser(input: RegisterInput) {
  const existing = await prisma.user.findUnique({ where: { email: input.email } });
  if (existing) throw new Error("Email already registered");

  const passwordHash = await bcrypt.hash(input.password, 12);
  const user = await prisma.user.create({
    data: { name: input.name, email: input.email, phone: input.phone, passwordHash, role: input.role },
    select: { id: true, name: true, email: true, role: true, createdAt: true },
  });

  const tokens = generateTokens(user);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user, ...tokens };
}

export async function loginUser(input: LoginInput) {
  const user = await prisma.user.findUnique({ where: { email: input.email } });
  // Firebase-only accounts have no password and cannot use this route.
  if (!user || !user.passwordHash) throw new Error("Invalid credentials");

  const valid = await bcrypt.compare(input.password, user.passwordHash);
  if (!valid) throw new Error("Invalid credentials");

  const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
  const tokens = generateTokens(safeUser);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user: safeUser, ...tokens };
}

export async function refreshTokens(refreshToken: string) {
  const payload = verifyRefreshToken(refreshToken);
  const stored = await prisma.refreshToken.findUnique({ where: { token: refreshToken } });
  if (!stored || stored.expiresAt < new Date()) throw new Error("Refresh token expired or invalid");

  await prisma.refreshToken.delete({ where: { token: refreshToken } });

  const user = await prisma.user.findUniqueOrThrow({
    where: { id: stored.userId },
    select: { id: true, name: true, email: true, role: true },
  });
  const tokens = generateTokens(user);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user, ...tokens };
}

export async function logoutUser(refreshToken: string) {
  await prisma.refreshToken.deleteMany({ where: { token: refreshToken } });
}

// ─── Firebase ───────────────────────────────────────────────────────────────

// Signs in (or signs up) with a Firebase ID token and returns Mivia tokens.
// Accounts are matched by Firebase UID only. An existing email/password account
// is never taken over automatically: its owner must log in and call linkFirebase.
export async function firebaseSignIn(input: FirebaseSignInInput) {
  const decoded = await verifyIdTokenOrThrow(input.idToken);

  let user = await prisma.user.findUnique({ where: { firebaseUid: decoded.uid }, select: safeUserSelect });
  if (!user) {
    const email = decoded.email && decoded.email_verified ? decoded.email : null;
    if (email) {
      const existing = await prisma.user.findFirst({
        where: { email: { equals: email, mode: "insensitive" } },
        select: { id: true },
      });
      if (existing) {
        throw new AuthError(409, "An account with this email already exists. Log in with your password and link Firebase from your account.");
      }
    }

    try {
      user = await prisma.user.create({
        data: {
          firebaseUid: decoded.uid,
          email,
          phone: decoded.phone_number ?? null,
          name:  input.name ?? decoded.name ?? "Mivia user",
          role:  input.role,
        },
        select: safeUserSelect,
      });
    } catch (e) {
      // Two concurrent first sign-ins for the same UID: use the row the other request created.
      if (!isUniqueViolation(e)) throw e;
      user = await prisma.user.findUnique({ where: { firebaseUid: decoded.uid }, select: safeUserSelect });
      if (!user) throw new AuthError(409, "An account with this email already exists.");
    }
  }

  const tokens = generateTokens(user);
  await saveRefreshToken(user.id, tokens.refreshToken);
  return { user, ...tokens };
}

// Attaches a Firebase identity to the logged-in user so they can sign in with it later.
export async function linkFirebase(userId: number, idToken: string) {
  const decoded = await verifyIdTokenOrThrow(idToken);

  const current = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  if (current.firebaseUid === decoded.uid) {
    return prisma.user.findUniqueOrThrow({ where: { id: userId }, select: safeUserSelect });
  }
  if (current.firebaseUid) throw new AuthError(409, "This account is already linked to a different Firebase user");

  const owner = await prisma.user.findUnique({ where: { firebaseUid: decoded.uid }, select: { id: true } });
  if (owner) throw new AuthError(409, "This Firebase user is already linked to another account");

  try {
    return await prisma.user.update({
      where: { id: userId },
      // A phone number in the token was verified by Firebase; only fill it in if none is stored.
      data: { firebaseUid: decoded.uid, ...(current.phone ? {} : { phone: decoded.phone_number ?? null }) },
      select: safeUserSelect,
    });
  } catch (e) {
    if (isUniqueViolation(e)) throw new AuthError(409, "This Firebase user is already linked to another account");
    throw e;
  }
}

async function verifyIdTokenOrThrow(idToken: string): Promise<DecodedIdToken> {
  try {
    return await verifyFirebaseIdToken(idToken);
  } catch (e) {
    if (e instanceof FirebaseNotConfiguredError) throw new AuthError(503, e.message);
    throw new AuthError(401, "Invalid or expired Firebase ID token");
  }
}

function isUniqueViolation(e: unknown): boolean {
  return e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002";
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function generateTokens(user: { id: number; email: string | null; role: string }) {
  const accessToken  = signAccessToken({ id: user.id, email: user.email, role: user.role });
  const refreshToken = signRefreshToken({ id: user.id });
  return { accessToken, refreshToken };
}

async function saveRefreshToken(userId: number, token: string) {
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
  await prisma.refreshToken.create({ data: { token, userId, expiresAt } });
}
