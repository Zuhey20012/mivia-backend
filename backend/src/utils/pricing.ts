import { env } from "../config/env";

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

/**
 * Calculate all pricing fields for a SALE order. All values in cents, VAT included.
 */
export function calcOrderPricing(subtotalCents: number, commissionRate: number, deliveryFeeCents: number) {
  const commissionCents    = Math.round(subtotalCents * commissionRate);
  const sellerPayoutCents  = subtotalCents - commissionCents;
  const totalCents         = subtotalCents + deliveryFeeCents;
  return { subtotalCents, commissionCents, sellerPayoutCents, deliveryFeeCents, totalCents };
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
