import { env, PricingConfig } from "../config/env";

/**
 * Delivery fee shown in the store list AND charged at checkout — they must always match
 * (Kuluttajansuojalaki 2:8: the advertised total price must include all fees).
 * Unknown distance falls back to the flat fee.
 */
export function deliveryFeeForDistance(distanceKm: number | null): number {
  if (distanceKm === null || !Number.isFinite(distanceKm)) return env.deliveryFeeCents;
  if (distanceKm <= 1.5) return 190;
  return Math.min(690, 190 + Math.round((distanceKm - 1.5) * 50));
}

/** Stripe will not charge less than 0,50 € in EUR, so a discount never takes the total below this. */
export const MIN_CHARGE_CENTS = 50;

/** Service fee: a percentage of the item subtotal, clamped to min/max (max 0 = no cap). 0 when the percent is 0. */
export function serviceFeeFor(subtotalCents: number, cfg: PricingConfig = env.pricing): number {
  if (cfg.serviceFeePercent <= 0 || subtotalCents <= 0) return 0;
  let fee = Math.round((subtotalCents * cfg.serviceFeePercent) / 100);
  fee = Math.max(fee, cfg.serviceFeeMinCents);
  if (cfg.serviceFeeMaxCents > 0) fee = Math.min(fee, cfg.serviceFeeMaxCents);
  return fee;
}

/** Small-order fee: charged when the item subtotal is below the threshold (threshold 0 = off). */
export function smallOrderFeeFor(subtotalCents: number, cfg: PricingConfig = env.pricing): number {
  return cfg.smallOrderThresholdCents > 0 && subtotalCents < cfg.smallOrderThresholdCents ? cfg.smallOrderFeeCents : 0;
}

export type PromoTerms = { kind: "PERCENT" | "AMOUNT"; value: number; maxDiscountCents: number | null };

/** Discount of a promo code on the item subtotal, before the minimum-charge rule. Never more than the subtotal. */
export function promoDiscountFor(subtotalCents: number, promo: PromoTerms): number {
  let d = promo.kind === "PERCENT" ? Math.round((subtotalCents * promo.value) / 100) : promo.value;
  if (promo.maxDiscountCents !== null && promo.maxDiscountCents !== undefined) d = Math.min(d, promo.maxDiscountCents);
  return Math.max(0, Math.min(d, subtotalCents));
}

export type CheckoutPricing = {
  subtotalCents: number;
  commissionCents: number;
  sellerPayoutCents: number;
  deliveryFeeCents: number;
  serviceFeeCents: number;
  smallOrderFeeCents: number;
  discountCents: number;
  tipCents: number;
  totalCents: number;
  courierFeeCents: number;
};

/**
 * Every money field of a SALE order, in cents, VAT included. The quote and createOrder both use this,
 * so the price shown before payment is exactly the price charged.
 *  total = subtotal + delivery + service fee + small-order fee + tip − discount (never below 0,50 €)
 * The discount is paid by Malvoya: the store's commission/payout and the courier's pay are computed
 * as if there were no discount. The tip goes to the courier in full and carries no commission.
 */
export function calcCheckoutPricing(input: {
  subtotalCents: number;
  commissionRate: number;
  deliveryFeeCents: number;
  tipCents?: number;
  promo?: PromoTerms | null;
  config?: PricingConfig;
  courierFeeShare?: number;
}): CheckoutPricing {
  const cfg = input.config ?? env.pricing;
  const share = input.courierFeeShare ?? env.courierFeeShare;
  const { subtotalCents, deliveryFeeCents } = input;
  const tipCents = input.tipCents ?? 0;
  const commissionCents = Math.round(subtotalCents * input.commissionRate);
  const sellerPayoutCents = subtotalCents - commissionCents;
  const serviceFeeCents = serviceFeeFor(subtotalCents, cfg);
  const smallOrderFeeCents = smallOrderFeeFor(subtotalCents, cfg);
  const gross = subtotalCents + deliveryFeeCents + serviceFeeCents + smallOrderFeeCents + tipCents;
  const discountCents = input.promo
    ? Math.max(0, Math.min(promoDiscountFor(subtotalCents, input.promo), gross - MIN_CHARGE_CENTS))
    : 0;
  return {
    subtotalCents,
    commissionCents,
    sellerPayoutCents,
    deliveryFeeCents,
    serviceFeeCents,
    smallOrderFeeCents,
    discountCents,
    tipCents,
    totalCents: gross - discountCents,
    courierFeeCents: Math.round(deliveryFeeCents * share) + tipCents,
  };
}

/**
 * Calculate all pricing fields for a RENTAL.
 */
export function calcRentalPricing(
  dailyCents: number,
  quantity: number,
  days: number,
  depositCents: number
) {
  const subtotalCents = dailyCents * quantity * days;
  return { subtotalCents, depositCents: depositCents * quantity };
}

/** e.g. 4999 → "49,99 €" */
export function formatCents(cents: number, locale = "fi-FI"): string {
  return new Intl.NumberFormat(locale, { style: "currency", currency: "EUR" }).format(cents / 100);
}
