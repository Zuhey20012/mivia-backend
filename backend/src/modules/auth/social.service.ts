import { OAuth2Client } from 'google-auth-library';
import * as admin from 'firebase-admin';
import { prisma } from "../../lib/prisma";
import { signAccessToken, signRefreshToken } from "../../utils/jwt";
import { env } from "../../config/env";

const googleClient = new OAuth2Client(env.googleClientId);

// Initialize Firebase Admin (requires GOOGLE_APPLICATION_CREDENTIALS env var or serviceAccount.json)
if (!admin.apps.length) {
  try {
    admin.initializeApp();
  } catch (e) {
    console.error("Firebase Admin Initialization Error", e);
  }
}

export async function loginWithGoogle(idToken: string) {
  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: env.googleClientId,
  });
  const payload = ticket.getPayload();
  if (!payload || !payload.email) throw new Error("Invalid Google Token");

  let user = await prisma.user.findUnique({ where: { email: payload.email } });

  if (!user) {
    user = await prisma.user.create({
      data: {
        email: payload.email,
        name: payload.name || "Google User",
        passwordHash: "SOCIAL_AUTH",
        role: "CUSTOMER",
      }
    });
  }

  return generateSession(user);
}

export async function loginWithPhone(firebaseToken: string) {
  const decodedToken = await admin.auth().verifyIdToken(firebaseToken);
  const phoneNumber = decodedToken.phone_number;

  if (!phoneNumber) throw new Error("Invalid Phone Token");

  let user = await prisma.user.findFirst({ where: { phone: phoneNumber } });

  if (!user) {
    user = await prisma.user.create({
      data: {
        phone: phoneNumber,
        email: `${phoneNumber.replace(/[^0-9]/g, '')}@phone.malvoya.app`,
        name: "Mobile User",
        passwordHash: "SOCIAL_AUTH",
        role: "CUSTOMER",
      }
    });
  }

  return generateSession(user);
}

export async function loginWithApple(identityToken: string) {
  // Verify Apple identity token using Firebase Admin
  const decodedToken = await admin.auth().verifyIdToken(identityToken);
  const email = decodedToken.email;
  const name = decodedToken.name || "Apple User";

  if (!email) throw new Error("Invalid Apple Token — no email provided");

  let user = await prisma.user.findUnique({ where: { email } });

  if (!user) {
    user = await prisma.user.create({
      data: {
        email,
        name,
        passwordHash: "SOCIAL_AUTH",
        role: "CUSTOMER",
      }
    });
  }

  return generateSession(user);
}

async function generateSession(user: any) {
  const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
  const accessToken = signAccessToken(safeUser);
  const refreshToken = signRefreshToken({ id: user.id });

  // Save refresh token to database for proper session management
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
  await prisma.refreshToken.create({ data: { token: refreshToken, userId: user.id, expiresAt } });

  return { user: safeUser, accessToken, refreshToken };
}
