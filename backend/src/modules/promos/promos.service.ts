import { Prisma, PromoCode } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { formatCents } from "../../utils/pricing";

type Db = Prisma.TransactionClient | typeof prisma;

export function normalizeCode(code: string) {
  return code.trim().toUpperCase();
}

/**
 * Finds a promo code and checks that this customer may use it on this subtotal.
 * Throws ApiError(409) with a message the apps can show as is ("Finnish / English").
 * Only PAID orders count as redemptions (PromoRedemption rows); they are released on cancellation.
 */
export async function checkPromo(db: Db, rawCode: string, userId: number, subtotalCents: number, now = new Date()): Promise<PromoCode> {
  const code = normalizeCode(rawCode);
  const promo = code ? await db.promoCode.findUnique({ where: { code } }) : null;
  if (!promo || !promo.active) throw new ApiError("Tarjouskoodi ei ole voimassa. / This promo code is not valid.", 409);
  if (promo.startsAt && promo.startsAt > now) throw new ApiError("Tarjouskoodi ei ole vielä voimassa. / This promo code is not active yet.", 409);
  if (promo.endsAt && promo.endsAt <= now) throw new ApiError("Tarjouskoodi on vanhentunut. / This promo code has expired.", 409);
  if (subtotalCents < promo.minSubtotalCents) {
    const min = formatCents(promo.minSubtotalCents);
    throw new ApiError(`Koodi vaatii vähintään ${min} ostokset. / This code needs at least ${min} of items.`, 409);
  }
  if (promo.firstOrderOnly) {
    const earlier = await db.order.count({
      where: { userId, paymentStatus: { in: ["SUCCEEDED", "REFUNDED"] }, status: { not: "CANCELLED" } },
    });
    if (earlier > 0) throw new ApiError("Koodi on vain ensimmäiseen tilaukseen. / This code is for your first order only.", 409);
  }
  if (promo.maxRedemptions !== null) {
    const used = await db.promoRedemption.count({ where: { promoCodeId: promo.id } });
    if (used >= promo.maxRedemptions) throw new ApiError("Tarjouskoodi on käytetty loppuun. / This promo code has run out.", 409);
  }
  const mine = await db.promoRedemption.count({ where: { promoCodeId: promo.id, userId } });
  if (mine >= promo.perUserLimit) throw new ApiError("Olet jo käyttänyt tämän koodin. / You have already used this promo code.", 409);
  return promo;
}

// ─── Admin ──────────────────────────────────────────────────────────────────

export async function listPromoCodes() {
  const codes = await prisma.promoCode.findMany({
    orderBy: { createdAt: "desc" },
    take: 200,
    include: { _count: { select: { redemptions: true } } },
  });
  const sums = await prisma.promoRedemption.groupBy({
    by: ["promoCodeId"],
    where: { promoCodeId: { in: codes.map((c) => c.id) } },
    _sum: { discountCents: true },
  });
  const discountBy = new Map(sums.map((s) => [s.promoCodeId, s._sum.discountCents ?? 0]));
  return codes.map(({ _count, ...c }) => ({ ...c, redemptionCount: _count.redemptions, discountGivenCents: discountBy.get(c.id) ?? 0 }));
}

export async function createPromoCode(input: {
  code: string; description: string; kind: "PERCENT" | "AMOUNT"; value: number;
  maxDiscountCents?: number | null; minSubtotalCents?: number; firstOrderOnly?: boolean;
  maxRedemptions?: number | null; perUserLimit?: number; startsAt?: string | null; endsAt?: string | null; active?: boolean;
}) {
  const code = normalizeCode(input.code);
  if (await prisma.promoCode.findUnique({ where: { code } })) throw new ApiError("A promo code with this name already exists", 409);
  if (input.startsAt && input.endsAt && new Date(input.endsAt) <= new Date(input.startsAt)) {
    throw new ApiError("The end date must be after the start date");
  }
  return prisma.promoCode.create({
    data: {
      code,
      description: input.description,
      kind: input.kind,
      value: input.value,
      maxDiscountCents: input.maxDiscountCents ?? null,
      minSubtotalCents: input.minSubtotalCents ?? 0,
      firstOrderOnly: input.firstOrderOnly ?? false,
      maxRedemptions: input.maxRedemptions ?? null,
      perUserLimit: input.perUserLimit ?? 1,
      startsAt: input.startsAt ? new Date(input.startsAt) : null,
      endsAt: input.endsAt ? new Date(input.endsAt) : null,
      active: input.active ?? true,
    },
  });
}

/** Activate/deactivate, change the end date, description or redemption cap. Paid orders keep their discount. */
export async function updatePromoCode(id: number, input: {
  active?: boolean; endsAt?: string | null; description?: string; maxRedemptions?: number | null;
}) {
  const promo = await prisma.promoCode.findUnique({ where: { id } });
  if (!promo) throw new ApiError("Promo code not found", 404);
  if (input.endsAt && promo.startsAt && new Date(input.endsAt) <= promo.startsAt) {
    throw new ApiError("The end date must be after the start date");
  }
  return prisma.promoCode.update({
    where: { id },
    data: {
      ...(input.active !== undefined ? { active: input.active } : {}),
      ...(input.endsAt !== undefined ? { endsAt: input.endsAt ? new Date(input.endsAt) : null } : {}),
      ...(input.description !== undefined ? { description: input.description } : {}),
      ...(input.maxRedemptions !== undefined ? { maxRedemptions: input.maxRedemptions } : {}),
    },
  });
}
