import { OAuth2Client } from "google-auth-library";
import * as admin from "firebase-admin";
import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { issueSession } from "./session";
import { AuthError, phoneToSyntheticEmail } from "./auth.service";

const googleClient = new OAuth2Client(env.googleClientId);

// Verifying Firebase ID tokens only needs the project id (public keys are fetched from Google).
if (!admin.apps.length) {
  try {
    admin.initializeApp(process.env.FIREBASE_PROJECT_ID ? { projectId: process.env.FIREBASE_PROJECT_ID } : undefined);
  } catch (e) {
    console.error("Firebase Admin initialization error", e);
  }
}

type SocialUser = { id: number; name: string; email: string; role: string; isActive: boolean };
export type SignupRole = "CUSTOMER" | "VENDOR" | "COURIER";

/** The role only applies when a new account is created; existing accounts keep theirs. */
async function createSocialUser(data: { email: string; name: string; phone?: string }, role: SignupRole) {
  const user = await prisma.user.create({
    data: { email: data.email, name: data.name, phone: data.phone ?? null, passwordHash: unusablePasswordHash(), role },
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

export async function loginWithGoogle(idToken: string, role: SignupRole = "CUSTOMER") {
  if (!env.googleClientId) throw new AuthError("Google sign-in is not configured", 503);
  const ticket = await googleClient.verifyIdToken({ idToken, audience: env.googleClientId });
  const payload = ticket.getPayload();
  // Only trust emails Google has verified, otherwise an attacker could claim someone else's address.
  if (!payload?.email || payload.email_verified !== true) throw new AuthError("Invalid Google token", 401);

  const email = payload.email.toLowerCase();
  let user = await prisma.user.findFirst({ where: { email: { equals: email, mode: "insensitive" } } });
  if (!user) {
    user = await createSocialUser({ email, name: payload.name || email.split("@")[0] }, role);
  }
  assertActive(user);
  return issueSession(user);
}

async function verifyFirebaseToken(token: string) {
  try {
    return await admin.auth().verifyIdToken(token);
  } catch {
    throw new AuthError("Invalid sign-in token", 401);
  }
}

export async function loginWithPhone(firebaseToken: string, role: SignupRole = "CUSTOMER") {
  const decoded = await verifyFirebaseToken(firebaseToken);
  const phoneNumber = decoded.phone_number;
  if (!phoneNumber) throw new AuthError("Invalid phone token", 401);

  let user = await prisma.user.findFirst({ where: { phone: phoneNumber } });
  if (!user) {
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
  if (!user) {
    user = await createSocialUser({ email, name: decoded.name || "Customer" }, role);
  }
  assertActive(user);
  return issueSession(user);
}
