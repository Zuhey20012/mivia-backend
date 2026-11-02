import pino from "pino";
import { prisma } from "../../lib/prisma";
import { getStripe } from "../../lib/stripe";
import { alertAdmins } from "../../lib/adminAlerts";
import { adjustStorePayoutForRefund } from "../payouts/payouts.service";
import { emitOrderStatus } from "../../lib/socket";

const logger = pino({ name: "disputes" });

/** Dispute statuses after which the store's payout may go out again (Malvoya kept the money). */
export const DISPUTE_SETTLED_OK = ["won", "warning_closed"];

async function orderForPaymentIntent(paymentIntentId: string | null | undefined) {
  if (!paymentIntentId) return null;
  return prisma.order.findFirst({
    where: { stripePaymentIntentId: paymentIntentId },
    select: { id: true, storeId: true, totalCents: true, refundedCents: true, externalRefundedCents: true, disputedAt: true },
  });
}

async function paymentIntentOfCharge(chargeId: unknown): Promise<string | null> {
  if (typeof chargeId !== "string" || !chargeId) return null;
  try {
    const ch = await getStripe().charges.retrieve(chargeId);
    return typeof ch.payment_intent === "string" ? ch.payment_intent : ch.payment_intent?.id ?? null;
  } catch {
    return null;
  }
}

/**
 * charge.dispute.created / .updated / .closed (2.17): the customer's bank opened a chargeback. The order is flagged
 * (Order.disputedAt, disputeStatus), the store's unpaid payout for it is frozen (processDuePayouts skips it until the
 * dispute is won), admins are pushed and emailed, and System → attention lists it.
 */
export async function handleDispute(eventType: string, dispute: any) {
  const pi = typeof dispute?.payment_intent === "string" ? dispute.payment_intent : await paymentIntentOfCharge(dispute?.charge);
  const order = await orderForPaymentIntent(pi);
  if (!order) {
    logger.warn({ disputeId: dispute?.id }, "Dispute for an unknown payment");
    return;
  }
  const status = typeof dispute?.status === "string" ? dispute.status.slice(0, 40) : eventType.endsWith("closed") ? "closed" : "needs_response";
  await prisma.order.update({
    where: { id: order.id },
    data: {
      disputedAt: order.disputedAt ?? new Date(),
      disputeStatus: status,
      disputeId: typeof dispute?.id === "string" ? dispute.id.slice(0, 100) : undefined,
      disputeReason: typeof dispute?.reason === "string" ? dispute.reason.slice(0, 100) : undefined,
    },
  });
  emitOrderStatus(order.id, { disputeStatus: status });
  const amount = Number(dispute?.amount);
  const euros = Number.isFinite(amount) ? `${(amount / 100).toFixed(2)} €` : "";
  if (eventType === "charge.dispute.created") {
    await alertAdmins(`Chargeback on order #${order.id}`, [
      `The customer's bank opened a dispute${euros ? ` of ${euros}` : ""} (reason: ${dispute?.reason ?? "not given"}).`,
      "The store's payout for this order is held until the dispute is won. Answer it in the Stripe dashboard before the deadline.",
    ], { type: "dispute", orderId: String(order.id) });
  } else if (eventType === "charge.dispute.closed") {
    await alertAdmins(`Chargeback on order #${order.id} closed: ${status}`, [
      DISPUTE_SETTLED_OK.includes(status) ? "The store's payout is released as usual." : "The dispute was lost: the store's payout stays held; decide with the store (Disputes).",
    ], { type: "dispute", orderId: String(order.id) });
  }
}

/**
 * charge.refunded (2.17): refunds made outside Malvoya (Stripe dashboard) are synced into Order.refundedCents and
 * reduce the store payout like any refund. Malvoya's own refunds carry metadata.source = "malvoya" (or a returnId)
 * and are already counted, so the sync is idempotent and never counts them twice.
 */
export async function handleChargeRefunded(charge: any) {
  const pi = typeof charge?.payment_intent === "string" ? charge.payment_intent : charge?.payment_intent?.id;
  const order = await orderForPaymentIntent(pi);
  if (!order) return;
  let refunds: any[] | null = Array.isArray(charge?.refunds?.data) && charge.refunds.has_more !== true ? charge.refunds.data : null;
  if (!refunds) {
    try {
      refunds = (await getStripe().refunds.list({ payment_intent: pi, limit: 100 })).data;
    } catch (e: any) {
      logger.warn({ orderId: order.id, err: e?.message }, "Refunds not listed; sync skipped");
      return;
    }
  }
  const external = refunds
    .filter((r) => (r?.status === "succeeded" || r?.status === "pending") && r?.metadata?.source !== "malvoya" && !r?.metadata?.returnId)
    .reduce((sum, r) => sum + (Number(r.amount) || 0), 0);
  const diff = external - order.externalRefundedCents;
  if (diff <= 0) return;
  // Conditional on the value read, so two deliveries of the same event cannot both count it
  const done = await prisma.order.updateMany({
    where: { id: order.id, externalRefundedCents: order.externalRefundedCents },
    data: { externalRefundedCents: external, refundedCents: { increment: diff } },
  });
  if (!done.count) return;
  const after = await prisma.order.findUniqueOrThrow({ where: { id: order.id }, select: { refundedCents: true, totalCents: true } });
  if (after.refundedCents >= after.totalCents) await prisma.order.update({ where: { id: order.id }, data: { paymentStatus: "REFUNDED" } });
  await adjustStorePayoutForRefund(order.id, diff);
  logger.info({ orderId: order.id, cents: diff }, "Refund made outside Malvoya synced");
}
