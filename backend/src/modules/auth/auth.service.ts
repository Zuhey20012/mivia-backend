import bcrypt from "bcryptjs";
import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { verifyRefreshToken } from "../../utils/jwt";
import { RegisterInput, LoginInput } from "./auth.schema";
import { issueSession, hashToken, revokeAllSessions } from "./session";

export class AuthError extends Error {
  constructor(message: string, public status: number) {
    super(message);
  }
}

const PHONE_EMAIL_DOMAIN = "phone.malvoya.app";
const DUMMY_HASH = bcrypt.hashSync(crypto.randomBytes(16).toString("hex"), 12);

function isPhoneIdentifier(value: string) {
  return !value.includes("@") && /^[0-9+ ()-]+$/.test(value);
}

/** Phone-only accounts get a synthetic, non-deliverable email so `email` stays unique. */
export function phoneToSyntheticEmail(phone: string) {
  return `${phone.replace(/[^0-9]/g, "")}@${PHONE_EMAIL_DOMAIN}`;
}

export function isSyntheticEmail(email: string) {
  return email.endsWith(`@${PHONE_EMAIL_DOMAIN}`) || email.endsWith("@deleted.invalid");
}

export async function registerUser(input: RegisterInput) {
  const identifier = input.email.trim();
  const isPhone = isPhoneIdentifier(identifier);
  const email = isPhone ? phoneToSyntheticEmail(identifier) : identifier.toLowerCase();
  const phone = isPhone ? identifier.replace(/[^0-9+]/g, "") : input.phone;

  if (!isPhone && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new AuthError("Enter a valid email address or phone number", 400);
  }

  const existing = await prisma.user.findFirst({
    where: {
      OR: [
        { email: { equals: email, mode: "insensitive" } },
        ...(phone ? [{ phone }] : []),
      ],
    },
    select: { id: true },
  });
  // Never hand out a session for an existing account from the register endpoint.
  if (existing) throw new AuthError("An account with this email or phone already exists. Please sign in.", 409);

  const passwordHash = await bcrypt.hash(input.password, 12);
  const user = await prisma.user.create({
    data: { name: input.name, email, phone, passwordHash, role: input.role },
    select: { id: true, name: true, email: true, role: true },
  });

  if (input.role === "COURIER") {
    // Couriers start unapproved; an admin approves them after identity / right-to-work checks.
    await prisma.courier.create({ data: { userId: user.id, name: user.name, email: isPhone ? null : email, phone, isActive: false } });
  }

  return issueSession(user);
}

export async function loginUser(input: LoginInput) {
  const identifier = input.email.trim();
  const candidates = isPhoneIdentifier(identifier)
    ? [{ phone: identifier.replace(/[^0-9+]/g, "") }, { email: phoneToSyntheticEmail(identifier) }]
    : [{ email: { equals: identifier.toLowerCase(), mode: "insensitive" as const } }];

  const user = await prisma.user.findFirst({ where: { OR: candidates } });

  // Compare against a dummy hash when the user does not exist so response timing does not reveal accounts.
  // Social/OTP-only accounts have no bcrypt hash, so they can't sign in with a password.
  const hash = user?.passwordHash?.startsWith("$2") ? user.passwordHash : DUMMY_HASH;
  const valid = await bcrypt.compare(input.password, hash);
  if (!user || !valid || !user.isActive) throw new AuthError("Invalid credentials", 401);

  return issueSession(user);
}

export async function refreshTokens(refreshToken: string) {
  try {
    verifyRefreshToken(refreshToken);
  } catch {
    throw new AuthError("Refresh token expired or invalid", 401);
  }
  const tokenHash = hashToken(refreshToken);
  const stored = await prisma.refreshToken.findUnique({ where: { token: tokenHash }, include: { user: true } });
  if (!stored || stored.expiresAt < new Date() || !stored.user.isActive) {
    throw new AuthError("Refresh token expired or invalid", 401);
  }

  // Rotation: each refresh token is single use
  await prisma.refreshToken.delete({ where: { token: tokenHash } });
  return issueSession(stored.user);
}

export async function logoutUser(refreshToken: string) {
  await prisma.refreshToken.deleteMany({ where: { token: hashToken(refreshToken) } });
}

// ─── GDPR: access (Art. 15/20) and erasure (Art. 17) ────────────────────────

export async function exportUserData(userId: number) {
  return prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true, email: true, name: true, phone: true, role: true, avatarUrl: true,
      address: true, latitude: true, longitude: true, createdAt: true, updatedAt: true,
      orders: { include: { items: true } },
      rentals: { include: { items: true } },
      returns: true,
      store: { include: { products: true } },
      courier: { select: { id: true, name: true, phone: true, email: true, isApproved: true, createdAt: true } },
    },
  });
}

const OPEN_ORDER_STATUSES = ["PENDING", "CONFIRMED", "PROCESSING", "SHIPPED"] as const;

/**
 * Erases personal data while keeping the transaction records that Finnish bookkeeping law
 * (Kirjanpitolaki 2:10) requires us to retain. Orders stay linked to an anonymised user row.
 */
export async function deleteUserAccount(userId: number) {
  const openOrders = await prisma.order.count({
    where: {
      status: { in: [...OPEN_ORDER_STATUSES] },
      OR: [{ userId }, { store: { ownerId: userId } }, { courier: { userId } }],
    },
  });
  if (openOrders > 0) {
    throw new AuthError("You have orders in progress. Your account can be deleted once they are completed or cancelled.", 409);
  }

  await prisma.$transaction(async (tx) => {
    // Delivery addresses and notes are not needed for bookkeeping once an order is closed
    await tx.order.updateMany({
      where: { userId },
      data: { deliveryAddress: null, deliveryLat: null, deliveryLng: null, notes: null },
    });

    const store = await tx.store.findUnique({ where: { ownerId: userId } });
    if (store) {
      // The store's legal identity stays on past orders; it just stops trading.
      await tx.product.updateMany({ where: { storeId: store.id }, data: { isAvailable: false } });
      await tx.store.update({ where: { id: store.id }, data: { isVerified: false, phone: null, email: null } });
    }

    await tx.courier.updateMany({
      where: { userId },
      data: { name: "Deleted courier", phone: null, email: null, passwordHash: null, isActive: false, isApproved: false, latitude: null, longitude: null },
    });

    await tx.user.update({
      where: { id: userId },
      data: {
        name: "Deleted user",
        email: `deleted-${userId}-${crypto.randomBytes(4).toString("hex")}@deleted.invalid`,
        phone: null,
        avatarUrl: null,
        address: null,
        latitude: null,
        longitude: null,
        passwordHash: crypto.randomBytes(32).toString("hex"),
        isActive: false,
        deletedAt: new Date(),
      },
    });
  });

  await revokeAllSessions(userId);
}
