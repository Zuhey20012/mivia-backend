import { Prisma } from "@prisma/client";

/**
 * What a delivered order means for the store, with the same money rules as payouts
 * (payouts.service.ts#adjustStorePayoutForRefund):
 *  - sales = the item subtotal at full price. Promo and referral discounts are paid by Malvoya and never
 *    reduce the store's sales or payout;
 *  - each refunded return takes back the value of the returned goods (less any written deduction), and the
 *    commission on those goods is given back at the order's own rate (commissionCents / subtotalCents);
 *  - payout = sales − refunds − commission. Delivery, service and small-order fees and tips are not the store's.
 * Used by the monthly statements and the DAC7 report, so both always agree with each other.
 */
export const settlementSelect = {
  id: true, storeId: true, status: true, deliveredAt: true, subtotalCents: true, commissionCents: true, sellerPayoutCents: true,
  items: { select: { id: true, quantity: true, unitCents: true } },
  returns: { select: { id: true, status: true, damageDedCents: true, items: { select: { orderItemId: true, quantity: true } } } },
  payouts: { where: { party: "STORE" }, select: { status: true, amountCents: true } },
} satisfies Prisma.OrderSelect;

export type SettlementOrder = Prisma.OrderGetPayload<{ select: typeof settlementSelect }>;

export type Settlement = {
  itemsCents: number;
  refundsCents: number;
  commissionRate: number;
  commissionCents: number; // net: commission on what the customer kept
  payoutCents: number;
  payoutStatus: "SCHEDULED" | "WAITING_FOR_ACCOUNT" | "PAID" | "CANCELLED" | "FAILED" | "NOT_CREATED";
  fullyRefunded: boolean;
};

export function settle(o: SettlementOrder): Settlement {
  const s = o.subtotalCents;
  const byId = new Map(o.items.map((i) => [i.id, i]));
  let payout = o.sellerPayoutCents;
  let refunds = 0;
  let commissionBack = 0;
  for (const r of [...o.returns].filter((r) => r.status === "REFUNDED").sort((a, b) => a.id - b.id)) {
    // Returns made before 2.8 have no item rows and cover the whole order
    const lines = r.items.length ? r.items : o.items.map((i) => ({ orderItemId: i.id, quantity: i.quantity }));
    const goodsValue = lines.reduce((sum, l) => sum + (byId.get(l.orderItemId)?.unitCents ?? 0) * l.quantity, 0);
    const value = Math.max(0, goodsValue - (r.damageDedCents ?? 0));
    const goods = Math.min(value, s);
    const back = s > 0 ? Math.round((goods * o.commissionCents) / s) : 0;
    refunds += value;
    commissionBack += back;
    payout = Math.max(0, payout - (value - back));
  }
  refunds = Math.min(refunds, s);
  const row = o.payouts[0];
  return {
    itemsCents: s,
    refundsCents: refunds,
    commissionRate: s > 0 ? Math.round((o.commissionCents / s) * 10_000) / 10_000 : 0,
    commissionCents: Math.max(0, o.commissionCents - commissionBack),
    // What was actually transferred, once it has been; otherwise what will be
    payoutCents: row?.status === "PAID" ? row.amountCents : payout,
    payoutStatus: row?.status ?? "NOT_CREATED",
    fullyRefunded: o.status === "REFUNDED" || refunds >= s,
  };
}
