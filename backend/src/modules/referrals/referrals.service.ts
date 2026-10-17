import crypto from "crypto";
import { Prisma } from "@prisma/client";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { ApiError } from "../../lib/errors";
import { pushToUser } from "../../lib/push";
import { euros, t } from "../../lib/i18n";
import { PromoTerms, formatCents } from "../../utils/pricing";

const logger = pino({ name: "referrals" });

type Db = Prisma.TransactionClient | typeof prisma;

/** No 0/O, 1/I/L: easy to read out and type. */
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const REFERRAL_CODE = /^[A-Z0-9]{8}$/;

function randomCode(length: number) {
  let out = "";
  for (let i = 0; i < length; i++) out += ALPHABET[crypto.randomInt(ALPHABET.length)];
  return out;
}

/** Referrals are on only while the new customer actually gets something (REFERRAL_DISCOUNT_CENTS > 0). */
export function referralsEnabled() {
  return env.referral.discountCents > 0;
}

/** A discount found for a checkout: a promo code or a friend's invite code. */
export type CheckoutDiscount = {
  terms: PromoTerms;
  promoCodeId: number | null;
  referrerId: number | null;
  code: string;
  description: string;
};

const moneyEn = (c: number) => `${(c / 100).toFixed(2)} €`;
const moneyFi = (c: number) => formatCents(c);

/**
 * An invite code at checkout. Returns null when the code is not an invite code (or referrals are off), so the
 * caller treats it as a promo code. Throws ApiError(409) with a readable reason when it is one but cannot be used.
 * Works like a platform-funded, first-order-only AMOUNT promo of REFERRAL_DISCOUNT_CENTS.
 */
export async function checkReferralCode(db: Db, code: string, userId: number): Promise<CheckoutDiscount | null> {
  if (!referralsEnabled() || !REFERRAL_CODE.test(code)) return null;
  const referrer = await db.user.findUnique({ where: { referralCode: code }, select: { id: true, isActive: true, deletedAt: true } });
  if (!referrer) return null;
  if (!referrer.isActive || referrer.deletedAt) {
    throw new ApiError("Kutsukoodi ei ole enää voimassa. / This invite code is no longer valid.", 409);
  }
  if (referrer.id === userId) throw new ApiError("Et voi käyttää omaa kutsukoodiasi. / You can't use your own invite code.", 409);
  const earlier = await db.order.count({
    where: { userId, paymentStatus: { in: ["SUCCEEDED", "REFUNDED"] }, status: { not: "CANCELLED" } },
  });
  if (earlier > 0) {
    throw new ApiError("Kutsukoodi on vain uuden asiakkaan ensimmäiseen tilaukseen. / Invite codes are for a new customer's first order only.", 409);
  }
  if (await db.referral.findUnique({ where: { refereeId: userId }, select: { id: true } })) {
    throw new ApiError("Olet jo käyttänyt kutsukoodin. / You have already used an invite code.", 409);
  }
  const cents = env.referral.discountCents;
  return {
    terms: { kind: "AMOUNT", value: cents, maxDiscountCents: null },
    promoCodeId: null,
    referrerId: referrer.id,
    code,
    description: `Kaverin kutsu: ${moneyFi(cents)} alennus ensimmäisestä tilauksesta / Invite from a friend: ${moneyEn(cents)} off your first order`,
  };
}

/** The user's own invite code, created the first time it is asked for. Never collides with a promo code. */
export async function ensureReferralCode(userId: number): Promise<string> {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { referralCode: true } });
  if (!user) throw new ApiError("Account not found", 404);
  if (user.referralCode) return user.referralCode;
  for (let i = 0; i < 10; i++) {
    const code = randomCode(8);
    if (await prisma.promoCode.findUnique({ where: { code }, select: { id: true } })) continue;
    try {
      await prisma.user.updateMany({ where: { id: userId, referralCode: null }, data: { referralCode: code } });
      const now = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { referralCode: true } });
      if (now.referralCode) return now.referralCode;
    } catch (e: any) {
      if (e?.code !== "P2002") throw e; // taken by someone else: try another
    }
  }
  throw new ApiError("Could not create an invite code, please try again", 503);
}

/** Plain-language terms shown next to the code (fi/en). Honest about what each side gets and when. */
export function referralTerms() {
  const { discountCents, rewardCents } = env.referral;
  if (!referralsEnabled()) {
    return {
      en: "Invites are not available right now.",
      fi: "Kutsut eivät ole juuri nyt käytössä.",
    };
  }
  const rewardEn = rewardCents > 0
    ? ` When their order has been delivered or collected, you get a one-time code worth ${moneyEn(rewardCents)} for your next order.`
    : "";
  const rewardFi = rewardCents > 0
    ? ` Kun tilaus on toimitettu tai noudettu, saat ${moneyFi(rewardCents)} arvoisen kertakäyttöisen koodin seuraavaan tilaukseesi.`
    : "";
  return {
    en: `A friend who is new to Malvoya gets ${moneyEn(discountCents)} off their first order with your code (one invite per new customer).${rewardEn} Codes have no cash value. Malvoya can end invites at any time; codes already earned stay valid. Misuse, such as fake accounts or inviting yourself, voids the reward.`,
    fi: `Malvoyan uusi asiakas saa koodillasi ${moneyFi(discountCents)} alennuksen ensimmäisestä tilauksestaan (yksi kutsu uutta asiakasta kohden).${rewardFi} Koodeilla ei ole rahallista arvoa. Malvoya voi lopettaa kutsut milloin tahansa; jo ansaitut koodit pysyvät voimassa. Väärinkäyttö, kuten valetilit tai itsensä kutsuminen, mitätöi palkkion.`,
  };
}

/** GET /me/referral */
export async function referralInfo(userId: number) {
  const code = await ensureReferralCode(userId);
  const [invited, rewarded] = await Promise.all([
    prisma.referral.count({ where: { referrerId: userId } }),
    prisma.referral.count({ where: { referrerId: userId, rewardedAt: { not: null } } }),
  ]);
  return {
    enabled: referralsEnabled(),
    code,
    shareUrl: `${env.publicApiUrl}/r/${code}`,
    discountCents: env.referral.discountCents,
    rewardCents: env.referral.rewardCents,
    invited,
    rewarded,
    terms: referralTerms(),
  };
}

/** For the public invite page: is this code usable right now? */
export async function inviteForCode(rawCode: string) {
  const code = rawCode.trim().toUpperCase();
  if (!referralsEnabled() || !REFERRAL_CODE.test(code)) return null;
  const user = await prisma.user.findUnique({ where: { referralCode: code }, select: { isActive: true, deletedAt: true } });
  if (!user || !user.isActive || user.deletedAt) return null;
  return { code, discountCents: env.referral.discountCents };
}

/**
 * The referee's first order was delivered (or collected): the referrer gets a personal one-time promo code
 * (only they can use it, once) and a push. Idempotent; nothing happens while REFERRAL_REWARD_CENTS is 0.
 */
export async function rewardReferralForOrder(orderId: number) {
  const rewardCents = env.referral.rewardCents;
  if (rewardCents <= 0) return;
  const ref = await prisma.referral.findUnique({
    where: { orderId },
    include: { referrer: { select: { id: true, isActive: true, deletedAt: true } }, order: { select: { status: true } } },
  });
  if (!ref || ref.rewardedAt || ref.order.status !== "DELIVERED") return;
  if (!ref.referrer.isActive || ref.referrer.deletedAt) return;
  const claimed = await prisma.referral.updateMany({ where: { id: ref.id, rewardedAt: null }, data: { rewardedAt: new Date() } });
  if (!claimed.count) return;

  let promo = null;
  for (let i = 0; i < 10 && !promo; i++) {
    const code = `KIITOS-${randomCode(6)}`;
    try {
      promo = await prisma.promoCode.create({
        data: {
          code,
          description: `Kiitos kutsusta: ${moneyFi(rewardCents)} alennus / Thanks for inviting a friend: ${moneyEn(rewardCents)} off`,
          kind: "AMOUNT",
          value: rewardCents,
          perUserLimit: 1,
          maxRedemptions: 1,
          userId: ref.referrerId,
        },
      });
    } catch (e: any) {
      if (e?.code !== "P2002") throw e;
    }
  }
  if (!promo) {
    logger.error({ referralId: ref.id }, "Could not create the referral reward code");
    await prisma.referral.update({ where: { id: ref.id }, data: { rewardedAt: null } });
    return;
  }
  await prisma.referral.update({ where: { id: ref.id }, data: { rewardPromoCodeId: promo.id } });
  pushToUser(ref.referrerId, {
    title: t(`You earned ${moneyEn(rewardCents)} off`, `Ansaitsit ${euros(rewardCents).fi} alennuksen`),
    body: t(`A friend you invited got their first Malvoya order. Use code ${promo.code} at checkout.`, `Kutsumasi kaveri sai ensimmäisen Malvoya-tilauksensa. Käytä koodia ${promo.code} kassalla.`),
    data: { type: "referral", code: promo.code },
  }).catch(() => {});
}

/** Admin system status: settings and counts. */
export async function referralSummary() {
  const [referrals, rewarded, discount] = await Promise.all([
    prisma.referral.count(),
    prisma.referral.count({ where: { rewardedAt: { not: null } } }),
    prisma.order.aggregate({
      where: { referrerId: { not: null }, paymentStatus: "SUCCEEDED", status: { not: "CANCELLED" } },
      _sum: { discountCents: true },
    }),
  ]);
  return {
    enabled: referralsEnabled(),
    discountCents: env.referral.discountCents,
    rewardCents: env.referral.rewardCents,
    referrals,
    rewarded,
    discountGivenCents: discount._sum.discountCents ?? 0,
  };
}
