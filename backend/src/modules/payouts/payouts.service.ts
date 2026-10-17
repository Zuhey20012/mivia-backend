import pino from "pino";
import { prisma } from "../../lib/prisma";
import { getStripe } from "../../lib/stripe";
import { ApiError } from "../../lib/errors";
import { env } from "../../config/env";
import { pushToUser } from "../../lib/push";
import { euros, t } from "../../lib/i18n";

const logger = pino({ name: "payouts" });

type Actor = { id: number; role: string };
type Party = { kind: "STORE"; id: number; accountId: string | null; email: string; individual: boolean; name: string }
  | { kind: "COURIER"; id: number; accountId: string | null; email: string; individual: true; name: string };

async function partyFor(actor: Actor): Promise<Party> {
  const user = await prisma.user.findUnique({ where: { id: actor.id }, select: { email: true } });
  if (!user) throw new ApiError("Account not found", 404);
  if (actor.role === "VENDOR") {
    const store = await prisma.store.findUnique({ where: { ownerId: actor.id } });
    if (!store) throw new ApiError("Create your store first", 409);
    return { kind: "STORE", id: store.id, accountId: store.stripeAccountId, email: store.email ?? user.email, individual: store.sellerType === "PRIVATE", name: store.name };
  }
  if (actor.role === "COURIER") {
    const courier = await prisma.courier.findUnique({ where: { userId: actor.id } });
    if (!courier) throw new ApiError("Courier profile not found", 404);
    if (!courier.isApproved) throw new ApiError("You can set up payouts once your account is approved", 403);
    return { kind: "COURIER", id: courier.id, accountId: courier.stripeAccountId, email: user.email, individual: true, name: courier.name };
  }
  throw new ApiError("Payouts are for stores and couriers", 403);
}

async function saveAccount(party: Party, accountId: string, payoutsEnabled?: boolean) {
  const data = { stripeAccountId: accountId, ...(payoutsEnabled !== undefined ? { payoutsEnabled } : {}) };
  if (party.kind === "STORE") await prisma.store.update({ where: { id: party.id }, data });
  else await prisma.courier.update({ where: { id: party.id }, data });
}

/**
 * Stripe Express onboarding: Stripe collects identity, bank account and tax details (KYC) on its own
 * pages, so none of it passes through Malvoya's apps or servers.
 */
export async function startOnboarding(actor: Actor) {
  const party = await partyFor(actor);
  const stripe = getStripe();
  let accountId = party.accountId;
  if (!accountId) {
    const account = await stripe.accounts.create(
      {
        type: "express",
        country: "FI",
        email: party.email,
        business_type: party.individual ? "individual" : "company",
        capabilities: { transfers: { requested: true } },
        business_profile: party.kind === "STORE"
          ? { mcc: "5651", product_description: `Sells clothing and accessories on Malvoya (${party.name})` }
          : { mcc: "4215", product_description: "Delivers Malvoya orders by bike, scooter or car" },
        metadata: { party: party.kind, partyId: String(party.id) },
      },
      { idempotencyKey: `acct-${party.kind}-${party.id}` }
    );
    accountId = account.id;
    await saveAccount(party, accountId, false);
  }
  const link = await stripe.accountLinks.create({
    account: accountId,
    type: "account_onboarding",
    refresh_url: `${env.publicApiUrl}/api/v1/payouts/refresh`,
    return_url: `${env.publicApiUrl}/api/v1/payouts/return`,
  });
  return { url: link.url };
}

/** Reads the account from Stripe; releases held payouts as soon as it can receive transfers. */
export async function refreshStatus(actor: Actor) {
  const party = await partyFor(actor);
  if (!party.accountId) return { hasAccount: false, payoutsEnabled: false, detailsSubmitted: false, requirementsDue: 0 };
  const account = await getStripe().accounts.retrieve(party.accountId);
  const enabled = account.capabilities?.transfers === "active";
  await saveAccount(party, party.accountId, enabled);
  if (enabled) await releaseWaiting(party.kind, party.id);
  return {
    hasAccount: true,
    payoutsEnabled: enabled,
    detailsSubmitted: !!account.details_submitted,
    requirementsDue: account.requirements?.currently_due?.length ?? 0,
  };
}

export async function dashboardLink(actor: Actor) {
  const party = await partyFor(actor);
  if (!party.accountId) throw new ApiError("Set up payouts first", 409);
  const link = await getStripe().accounts.createLoginLink(party.accountId);
  return { url: link.url };
}

export async function listFor(actor: Actor) {
  const party = await partyFor(actor);
  const where = party.kind === "STORE" ? { storeId: party.id } : { courierId: party.id };
  const payouts = await prisma.payout.findMany({
    where,
    orderBy: { createdAt: "desc" },
    take: 200,
    select: { id: true, orderId: true, amountCents: true, status: true, releaseAt: true, paidAt: true, createdAt: true, failureReason: true },
  });
  const weekAgo = Date.now() - 7 * 86_400_000;
  const sum = (f: (p: (typeof payouts)[number]) => boolean) => payouts.filter(f).reduce((s, p) => s + p.amountCents, 0);
  return {
    summary: {
      paidCents: sum((p) => p.status === "PAID"),
      paidThisWeekCents: sum((p) => p.status === "PAID" && !!p.paidAt && p.paidAt.getTime() >= weekAgo),
      scheduledCents: sum((p) => p.status === "SCHEDULED"),
      waitingForAccountCents: sum((p) => p.status === "WAITING_FOR_ACCOUNT"),
      deliveries: payouts.length,
    },
    payouts,
  };
}

// ─── Money movement ─────────────────────────────────────────────────────────

/** Called once an order is delivered: the courier is paid now, the store after the return window. */
export async function createPayoutsForOrder(orderId: number) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { store: { select: { id: true, payoutsEnabled: true } }, courier: { select: { id: true, payoutsEnabled: true } } },
  });
  if (!order || order.status !== "DELIVERED" || !order.deliveredAt || order.paymentStatus !== "SUCCEEDED") return;

  const storeRelease = new Date(order.deliveredAt.getTime() + env.storePayoutHoldDays * 86_400_000);
  if (order.sellerPayoutCents + order.courierFeeCents > order.totalCents) {
    // Possible with formula courier pay or a big promo discount: Malvoya covers the difference from its balance
    logger.warn({ orderId, store: order.sellerPayoutCents, courier: order.courierFeeCents, charge: order.totalCents }, "Payouts exceed the charge");
  }
  const rows = [
    {
      orderId, party: "STORE" as const, storeId: order.storeId, amountCents: order.sellerPayoutCents,
      status: "SCHEDULED" as const, releaseAt: storeRelease,
    },
    ...(order.courier && order.courierFeeCents > 0
      ? [{
          orderId, party: "COURIER" as const, courierId: order.courier.id, amountCents: order.courierFeeCents,
          status: order.courier.payoutsEnabled ? ("SCHEDULED" as const) : ("WAITING_FOR_ACCOUNT" as const), releaseAt: new Date(),
        }]
      : []),
  ];
  await prisma.payout.createMany({ data: rows, skipDuplicates: true });
  processDuePayouts().catch((err) => logger.error({ err: err?.message }, "Payout run failed"));
}

/**
 * An order the courier took back to the shop (customer not reached): the courier is paid the job pay and the
 * tip as for a delivery; the store gets no payout (it has the items back and the items were refunded).
 * The transfer is tied to the charge only while it fits in what is left of it after the refund.
 */
export async function createCourierPayoutForReturnedOrder(orderId: number) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { courier: { select: { id: true, payoutsEnabled: true } } } });
  if (!order || !order.returnedToStoreAt || !order.courier || order.courierFeeCents <= 0 || order.paymentStatus !== "SUCCEEDED") return;
  if (order.courierFeeCents > order.totalCents - order.refundedCents) {
    logger.warn({ orderId, courier: order.courierFeeCents, kept: order.totalCents - order.refundedCents }, "Courier pay exceeds what was kept of the charge");
  }
  await prisma.payout.createMany({
    data: [{
      orderId, party: "COURIER", courierId: order.courier.id, amountCents: order.courierFeeCents,
      status: order.courier.payoutsEnabled ? "SCHEDULED" : "WAITING_FOR_ACCOUNT", releaseAt: new Date(),
    }],
    skipDuplicates: true,
  });
  processDuePayouts().catch((err) => logger.error({ err: err?.message }, "Payout run failed"));
}

async function releaseWaiting(kind: "STORE" | "COURIER", id: number) {
  const where = kind === "STORE" ? { storeId: id } : { courierId: id };
  const res = await prisma.payout.updateMany({ where: { ...where, status: "WAITING_FOR_ACCOUNT" }, data: { status: "SCHEDULED" } });
  if (res.count) processDuePayouts().catch(() => {});
}

/** Sends every due transfer. Safe to run repeatedly: each transfer has an idempotency key. */
export async function processDuePayouts() {
  const due = await prisma.payout.findMany({
    where: {
      status: "SCHEDULED",
      releaseAt: { lte: new Date() },
      // A store is not paid while a return on the order is still open: the refund may take the
      // money back. The payout goes out once the return is refunded (reduced) or rejected.
      NOT: { party: "STORE", order: { returns: { some: { status: { in: ["REQUESTED", "APPROVED", "IN_TRANSIT", "RECEIVED"] } } } } },
    },
    include: {
      order: { select: { stripePaymentIntentId: true, totalCents: true, refundedCents: true, sellerPayoutCents: true } },
      store: { select: { stripeAccountId: true, payoutsEnabled: true, ownerId: true } },
      courier: { select: { stripeAccountId: true, payoutsEnabled: true, userId: true } },
    },
    take: 50,
    orderBy: { releaseAt: "asc" },
  });
  if (!due.length) return;
  const stripe = getStripe();

  for (const p of due) {
    const account = p.party === "STORE" ? p.store : p.courier;
    if (!account?.stripeAccountId || !account.payoutsEnabled) {
      await prisma.payout.update({ where: { id: p.id }, data: { status: "WAITING_FOR_ACCOUNT" } });
      continue;
    }
    if (p.amountCents <= 0) {
      await prisma.payout.update({ where: { id: p.id }, data: { status: "CANCELLED" } });
      continue;
    }
    try {
      const intent = await stripe.paymentIntents.retrieve(p.order.stripePaymentIntentId!);
      const charge = typeof intent.latest_charge === "string" ? intent.latest_charge : intent.latest_charge?.id;
      // A succeeded payment always has a charge; the share is counted against it either way
      const link = p.amountCents <= await linkableCents(p.orderId, p.party, p.order);
      const transfer = await stripe.transfers.create(
        {
          amount: p.amountCents,
          currency: "eur",
          destination: account.stripeAccountId,
          // Tied to the charge only while the transfers tied to it stay within it (Stripe refuses more);
          // anything else is paid from Malvoya's balance
          ...(link && charge ? { source_transaction: charge } : {}),
          transfer_group: `order_${p.orderId}`,
          description: `Malvoya order #${p.orderId} – ${p.party === "STORE" ? "sale" : "delivery"}`,
          metadata: { payoutId: String(p.id), orderId: String(p.orderId), party: p.party },
        },
        { idempotencyKey: `payout-${p.id}` }
      );
      await prisma.payout.update({
        where: { id: p.id },
        data: { status: "PAID", stripeTransferId: transfer.id, paidAt: new Date(), failureReason: null, linkedToCharge: link },
      });
      const userId = p.party === "STORE" ? p.store?.ownerId : p.courier?.userId;
      if (userId) {
        const amount = euros(p.amountCents);
        pushToUser(userId, {
          title: t("Payout sent", "Tilitys lähetetty"),
          body: t(`${amount.en} for order #${p.orderId} is on its way to your account.`, `${amount.fi} tilauksesta #${p.orderId} on matkalla tilillesi.`),
          data: { type: "payout", payoutId: String(p.id) },
        }).catch(() => {});
      }
    } catch (err: any) {
      logger.error({ payoutId: p.id, err: err?.message }, "Transfer failed");
      await prisma.payout.update({ where: { id: p.id }, data: { status: "FAILED", failureReason: String(err?.message ?? "Transfer failed").slice(0, 300) } });
    }
  }
}

/**
 * How much of an order's charge a transfer may still be tied to (source_transaction): the charge, less refunds,
 * less transfers already tied to it. A courier transfer also leaves room for the store's payout, which is
 * released later, so the store's money can always come from the charge.
 */
async function linkableCents(
  orderId: number, party: "STORE" | "COURIER",
  order: { totalCents: number; refundedCents: number; sellerPayoutCents: number },
) {
  const linked = await prisma.payout.aggregate({ where: { orderId, status: "PAID", linkedToCharge: true }, _sum: { amountCents: true } });
  const store = party === "COURIER"
    ? (await prisma.payout.findUnique({ where: { orderId_party: { orderId, party: "STORE" } }, select: { amountCents: true, status: true } }))
    : null;
  const reserved = party === "COURIER" ? (store && store.status !== "PAID" && store.status !== "CANCELLED" ? store.amountCents : 0) : 0;
  return order.totalCents - order.refundedCents - (linked._sum.amountCents ?? 0) - reserved;
}

/** Orders whose store payout + courier pay is more than the customer paid (Malvoya covers the rest). */
export async function ordersPayingOutMoreThanCharged() {
  const rows = await prisma.$queryRaw<{ n: bigint }[]>`
    SELECT count(*)::bigint AS n FROM "Order"
    WHERE "paymentStatus" = 'SUCCEEDED' AND (
      (status = 'DELIVERED' AND "sellerPayoutCents" + "courierFeeCents" > "totalCents")
      -- taken back to the shop: only the courier is paid, from what is left of the charge after the refund
      OR (status = 'CANCELLED' AND "returnedToStoreAt" IS NOT NULL AND "courierFeeCents" > "totalCents" - "refundedCents"))`;
  return Number(rows[0]?.n ?? 0);
}

/**
 * A refund before the store has been paid reduces the store's payout by the refunded goods, minus the
 * commission Malvoya gives back on them. `goodsCents` (returns) is the undiscounted value of the returned
 * goods; without it the refund itself is scaled back to goods value (a promo discount is paid by Malvoya, not
 * the store), so a full withdrawal takes back the whole store payout and a partial one its fair share.
 * The commission rate is the order's own (commissionCents / subtotalCents), so a later change of the store's
 * rate never touches existing orders.
 */
export async function adjustStorePayoutForRefund(orderId: number, refundCents: number, goodsCents?: number) {
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  const payout = await prisma.payout.findUnique({ where: { orderId_party: { orderId, party: "STORE" } } });
  if (!order || !payout) return;
  if (payout.status === "PAID") {
    logger.warn({ orderId, refundCents }, "Refund after the store was paid — recover from the store manually");
    return;
  }
  if (!["SCHEDULED", "WAITING_FOR_ACCOUNT", "FAILED"].includes(payout.status)) return;
  let value: number;
  if (goodsCents !== undefined) {
    value = goodsCents;
  } else {
    const paidExTip = order.totalCents - order.tipCents;
    value = order.discountCents > 0 && paidExTip > 0
      ? Math.round((refundCents * (paidExTip + order.discountCents)) / paidExTip)
      : refundCents;
  }
  const goods = Math.min(value, order.subtotalCents);
  const commissionBack = order.subtotalCents > 0 ? Math.round((goods * order.commissionCents) / order.subtotalCents) : 0;
  const next = Math.max(0, payout.amountCents - (value - commissionBack));
  await prisma.payout.update({ where: { id: payout.id }, data: { amountCents: next, ...(next === 0 ? { status: "CANCELLED" } : {}) } });
}

// ─── Admin ──────────────────────────────────────────────────────────────────

export async function adminList(status?: string) {
  return prisma.payout.findMany({
    where: status ? { status: status as any } : {},
    include: { store: { select: { id: true, name: true } }, courier: { select: { id: true, name: true } } },
    orderBy: { createdAt: "desc" },
    take: 300,
  });
}

export async function retry(payoutId: number) {
  const p = await prisma.payout.findUnique({ where: { id: payoutId } });
  if (!p) throw new ApiError("Payout not found", 404);
  if (p.status !== "FAILED") throw new ApiError("Only failed payouts can be retried", 409);
  await prisma.payout.update({ where: { id: payoutId }, data: { status: "SCHEDULED", failureReason: null } });
  await processDuePayouts();
  return prisma.payout.findUnique({ where: { id: payoutId } });
}
