import bcrypt from "bcryptjs";
import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { verifyRefreshToken } from "../../utils/jwt";
import { RegisterInput, LoginInput } from "./auth.schema";
import { issueSession, hashToken, revokeAllSessions, isMfaChallenge } from "./session";
import { AcceptContext, recordAcceptances, registrationVersions } from "../legal/agreements";
import { mainDocForRole } from "../legal/legalDocs";
import { forgetSessionState } from "../../middleware/auth";
import { deleteFirebaseUser, deleteStoreMedia } from "./accountCleanup";
import { TWO_STEP_OFF } from "./twoStepFields";
import { disconnectUser } from "../../lib/socket";
import { endLivesOfStore } from "../live/live.service";

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

/**
 * Verified sign-ins (Google, Apple, Firebase phone, one-time code) find existing accounts by email or phone.
 * Accounts made by /register have a bcrypt password and an email/phone nobody proved, so whoever registered
 * may not own them: opening the account here would let someone pre-register a victim's address and keep
 * access to everything the victim later puts in it. Those accounts sign in with their password instead.
 */
export function assertVerifiedSignInAllowed(user: { passwordHash: string }) {
  if (user.passwordHash.startsWith("$2")) {
    throw new AuthError("An account with this email or phone number already exists. Please sign in with your password.", 409);
  }
}

export async function registerUser(input: RegisterInput, ctx: AcceptContext = { ip: null, userAgent: null, appVersion: null }) {
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
  // The versions in force of the role's documents (customers: Terms of Service + Privacy Policy acknowledgement)
  const accepted = input.acceptTerms ? await registrationVersions(input.role) : [];
  const main = accepted.find((a) => a.doc === mainDocForRole(input.role));
  const now = new Date();
  const user = await prisma.user.create({
    data: {
      name: input.name, email, phone, passwordHash, role: input.role,
      // The schema refuses registration without ageConfirmed: true (2.16.0)
      ageConfirmedAt: now,
      ...(input.acceptTerms ? { termsAcceptedAt: now, termsVersion: main?.version ?? null } : {}),
    },
    select: { id: true, name: true, email: true, role: true, passwordHash: true },
  });
  // Clickwrap proof: one AgreementAcceptance per document, with time, version, truncated address and app version
  await recordAcceptances(user.id, accepted, "register", ctx);

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
  let mfa = false;
  try {
    mfa = verifyRefreshToken(refreshToken).mfa;
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
  const session = await issueSession(stored.user, { mfa });
  // Turning two-step sign-in on ends every older session, so this only happens to a token from before that
  if (isMfaChallenge(session)) throw new AuthError("Please sign in again", 401);
  return session;
}

/**
 * Signed-in password change. Wrong current password → 400. Every other session ends (refresh tokens revoked, older
 * access tokens refused); the caller gets a fresh session in the same shape as login and stays signed in.
 */
export async function changePassword(userId: number, currentPassword: string, newPassword: string, mfa = false) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.isActive) throw new AuthError("Account not found", 404);
  if (!user.passwordHash.startsWith("$2")) {
    throw new AuthError("This account signs in without a password (Google, phone or email code), so there is no password to change.", 400);
  }
  if (!(await bcrypt.compare(currentPassword, user.passwordHash))) throw new AuthError("The current password is wrong", 400);
  const passwordHash = await bcrypt.hash(newPassword, 12);
  const updated = await prisma.user.update({ where: { id: userId }, data: { passwordHash, tokensValidAfter: new Date() } });
  await revokeAllSessions(userId);
  forgetSessionState(userId);
  // The caller is signed in: the new session keeps whether theirs passed two-step sign-in
  return issueSession(updated, { mfa });
}

export async function logoutUser(refreshToken: string) {
  await prisma.refreshToken.deleteMany({ where: { token: hashToken(refreshToken) } });
}

// ─── GDPR: access (Art. 15/20) and erasure (Art. 17) ────────────────────────

export async function exportUserData(userId: number) {
  const [user, supportRequests, chatMessages, productReports, liveMessages] = await Promise.all([exportUser(userId), prisma.supportRequest.findMany({
    where: { userId }, select: { id: true, topic: true, message: true, status: true, createdAt: true },
  }), prisma.orderMessage.findMany({
    where: { senderId: userId }, select: { orderId: true, text: true, createdAt: true }, orderBy: { createdAt: "desc" }, take: 5000,
  }), prisma.productReport.findMany({
    // "Report this product" notices the user sent (2.12)
    where: { reporterId: userId }, select: { productId: true, reason: true, details: true, ipNotice: true, status: true, createdAt: true }, take: 1000,
  }), prisma.liveMessage.findMany({
    // Messages written in stores' live streams (2.15), kept 30 days after each live
    where: { userId }, select: { liveId: true, text: true, hidden: true, createdAt: true }, orderBy: { id: "desc" }, take: 5000,
  })]);
  return user && { ...user, supportRequests, chatMessages, productReports, liveMessages };
}

function exportUser(userId: number) {
  return prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true, email: true, name: true, phone: true, role: true, avatarUrl: true, googleSub: true,
      address: true, latitude: true, longitude: true, createdAt: true, updatedAt: true,
      locale: true, termsAcceptedAt: true, termsVersion: true, totpEnabledAt: true,
      ageConfirmedAt: true, emailMarketingOptOutAt: true,
      // Every agreement version accepted, with time, method, truncated address and app version (2.11)
      agreementAcceptances: { select: { doc: true, version: true, acceptedAt: true, method: true, ip: true, userAgent: true, appVersion: true } },
      blocks: { select: { blockedId: true, createdAt: true } },
      orders: { include: { items: true } },
      rentals: { include: { items: true } },
      returns: true,
      store: {
        include: {
          products: true,
          drops: { select: { id: true, caption: true, status: true, createdAt: true, likeCount: true, viewCount: true } },
          // Live streams (2.15): nothing is recorded; title, products and counts only
          lives: { select: { id: true, title: true, productIds: true, status: true, startedAt: true, endedAt: true, endedReason: true, viewerPeak: true, likeCount: true }, orderBy: { id: "desc" }, take: 1000 },
          // DAC7 seller data; the tax ID itself stays encrypted (shown masked in the store app)
          taxInfo: { select: { legalName: true, dateOfBirth: true, vatNumber: true, addressLine: true, postalCode: true, city: true, country: true, createdAt: true, updatedAt: true } },
        },
      },
      courier: { select: { id: true, name: true, phone: true, email: true, isApproved: true, createdAt: true, rating: true } },
      favorites: { select: { productId: true, createdAt: true } },
      dropLikes: { select: { dropId: true, createdAt: true } },
      // Saved drops and "Not interested" marks (2.14)
      dropSaves: { select: { dropId: true, createdAt: true }, orderBy: { id: "desc" }, take: 5000 },
      dropHides: { select: { dropId: true, createdAt: true }, take: 5000 },
      reviews: { select: { orderId: true, storeRating: true, courierRating: true, comment: true, createdAt: true } },
      devices: { select: { platform: true, createdAt: true, updatedAt: true } },
      dropComments: { where: { status: { not: "REMOVED" } }, select: { dropId: true, body: true, status: true, createdAt: true } },
      follows: { select: { storeId: true, createdAt: true } },
      launchAlert: { select: { latitude: true, longitude: true, area: true, notifiedAt: true, createdAt: true } },
      referralCode: true,
      referralsMade: { select: { createdAt: true, rewardedAt: true } },
      personalPromos: { select: { code: true, description: true, value: true, active: true, createdAt: true } },
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
  // Needed for the clean-up outside the database once the account is anonymised
  const before = await prisma.user.findUnique({ where: { id: userId }, select: { email: true, phone: true, store: { select: { id: true } } } });

  await prisma.$transaction(async (tx) => {
    // Delivery addresses and notes are not needed for bookkeeping once an order is closed
    await tx.order.updateMany({
      where: { userId },
      data: { deliveryAddress: null, deliveryLat: null, deliveryLng: null, notes: null },
    });

    const store = await tx.store.findUnique({ where: { ownerId: userId } });
    if (store) {
      // The store's legal identity stays on past orders; it just stops trading. Its DAC7 tax data (StoreTaxInfo)
      // is kept: the law requires 10 years' retention after the reporting year (GDPR Art. 17(3)(b)).
      await tx.product.updateMany({ where: { storeId: store.id }, data: { isAvailable: false } });
      await tx.store.update({ where: { id: store.id }, data: { isVerified: false, phone: null, email: null } });
    }

    // Likes, favourites and push devices go; reviews stay (they carry store ratings) without their text
    await tx.dropLike.deleteMany({ where: { userId } });
    // Saves and "Not interested" marks (2.14); each saved drop's count goes down by one
    const saves = await tx.dropSave.findMany({ where: { userId }, select: { dropId: true } });
    if (saves.length) {
      await tx.drop.updateMany({ where: { id: { in: saves.map((v) => v.dropId) }, saveCount: { gt: 0 } }, data: { saveCount: { decrement: 1 } } });
      await tx.dropSave.deleteMany({ where: { userId } });
    }
    await tx.dropHide.deleteMany({ where: { userId } });
    await tx.supportRequest.deleteMany({ where: { userId } });
    await tx.favorite.deleteMany({ where: { userId } });
    await tx.deviceToken.deleteMany({ where: { userId } });
    await tx.storeFollow.deleteMany({ where: { userId } });
    await tx.launchAlert.deleteMany({ where: { userId } });
    // The invite code stops working; unused personal reward codes are switched off
    await tx.promoCode.updateMany({ where: { userId }, data: { active: false } });
    // Comments are personal data: remove them and keep each drop's visible-comment count right
    const visible = await tx.dropComment.groupBy({ by: ["dropId"], where: { userId, status: "VISIBLE" }, _count: { _all: true } });
    for (const v of visible) {
      await tx.drop.update({ where: { id: v.dropId }, data: { commentCount: { decrement: v._count._all } } });
    }
    await tx.dropComment.deleteMany({ where: { userId } });
    // Chat messages, blocks and review reports are personal data too
    await tx.orderMessage.deleteMany({ where: { senderId: userId } });
    // Live chat messages and mutes (2.15)
    await tx.liveMessage.deleteMany({ where: { userId } });
    await tx.liveBan.deleteMany({ where: { userId } });
    await tx.userBlock.deleteMany({ where: { OR: [{ blockerId: userId }, { blockedId: userId }] } });
    await tx.reviewReport.deleteMany({ where: { reporterId: userId } });
    // Copyright / trademark notices (2.16) keep the claim (work, location, statement) but drop the person's name and email
    await tx.$executeRaw`UPDATE "ProductReport" SET "ipNotice" = "ipNotice" - 'name' - 'email' - 'onBehalfOf' WHERE "reporterId" = ${userId} AND "ipNotice" IS NOT NULL`;
    await tx.$executeRaw`UPDATE "DropReport" SET "ipNotice" = "ipNotice" - 'name' - 'email' - 'onBehalfOf' WHERE "reporterId" = ${userId} AND "ipNotice" IS NOT NULL`;
    await tx.$executeRaw`UPDATE "DropCommentReport" SET "ipNotice" = "ipNotice" - 'name' - 'email' - 'onBehalfOf' WHERE "reporterId" = ${userId} AND "ipNotice" IS NOT NULL`;
    // Product reports stay (product-safety notices must be processed) but no longer point at the person
    await tx.productReport.updateMany({ where: { reporterId: userId }, data: { reporterId: null, reporterEmail: null } });
    await tx.review.updateMany({ where: { userId }, data: { comment: null } });
    if (store) {
      await tx.drop.updateMany({ where: { storeId: store.id, status: { in: ["READY", "PROCESSING"] } }, data: { status: "REMOVED", removedReason: "Store account deleted" } });
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
        googleSub: null,
        appleSub: null,
        referralCode: null,
        locale: null,
        ...TWO_STEP_OFF,
        isActive: false,
        deletedAt: new Date(),
      },
    });
  });

  await revokeAllSessions(userId);
  forgetSessionState(userId);
  disconnectUser(userId);
  // A store that was live stops at once (viewers are told the live ended)
  if (before?.store) await endLivesOfStore(before.store.id).catch(() => {});
  // Outside the database (best effort, logged on failure, never blocks the deletion): the Firebase sign-in user
  // and, for a store, its photos, videos and drops on Cloudinary
  if (before) {
    deleteFirebaseUser({ email: before.email, phone: before.phone }).catch(() => {});
    deleteStoreMedia(before.store?.id ?? null, userId).catch(() => {});
  }
}
