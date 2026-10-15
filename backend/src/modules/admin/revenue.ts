export type RevenueSums = {
  commissionCents: number | null; serviceFeeCents: number | null; smallOrderFeeCents: number | null; discountCents: number | null;
  deliveryFeeCents: number | null; courierFeeCents: number | null; tipCents: number | null;
};

/**
 * What Malvoya keeps: commission + fees + the part of the delivery fee not paid to couriers − promo discounts.
 * Sums over paid orders that were not refunded or cancelled (GET /admin/stats, /admin/analytics).
 */
export function platformRevenue(sum: RevenueSums) {
  const commissionCents = Number(sum.commissionCents ?? 0);
  const serviceFeeCents = Number(sum.serviceFeeCents ?? 0);
  const smallOrderFeeCents = Number(sum.smallOrderFeeCents ?? 0);
  const discountCents = Number(sum.discountCents ?? 0);
  // courierFeeCents includes tips, which are not Malvoya's money
  const deliveryMarginCents = Number(sum.deliveryFeeCents ?? 0) - (Number(sum.courierFeeCents ?? 0) - Number(sum.tipCents ?? 0));
  return {
    commissionCents, serviceFeeCents, smallOrderFeeCents, deliveryMarginCents, discountCents,
    netPlatformRevenueCents: commissionCents + serviceFeeCents + smallOrderFeeCents + deliveryMarginCents - discountCents,
  };
}
