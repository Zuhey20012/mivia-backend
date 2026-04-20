import { env } from "../config/env";

/**
 * Calculate all pricing fields for a SALE order.
 * All values returned in cents (integers).
 */
export function calcOrderPricing(subtotalCents: number) {
  const commissionCents    = Math.round(subtotalCents * env.commissionRate);
  const sellerPayoutCents  = subtotalCents - commissionCents;
  const deliveryFeeCents   = env.deliveryFeeCents;
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
  const subtotalCents    = dailyCents * quantity * days;
  const commissionCents  = Math.round(subtotalCents * env.commissionRate);
  const deliveryFeeCents = env.deliveryFeeCents;
  const totalCents       = subtotalCents + depositCents + deliveryFeeCents;
  return { subtotalCents, commissionCents, depositCents, deliveryFeeCents, totalCents };
}

/**
 * Format cents to a display string.
 * e.g. 4999 → "$49.99"
 */
export function formatCents(cents: number, currency = "USD"): string {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}
