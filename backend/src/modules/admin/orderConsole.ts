import { Router, Response } from "express";
import { Prisma, OrderStatus } from "@prisma/client";
import { z } from "zod";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { AuthRequest } from "../../middleware/auth";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { audit } from "../../lib/audit";
import { getStripe } from "../../lib/stripe";
import { pushToUser } from "../../lib/push";
import { euros, t } from "../../lib/i18n";
import { authenticatedImageUrl } from "../../lib/cloudinary";
import { emitOrderStatus, emitToCourier, emitToStore } from "../../lib/socket";
import { cancelOrderInternal } from "../orders/orders.service";
import { adjustStorePayoutForRefund } from "../payouts/payouts.service";
import { offerOrderToCouriers } from "../../services/dispatchService";
import { courierPayOf, withApproach } from "../../utils/courierPay";
import { SWITCH_KEYS, SwitchKey, allSwitches, setSwitch } from "../../lib/settings";
import { courierPositionStatus } from "./admin.controller";

/**
 * Admin order console, disputes, audit log and runtime switches (since 2.17.0). Mounted under /admin (ADMIN session).
 * Every action is audited (AdminAuditLog) with the order's state before and after.
 */
const logger = pino({ name: "order-console" });
const router = Router();

const STATUSES = ["PENDING", "CONFIRMED", "PROCESSING", "SHIPPED", "DELIVERED", "CANCELLED", "REFUNDED"];

const listInclude = {
  user: { select: { id: true, name: true, email: true } },
  store: { select: { id: true, name: true } },
  courier: { select: { id: true, name: true, locationAt: true, locationExpiredAt: true } },
  items: { include: { product: { select: { name: true } } } },
} satisfies Prisma.OrderInclude;

/**
 * GET /admin/orders?q=&status=&before=&limit=&problem=1&disputed=1 → { orders, nextBefore } (newest first, ≤ 200 per
 * page). q: an order number, a customer email (contains "@") or a store name. The courier carries its position
 * status, never the coordinates.
 */
router.get("/orders", async (req: AuthRequest, res: Response) => {
  try {
    const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 200));
    const before = positiveId(req.query.before);
    const q = typeof req.query.q === "string" ? req.query.q.trim().slice(0, 100) : "";
    const status = typeof req.query.status === "string" ? req.query.status.toUpperCase() : "";
    const and: Prisma.OrderWhereInput[] = [];
    if (before) and.push({ id: { lt: before } });
    if (STATUSES.includes(status)) and.push({ status: status as OrderStatus });
    if (req.query.problem === "1") and.push({ deliveryProblemAt: { not: null } });
    if (req.query.disputed === "1") and.push({ disputedAt: { not: null } });
    if (q) {
      const id = /^#?\d+$/.test(q) ? Number(q.replace("#", "")) : null;
      and.push(id ? { id } : q.includes("@")
        ? { user: { email: { contains: q.toLowerCase(), mode: "insensitive" } } }
        : { store: { name: { contains: q, mode: "insensitive" } } });
    }
    const orders = await prisma.order.findMany({
      where: { AND: and },
      omit: { courierPay: false },
      include: listInclude,
      orderBy: { id: "desc" },
      take: limit,
    });
    res.json({
      ok: true,
      orders: orders.map((o) => (o.courier ? { ...o, courier: { id: o.courier.id, name: o.courier.name, position: courierPositionStatus(o.courier) } } : o)),
      nextBefore: orders.length === limit ? orders[orders.length - 1].id : null,
    });
  } catch (e) { sendError(res, e); }
});

async function orderDetail(id: number) {
  const o = await prisma.order.findUnique({
    where: { id },
    omit: { courierPay: false, handoverPin: false, cardFingerprint: false, receiptEmail: false, referrerId: false },
    include: {
      user: { select: { id: true, name: true, email: true, phone: true, createdAt: true, isActive: true } },
      store: { select: { id: true, name: true, address: true, phone: true, email: true, sellerType: true, businessId: true, ownerId: true } },
      courier: { select: { id: true, name: true, phone: true, userId: true, locationAt: true, locationExpiredAt: true } },
      items: { include: { product: { select: { id: true, name: true, images: true } }, variant: { select: { size: true, color: true } } } },
      returns: { include: { items: true }, orderBy: { id: "asc" } },
      payouts: { orderBy: { id: "asc" } },
      promoCode: { select: { code: true, description: true } },
    },
  });
  if (!o) throw new ApiError("Order not found", 404);
  const [messages, sameCard] = await Promise.all([
    prisma.orderMessage.findMany({ where: { orderId: id }, orderBy: { createdAt: "asc" }, take: 200 }),
    o.cardFingerprint ? prisma.order.count({ where: { cardFingerprint: o.cardFingerprint, id: { not: id }, userId: { not: o.userId } } }) : Promise.resolve(0),
  ]);
  const { handoverPin, cardFingerprint, courier, ...rest } = o;
  const timeline = ([
    ["created", o.createdAt], ["paid", o.paidAt], ["store_accepted", o.confirmedAt], ["courier_accepted", o.acceptedAt],
    ["courier_at_store", o.courierArrivedAt], ["ready", o.readyAt], ["picked_up", o.pickedUpAt], ["delivery_problem", o.deliveryProblemAt],
    ["returned_to_store", o.returnedToStoreAt], ["delivered", o.deliveredAt], ["cancelled", o.cancelledAt], ["disputed", o.disputedAt],
  ] as [string, Date | null][]).filter(([, at]) => !!at).map(([event, at]) => ({ event, at: at! })).sort((a, b) => +a.at - +b.at);
  return {
    ...rest,
    courier: courier ? { id: courier.id, name: courier.name, phone: courier.phone, userId: courier.userId, position: courierPositionStatus(courier) } : null,
    handoverPinRequired: !!handoverPin,
    // Other accounts that paid with the same card (linked-account signal), never the fingerprint itself
    sameCardOtherAccounts: sameCard,
    refundableCents: Math.max(0, o.totalCents - o.refundedCents),
    timeline,
    payments: {
      stripePaymentIntentId: o.stripePaymentIntentId, paymentStatus: o.paymentStatus, paidAt: o.paidAt, totalCents: o.totalCents,
      refundedCents: o.refundedCents, externalRefundedCents: o.externalRefundedCents,
    },
    dispute: o.disputedAt ? { at: o.disputedAt, status: o.disputeStatus, id: o.disputeId, reason: o.disputeReason } : null,
    chat: messages,
    deliveryProof: o.deliveredAt ? {
      method: o.handoverMethod,
      url: o.deliveryProofPublicId ? authenticatedImageUrl(o.deliveryProofPublicId) : null,
      location: o.deliveredLat !== null && o.deliveredLng !== null ? { lat: o.deliveredLat, lng: o.deliveredLng } : null,
    } : null,
  };
}

router.get("/orders/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, order: await orderDetail(positiveId(req.params.id)!) });
  } catch (e) { sendError(res, e); }
});

const reasonSchema = z.object({ reason: z.string().trim().min(3, "Give a reason").max(200) });

/** Cancel with a full refund (anything not yet picked up); the customer is told; audited. */
router.post("/orders/:id(\\d+)/cancel", async (req: AuthRequest, res: Response) => {
  const body = reasonSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Give a reason" });
  try {
    const id = positiveId(req.params.id)!;
    const before = await prisma.order.findUnique({ where: { id }, select: { status: true, paymentStatus: true, refundedCents: true } });
    if (!before) throw new ApiError("Order not found", 404);
    if (before.status === "CANCELLED") throw new ApiError("This order is already cancelled", 409);
    if (before.status === "SHIPPED" || before.status === "DELIVERED" || before.status === "REFUNDED") {
      throw new ApiError("This order is on its way or completed: use a refund instead", 409);
    }
    await cancelOrderInternal(id, `Cancelled by Malvoya: ${body.data.reason}`, {
      customerMessage: t(`Reason: ${body.data.reason}.`, `Syy: ${body.data.reason}.`),
    });
    const after = await prisma.order.findUniqueOrThrow({ where: { id }, select: { status: true, paymentStatus: true, refundedCents: true } });
    await audit(req.user!.id, "order.cancel", "Order", id, { oldValue: before, newValue: { ...after, reason: body.data.reason } });
    res.json({ ok: true, order: await orderDetail(id) });
  } catch (e) { sendError(res, e); }
});

const refundSchema = z.object({
  cents: z.number().int().min(1),
  reason: z.string().trim().min(3, "Give a reason").max(200),
  // true: the store pays it back (its payout is reduced like a return); false: a goodwill refund Malvoya pays
  fromStore: z.boolean().default(false),
});

/** A partial (or full) goodwill refund of what is left of the charge; audited; optionally taken from the store payout. */
router.post("/orders/:id(\\d+)/refund", async (req: AuthRequest, res: Response) => {
  const body = refundSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Check the amount and reason" });
  try {
    const id = positiveId(req.params.id)!;
    const o = await prisma.order.findUnique({ where: { id }, select: { id: true, userId: true, totalCents: true, refundedCents: true, paymentStatus: true, stripePaymentIntentId: true } });
    if (!o) throw new ApiError("Order not found", 404);
    if (!o.stripePaymentIntentId || (o.paymentStatus !== "SUCCEEDED" && o.paymentStatus !== "REFUNDED")) throw new ApiError("This order has no payment to refund", 409);
    const refundable = o.totalCents - o.refundedCents;
    if (body.data.cents > refundable) throw new ApiError(`At most ${(refundable / 100).toFixed(2)} € can still be refunded`, 400);
    // Claim the amount first (conditional on the value read), so two clicks cannot refund twice
    const claimed = await prisma.order.updateMany({ where: { id, refundedCents: o.refundedCents }, data: { refundedCents: { increment: body.data.cents } } });
    if (!claimed.count) throw new ApiError("The order changed in the meantime. Reload and try again.", 409);
    try {
      await getStripe().refunds.create(
        { payment_intent: o.stripePaymentIntentId, amount: body.data.cents, metadata: { source: "malvoya", orderId: String(id), kind: "admin_refund" } },
        { idempotencyKey: `admin-refund-${id}-${o.refundedCents}-${body.data.cents}` },
      );
    } catch (e) {
      await prisma.order.update({ where: { id }, data: { refundedCents: { decrement: body.data.cents } } });
      throw e;
    }
    if (o.refundedCents + body.data.cents >= o.totalCents) await prisma.order.update({ where: { id }, data: { paymentStatus: "REFUNDED" } });
    if (body.data.fromStore) await adjustStorePayoutForRefund(id, body.data.cents);
    await audit(req.user!.id, "order.refund", "Order", id, {
      oldValue: { refundedCents: o.refundedCents },
      newValue: { refundedCents: o.refundedCents + body.data.cents, cents: body.data.cents, reason: body.data.reason, fromStore: body.data.fromStore },
    });
    const amount = euros(body.data.cents);
    pushToUser(o.userId, {
      title: t("Refund sent", "Hyvitys lähetetty"),
      body: t(`${amount.en} for order #${id} is on its way back to you.`, `${amount.fi} tilauksesta #${id} on matkalla sinulle.`),
      data: { type: "order", orderId: String(id) },
    }).catch(() => {});
    emitOrderStatus(id, { refundedCents: o.refundedCents + body.data.cents });
    res.json({ ok: true, order: await orderDetail(id) });
  } catch (e) { sendError(res, e); }
});

/** Takes the job away from its courier before pickup and offers it again (e.g. the courier is not moving). */
router.post("/orders/:id(\\d+)/unassign-courier", async (req: AuthRequest, res: Response) => {
  try {
    const id = positiveId(req.params.id)!;
    const o = await prisma.order.findUnique({ where: { id }, omit: { courierPay: false } });
    if (!o) throw new ApiError("Order not found", 404);
    if (!o.courierId) throw new ApiError("No courier is assigned to this order", 409);
    if (o.status !== "CONFIRMED" && o.status !== "PROCESSING") throw new ApiError("Only an order not yet picked up can be taken from its courier", 409);
    const courierId = o.courierId;
    const pay = o.courierPay ? courierPayOf(o) : null;
    const reset = pay ? withApproach(pay, null) : null;
    const done = await prisma.$transaction(async (tx) => {
      const r = await tx.order.updateMany({
        where: { id, courierId, status: { in: ["CONFIRMED", "PROCESSING"] } },
        data: {
          courierId: null, acceptedAt: null, courierArrivedAt: null, lastOfferAt: null,
          ...(reset ? { courierPay: reset as unknown as Prisma.InputJsonValue, courierFeeCents: reset.totalCents } : {}),
        },
      });
      if (!r.count) return false;
      await tx.courier.updateMany({ where: { id: courierId, currentOrderId: id }, data: { currentOrderId: null } });
      return true;
    });
    if (!done) throw new ApiError("The order changed in the meantime. Reload and try again.", 409);
    await audit(req.user!.id, "order.unassign_courier", "Order", id, { oldValue: { courierId }, newValue: { courierId: null } });
    emitToCourier(courierId, "order:unassigned", { orderId: id });
    emitToStore(o.storeId, "order:status", { orderId: id, status: o.status, courierName: null });
    emitOrderStatus(id, { status: o.status, courierId: null });
    const c = await prisma.courier.findUnique({ where: { id: courierId }, select: { userId: true } });
    if (c?.userId) {
      pushToUser(c.userId, {
        title: t(`Order #${id} was reassigned`, `Tilaus #${id} siirrettiin`),
        body: t("Malvoya support took this job off you. You are not expected to pick it up.", "Malvoyan tuki poisti tämän keikan sinulta. Sinun ei tarvitse noutaa sitä."),
        data: { type: "order", orderId: String(id) },
      }).catch(() => {});
    }
    offerOrderToCouriers(id).catch((e) => logger.error({ orderId: id, err: e?.message }, "Re-offer failed"));
    res.json({ ok: true, order: await orderDetail(id) });
  } catch (e) { sendError(res, e); }
});

/** GET /admin/disputes → chargebacks, newest first. */
router.get("/disputes", async (_req: AuthRequest, res: Response) => {
  try {
    const rows = await prisma.order.findMany({
      where: { disputedAt: { not: null } },
      select: {
        id: true, totalCents: true, refundedCents: true, status: true, disputedAt: true, disputeStatus: true, disputeId: true, disputeReason: true,
        user: { select: { id: true, name: true, email: true } }, store: { select: { id: true, name: true } },
        payouts: { select: { party: true, status: true, amountCents: true } },
      },
      orderBy: { disputedAt: "desc" },
      take: 200,
    });
    res.json({ ok: true, disputes: rows.map((r) => ({ ...r, orderId: r.id, storePayoutFrozen: !["won", "warning_closed"].includes(r.disputeStatus ?? "") })) });
  } catch (e) { sendError(res, e); }
});

/** GET /admin/audit?before=&limit=&action= → { entries:[{…, admin {id,name,email}}], nextBefore } (newest first). */
router.get("/audit", async (req: AuthRequest, res: Response) => {
  try {
    const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 50));
    const before = positiveId(req.query.before);
    const action = typeof req.query.action === "string" && /^[a-z0-9_.]{1,60}$/.test(req.query.action) ? req.query.action : null;
    const rows = await prisma.adminAuditLog.findMany({
      where: { ...(before ? { id: { lt: before } } : {}), ...(action ? { action: { startsWith: action } } : {}) },
      orderBy: { id: "desc" },
      take: limit,
    });
    const admins = await prisma.user.findMany({ where: { id: { in: [...new Set(rows.map((r) => r.adminId))] } }, select: { id: true, name: true, email: true } });
    const byId = new Map(admins.map((a) => [a.id, a]));
    res.json({ ok: true, entries: rows.map((r) => ({ ...r, admin: byId.get(r.adminId) ?? null })), nextBefore: rows.length === limit ? rows[rows.length - 1].id : null });
  } catch (e) { sendError(res, e); }
});

// ─── Runtime switches ───────────────────────────────────────────────────────

router.get("/settings", async (_req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, switches: await allSwitches() });
  } catch (e) { sendError(res, e); }
});

const switchSchema = z.object({ on: z.boolean(), message: z.string().trim().max(300).nullable().optional() });

router.patch("/settings/:key", async (req: AuthRequest, res: Response) => {
  const key = req.params.key as SwitchKey;
  if (!SWITCH_KEYS.includes(key)) return res.status(404).json({ ok: false, error: "Unknown setting" });
  const body = switchSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Send on (true/false) and an optional message" });
  try {
    res.json({ ok: true, switch: await setSwitch(req.user!.id, key, body.data.on, body.data.message ?? null), switches: await allSwitches() });
  } catch (e) { sendError(res, e); }
});

export default router;
