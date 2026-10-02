import { OAuth2Client } from "google-auth-library";
import { initializeApp, getApps, getApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { issueSession } from "./session";
import { AuthError, assertVerifiedSignInAllowed, phoneToSyntheticEmail } from "./auth.service";

const googleClient = new OAuth2Client(env.googleClientId);

// Verifying Firebase ID tokens only needs the project id (public keys are fetched from Google).
if (!getApps().some((a) => a.name === "[DEFAULT]")) {
  try {
    initializeApp(process.env.FIREBASE_PROJECT_ID ? { projectId: process.env.FIREBASE_PROJECT_ID } : undefined);
  } catch (e) {
    console.error("Firebase Admin initialization error", e);
  }
}

type SocialUser = { id: number; name: string; email: string; role: string; isActive: boolean; googleSub: string | null };
export type SignupRole = "CUSTOMER" | "VENDOR" | "COURIER";

/** The role only applies when a new account is created; existing accounts keep theirs. */
async function createSocialUser(data: { email: string; name: string; phone?: string; googleSub?: string }, role: SignupRole) {
  const user = await prisma.user.create({
    data: { email: data.email, name: data.name, phone: data.phone ?? null, googleSub: data.googleSub ?? null, passwordHash: unusablePasswordHash(), role },
  });
  if (role === "COURIER") {
    await prisma.courier.create({ data: { userId: user.id, name: user.name, phone: data.phone ?? null, isActive: false } });
  }
  return user;
}

function unusablePasswordHash() {
  return `SOCIAL:${crypto.randomBytes(24).toString("hex")}`;
}

function assertActive(user: SocialUser) {
  if (!user.isActive) throw new AuthError("This account is disabled", 403);
}

async function verifyGoogleToken(idToken: string) {
  if (!env.googleClientId) throw new AuthError("Google sign-in is not configured", 503);
  let payload;
  try {
    payload = (await googleClient.verifyIdToken({ idToken, audience: env.googleClientId })).getPayload();
  } catch {
    throw new AuthError("Invalid Google token", 401);
  }
  // Only trust emails Google has verified, otherwise an attacker could claim someone else's address.
  if (!payload?.sub || !payload.email || payload.email_verified !== true) throw new AuthError("Invalid Google token", 401);
  return { sub: payload.sub, email: payload.email.toLowerCase(), name: payload.name };
}

export async function loginWithGoogle(idToken: string, role: SignupRole = "CUSTOMER") {
  const google = await verifyGoogleToken(idToken);

  // A linked Google account opens the account it was linked to, whatever that account's email is.
  let user = await prisma.user.findUnique({ where: { googleSub: google.sub } });
  if (!user) {
    user = await prisma.user.findFirst({ where: { email: { equals: google.email, mode: "insensitive" } } });
    if (user) {
      assertVerifiedSignInAllowed(user);
      if (!user.googleSub) user = await prisma.user.update({ where: { id: user.id }, data: { googleSub: google.sub } });
    } else {
      user = await createSocialUser({ email: google.email, name: google.name || google.email.split("@")[0], googleSub: google.sub }, role);
    }
  }
  assertActive(user);
  return issueSession(user);
}

/**
 * Links a Google account to the signed-in user, so "Sign in with Google" opens this account from now on.
 * This is how accounts made by /register (which verified sign-ins never open by email) can use Google.
 */
export async function linkGoogle(userId: number, idToken: string) {
  const google = await verifyGoogleToken(idToken);
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { isActive: true, googleSub: true } });
  if (!user || !user.isActive) throw new AuthError("This account is disabled", 403);
  if (user.googleSub === google.sub) return { googleLinked: true, googleEmail: google.email };
  if (user.googleSub) throw new AuthError("A different Google account is already linked. Unlink it first.", 409);

  const owner = await prisma.user.findUnique({ where: { googleSub: google.sub }, select: { id: true } });
  if (owner) throw new AuthError("This Google account is already linked to another Malvoya account", 409);
  try {
    await prisma.user.update({ where: { id: userId }, data: { googleSub: google.sub } });
  } catch (e: any) {
    if (e?.code === "P2002") throw new AuthError("This Google account is already linked to another Malvoya account", 409);
    throw e;
  }
  return { googleLinked: true, googleEmail: google.email };
}

/** Only password accounts can unlink: any other account is reached by Google through its verified email anyway. */
export async function unlinkGoogle(userId: number) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { passwordHash: true } });
  if (!user?.passwordHash.startsWith("$2")) {
    throw new AuthError("Google can only be unlinked from accounts that sign in with a password.", 409);
  }
  await prisma.user.update({ where: { id: userId }, data: { googleSub: null } });
  return { googleLinked: false };
}

async function verifyFirebaseToken(token: string) {
  try {
    return await getAuth(getApp()).verifyIdToken(token);
  } catch {
    throw new AuthError("Invalid sign-in token", 401);
  }
}

export async function loginWithPhone(firebaseToken: string, role: SignupRole = "CUSTOMER") {
  const decoded = await verifyFirebaseToken(firebaseToken);
  const phoneNumber = decoded.phone_number;
  if (!phoneNumber) throw new AuthError("Invalid phone token", 401);

  let user = await prisma.user.findFirst({ where: { phone: phoneNumber } });
  if (user) {
    assertVerifiedSignInAllowed(user);
  } else {
    user = await createSocialUser({ phone: phoneNumber, email: phoneToSyntheticEmail(phoneNumber), name: role === "CUSTOMER" ? "Customer" : "Partner" }, role);
  }
  assertActive(user);
  return issueSession(user);
}

export async function loginWithApple(identityToken: string, role: SignupRole = "CUSTOMER") {
  const decoded = await verifyFirebaseToken(identityToken);
  const email = decoded.email?.toLowerCase();
  if (!email || decoded.email_verified === false) throw new AuthError("Apple sign-in did not provide a verified email", 401);

  let user = await prisma.user.findFirst({ where: { email: { equals: email, mode: "insensitive" } } });
  if (user) {
    assertVerifiedSignInAllowed(user);
  } else {
    user = await createSocialUser({ email, name: decoded.name || "Customer" }, role);
  }
  assertActive(user);
  return issueSession(user);
}
