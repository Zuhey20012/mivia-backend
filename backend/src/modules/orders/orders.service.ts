import crypto from "crypto";
import { Prisma, OrderStatus, Fulfilment } from "@prisma/client";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { getStripe } from "../../lib/stripe";
import { MIN_CHARGE_CENTS, calcCheckoutPricing, calcRentalPricing, deliveryFeeForDistance, formatCents } from "../../utils/pricing";
import { haversineKm } from "../../utils/distance";
import { env } from "../../config/env";
import { emitOrderStatus, emitToStore, emitToAllCouriers } from "../../lib/socket";
import { offerOrderToCouriers } from "../../services/dispatchService";
import { sendOrderConfirmation, sendOrderStatusEmail } from "../../services/notificationDeliveryService";
import { pushToUser } from "../../lib/push";
import { authenticatedImageUrl, destroyResource } from "../../lib/cloudinary";
import { estimateDelivery } from "../../utils/distance";
import { verifyOwnedUpload, UploadProof } from "../media/media.service";
import { adjustStorePayoutForRefund, createPayoutsForOrder } from "../payouts/payouts.service";
import { Actor, getCourierForUser, getOrderRelation } from "./access";
import { storeAvailability } from "../../utils/openingHours";
import { ApiError } from "../../lib/errors";
import { checkPromo, normalizeCode } from "../promos/promos.service";
import { CheckoutDiscount, checkReferralCode, rewardReferralForOrder } from "../referrals/referrals.service";
import { RIDE_SPEED_KMH, calcCourierPay, courierPayOf, presentCourierPay, withApproach, withWaiting } from "../../utils/courierPay";
import { freshPosition } from "../../utils/courierPosition";

const logger = pino({ name: "orders" });

export class OrderError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

type ItemInput = { productId: number; variantId?: number; quantity: number };

type Db = Prisma.TransactionClient | typeof prisma;

type CheckoutInput = {
  storeId: number; fulfilment?: Fulfilment; deliveryLat?: number; deliveryLng?: number; items: ItemInput[];
  tipCents?: number; promoCode?: string;
};

/** A courier counts as "at the shop" within this distance. */
const ARRIVAL_RADIUS_KM = 0.3;

/** Reserve & collect: 5 wrong pickup codes lock the handover for 15 minutes. */
const PICKUP_MAX_ATTEMPTS = 5;
const PICKUP_LOCK_MINUTES = 15;

// ─── ORDERS (SALE) ──────────────────────────────────────────────────────────

async function loadOrderStore(storeId: number) {
  const store = await prisma.store.findUnique({ where: { id: storeId } });
  if (!store || !store.isVerified) throw new OrderError("This store is not accepting orders", 404);
  return store;
}

function closedStoreError(availability: ReturnType<typeof storeAvailability>) {
  const opens = availability.opensAt ? ` It opens again at ${availability.opensAt.time}.` : "";
  return new OrderError(
    availability.closedReason === "paused" ? "This store is not taking orders right now." : `This store is closed right now.${opens}`,
    409,
  );
}

/**
 * Prices the basket from the database. With `reserve`, stock is taken with conditional decrements
 * (createOrder, inside its transaction); without, it is only checked (quote), with the same errors.
 */
async function priceItems(db: Db, storeId: number, items: ItemInput[], reserve: boolean) {
  let subtotalCents = 0;
  const lines: Prisma.OrderItemCreateManyOrderInput[] = [];
  const wanted = new Map<string, number>(); // quote: quantities asked so far per product / option

  for (const item of items) {
    const product = await db.product.findUnique({ where: { id: item.productId } });
    if (!product || product.storeId !== storeId) throw new OrderError(`Product ${item.productId} is not sold by this store`);
    if (!product.canBeSold || !product.isAvailable || product.salePriceCents === null) {
      throw new OrderError(`${product.name} is not available for purchase`);
    }

    let unitCents = product.salePriceCents;
    if (item.variantId) {
      const variant = await db.productVariant.findUnique({ where: { id: item.variantId } });
      if (!variant || variant.productId !== product.id) throw new OrderError(`Invalid option for ${product.name}`);
      const outOfStock = new OrderError(`${product.name} (${variant.size ?? variant.color ?? "option"}) is out of stock`);
      if (reserve) {
        const reserved = await db.productVariant.updateMany({
          where: { id: variant.id, stock: { gte: item.quantity } },
          data: { stock: { decrement: item.quantity } },
        });
        if (reserved.count === 0) throw outOfStock;
      } else {
        const key = `v${variant.id}`;
        const total = (wanted.get(key) ?? 0) + item.quantity;
        if (variant.stock < total) throw outOfStock;
        wanted.set(key, total);
      }
      unitCents += variant.priceAdjustCents;
    }

    if (reserve) {
      // Conditional decrement: never oversell when two customers check out at the same time.
      const reserved = await db.product.updateMany({
        where: { id: product.id, stockQuantity: { gte: item.quantity } },
        data: { stockQuantity: { decrement: item.quantity } },
      });
      if (reserved.count === 0) throw new OrderError(`Insufficient stock for ${product.name}`);
    } else {
      const key = `p${product.id}`;
      const total = (wanted.get(key) ?? 0) + item.quantity;
      if (product.stockQuantity < total) throw new OrderError(`Insufficient stock for ${product.name}`);
      wanted.set(key, total);
    }

    subtotalCents += unitCents * item.quantity;
    lines.push({ productId: product.id, variantId: item.variantId, quantity: item.quantity, unitCents });
  }
  return { subtotalCents, lines };
}

function deliveryDistanceKm(store: { latitude: number | null; longitude: number | null }, lat?: number, lng?: number) {
  return store.latitude !== null && store.longitude !== null && lat !== undefined && lng !== undefined
    ? haversineKm(store.latitude, store.longitude, lat, lng)
    : null;
}

/**
 * The one place a checkout is priced; used by both the quote and createOrder. A pickup order has no delivery
 * fee, no courier (no courier pay) and no tip; service fee, small-order fee and discounts work the same.
 */
function priceCheckout(
  store: { commissionRate: number; latitude: number | null; longitude: number | null },
  input: CheckoutInput,
  subtotalCents: number,
  discount: CheckoutDiscount | null,
) {
  const promo = discount?.terms ?? null;
  if (input.fulfilment === "PICKUP") {
    const pricing = calcCheckoutPricing({
      subtotalCents, commissionRate: store.commissionRate, deliveryFeeCents: 0, tipCents: 0, promo, courierPayCents: 0,
    });
    return { pricing, distanceKm: null, courierPay: null };
  }
  const distanceKm = deliveryDistanceKm(store, input.deliveryLat, input.deliveryLng);
  const deliveryFeeCents = deliveryFeeForDistance(distanceKm);
  const tipCents = input.tipCents ?? 0;
  // Courier pay is computed on its own (per-job formula), not from what the customer pays for delivery
  const courierPay = calcCourierPay({ straightKm: distanceKm, deliveryFeeCents, tipCents });
  const pricing = calcCheckoutPricing({
    subtotalCents,
    commissionRate: store.commissionRate,
    deliveryFeeCents,
    tipCents,
    promo,
    courierPayCents: courierPay.totalCents - tipCents,
  });
  return { pricing, distanceKm, courierPay };
}

/**
 * Checks the code typed at checkout: a promo code, or (when referrals are on and no promo code has that name)
 * another customer's invite code. "Cannot be used" becomes an OrderError with the user-readable reason.
 */
async function promoForCheckout(db: Db, code: string | undefined, userId: number, subtotalCents: number): Promise<CheckoutDiscount | null> {
  if (!code?.trim()) return null;
  try {
    const normalized = normalizeCode(code);
    if (!(await db.promoCode.findUnique({ where: { code: normalized }, select: { id: true } }))) {
      const invite = await checkReferralCode(db, normalized, userId);
      if (invite) return invite;
    }
    const promo = await checkPromo(db, code, userId, subtotalCents);
    return { terms: promo, promoCodeId: promo.id, referrerId: null, code: promo.code, description: promo.description };
  } catch (e) {
    if (e instanceof ApiError) throw new OrderError(e.message, e.status);
    throw e;
  }
}

/** Pickup needs a store address to collect from; tips are for couriers, so a pickup order cannot carry one. */
function assertPickupPossible(store: { address: string | null }, input: CheckoutInput) {
  if (input.fulfilment !== "PICKUP") return;
  if ((input.tipCents ?? 0) > 0) throw new OrderError("Tips go to couriers, so a pickup order cannot have a tip", 400);
  if (!store.address?.trim()) throw new OrderError("This store does not offer pickup", 409);
}

/**
 * Exact price before payment. Reserves nothing and creates nothing. Items and store give the same
 * errors as createOrder; a promo code that cannot be used comes back as `promoError` (still 200).
 */
export async function quoteOrder(userId: number, input: CheckoutInput) {
  const store = await loadOrderStore(input.storeId);
  assertPickupPossible(store, input);
  const { subtotalCents } = await priceItems(prisma, store.id, input.items, false);

  let promo: CheckoutDiscount | null = null;
  let promoError: string | null = null;
  try {
    promo = await promoForCheckout(prisma, input.promoCode, userId, subtotalCents);
  } catch (e) {
    if (!(e instanceof OrderError)) throw e;
    promoError = e.message;
  }

  const { pricing } = priceCheckout(store, input, subtotalCents, promo);
  const cfg = env.pricing;
  const availability = storeAvailability(store);
  return {
    subtotalCents: pricing.subtotalCents,
    deliveryFeeCents: pricing.deliveryFeeCents,
    serviceFeeCents: pricing.serviceFeeCents,
    smallOrderFeeCents: pricing.smallOrderFeeCents,
    // Below this item subtotal a small-order fee applies (0 = no small-order fee)
    smallOrderThresholdCents: cfg.smallOrderFeeCents > 0 ? cfg.smallOrderThresholdCents : 0,
    discountCents: pricing.discountCents,
    tipCents: pricing.tipCents,
    totalCents: pricing.totalCents,
    promo: promo ? { code: promo.code, description: promo.description } : null,
    promoError,
    fulfilment: input.fulfilment ?? "DELIVERY",
    ...(input.fulfilment === "PICKUP" ? { pickup: { storeName: store.name, address: store.address } } : {}),
    store: { openNow: availability.openNow, closedReason: availability.closedReason, opensAt: availability.opensAt },
  };
}

export async function createOrder(userId: number, input: CheckoutInput & { deliveryAddress?: string; notes?: string }) {
  const store = await loadOrderStore(input.storeId);
  const availability = storeAvailability(store);
  if (!availability.openNow) throw closedStoreError(availability);
  assertPickupPossible(store, input);
  const pickup = input.fulfilment === "PICKUP";

  // Price is always computed server-side from the database.
  const order = await prisma.$transaction(async (tx) => {
    const { subtotalCents, lines } = await priceItems(tx, store.id, input.items, true);
    // A code that cannot be used is refused (409), so the customer never pays a different price than quoted.
    const promo = await promoForCheckout(tx, input.promoCode, userId, subtotalCents);
    const { pricing, distanceKm, courierPay } = priceCheckout(store, input, subtotalCents, promo);
    if (pricing.totalCents < MIN_CHARGE_CENTS) throw new OrderError(`The minimum order is ${formatCents(MIN_CHARGE_CENTS)}`);
    const etaMinutes = distanceKm === null ? null : estimateDelivery(distanceKm, store.prepMinutes).etaMinutes;

    return tx.order.create({
      data: {
        userId,
        storeId: store.id,
        fulfilment: pickup ? "PICKUP" : "DELIVERY",
        deliveryAddress: pickup ? null : input.deliveryAddress,
        deliveryLat: pickup ? null : input.deliveryLat,
        deliveryLng: pickup ? null : input.deliveryLng,
        notes: input.notes,
        ...pricing, // includes tipCents and courierFeeCents (the tip goes to the courier in full, no commission)
        // the breakdown behind courierFeeCents; none for pickup (no courier)
        ...(courierPay ? { courierPay: courierPay as unknown as Prisma.InputJsonValue } : {}),
        promoCodeId: promo?.promoCodeId ?? null,
        referrerId: promo?.referrerId ?? null,
        etaMinutes,
        items: { createMany: { data: lines } },
      },
      include: { items: true, promoCode: { select: { code: true, description: true } } },
    });
  });

  try {
    // Automatic payment methods lets the Stripe PaymentSheet offer card, Apple/Google Pay,
    // MobilePay and SEPA — whatever is enabled in the Stripe dashboard. SCA/3DS is handled by Stripe.
    const paymentIntent = await getStripe().paymentIntents.create(
      {
        amount: order.totalCents,
        currency: "eur",
        automatic_payment_methods: { enabled: true },
        metadata: { type: "ORDER", orderId: String(order.id), userId: String(userId), storeId: String(store.id) },
        description: `Malvoya order #${order.id} – ${store.name}`,
      },
      { idempotencyKey: `order-${order.id}` }
    );
    await prisma.order.update({ where: { id: order.id }, data: { stripePaymentIntentId: paymentIntent.id } });
    return { order: { ...order, stripePaymentIntentId: paymentIntent.id }, clientSecret: paymentIntent.client_secret };
  } catch (err) {
    await cancelOrderInternal(order.id, "Payment could not be started", { notifyCustomer: false });
    throw err;
  }
}

/** Called from the Stripe webhook once the money has actually arrived. */
export async function markOrderPaid(orderId: number, paymentIntentId: string, amountReceived: number) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    omit: { referrerId: false },
    include: {
      user: true, store: true, items: { include: { product: { select: { name: true } } } },
      promoCode: { select: { code: true } },
    },
  });
  if (!order || order.stripePaymentIntentId !== paymentIntentId) {
    logger.warn({ orderId, paymentIntentId }, "Payment for unknown order/intent");
    return;
  }
  if (order.paymentStatus === "SUCCEEDED") return;
  if (amountReceived !== order.totalCents) {
    logger.error({ orderId, amountReceived, expected: order.totalCents }, "Paid amount does not match order total");
    return;
  }
  if (order.status === "CANCELLED") {
    // Paid after it was cancelled (e.g. slow SEPA): give the money back.
    await getStripe().refunds.create({ payment_intent: paymentIntentId }, { idempotencyKey: `late-refund-${orderId}` });
    await prisma.order.update({ where: { id: orderId }, data: { paymentStatus: "REFUNDED", refundedCents: order.totalCents } });
    return;
  }

  // A promo code counts as used only once the order is paid (released again if it is cancelled before delivery).
  // The same goes for an invite code (one referral per new customer). Pickup orders get their handover code now.
  const pickup = order.fulfilment === "PICKUP";
  await prisma.$transaction([
    prisma.order.update({
      where: { id: orderId },
      data: { paymentStatus: "SUCCEEDED", paidAt: new Date(), ...(pickup ? { pickupCode: newPickupCode() } : {}) },
    }),
    ...(order.referrerId
      ? [prisma.referral.createMany({ data: [{ referrerId: order.referrerId, refereeId: order.userId, orderId }], skipDuplicates: true })]
      : []),
    ...(order.promoCodeId
      ? [prisma.promoRedemption.upsert({
          where: { orderId },
          create: { orderId, userId: order.userId, promoCodeId: order.promoCodeId, discountCents: order.discountCents },
          update: {},
        })]
      : []),
  ]);

  emitToStore(order.storeId, "order:new", {
    id: order.id,
    status: order.status,
    fulfilment: order.fulfilment,
    totalCents: order.totalCents,
    deliveryAddress: order.deliveryAddress,
    items: order.items.map((i) => ({ name: i.product.name, quantity: i.quantity, unitCents: i.unitCents })),
    createdAt: order.createdAt,
  });
  emitOrderStatus(orderId, { status: order.status, paymentStatus: "SUCCEEDED" });
  pushToUser(order.store.ownerId, {
    title: pickup ? `New pickup order #${order.id}` : `New order #${order.id}`,
    body: `${order.items.reduce((n, i) => n + i.quantity, 0)} item(s) · ${(order.subtotalCents / 100).toFixed(2).replace(".", ",")} € — accept it in Malvoya Store.`,
    data: { type: "order", orderId: String(order.id) },
    channel: "new_orders",
  }).catch(() => {});

  sendOrderConfirmation({
    orderId: order.id,
    customerName: order.user.name,
    email: order.user.email,
    storeName: order.store.name,
    items: order.items.map((i) => ({ name: i.product.name, quantity: i.quantity, unitCents: i.unitCents })),
    subtotalCents: order.subtotalCents,
    deliveryFeeCents: order.deliveryFeeCents,
    serviceFeeCents: order.serviceFeeCents,
    smallOrderFeeCents: order.smallOrderFeeCents,
    discountCents: order.discountCents,
    promoCode: order.promoCode?.code ?? null,
    tipCents: order.tipCents,
    totalCents: order.totalCents,
    deliveryAddress: order.deliveryAddress,
  }).catch(() => {});
}

export async function markOrderPaymentFailed(orderId: number, paymentIntentId: string) {
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order || order.stripePaymentIntentId !== paymentIntentId || order.paymentStatus === "SUCCEEDED") return;
  await prisma.order.update({ where: { id: orderId }, data: { paymentStatus: "FAILED" } });
  emitOrderStatus(orderId, { status: order.status, paymentStatus: "FAILED" });
}

/** 6 random digits from the OS's secure random source. */
function newPickupCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");
}

async function restock(tx: Prisma.TransactionClient, orderId: number) {
  const items = await tx.orderItem.findMany({ where: { orderId } });
  for (const item of items) {
    await tx.product.update({ where: { id: item.productId }, data: { stockQuantity: { increment: item.quantity } } });
    if (item.variantId) {
      await tx.productVariant.update({ where: { id: item.variantId }, data: { stock: { increment: item.quantity } } });
    }
  }
}

/**
 * Cancels, restocks and refunds (or voids the unpaid PaymentIntent). Idempotent.
 * `notifyCustomer: false` is for checkouts the customer abandoned themselves.
 */
export async function cancelOrderInternal(orderId: number, reason: string, opts: { notifyCustomer?: boolean; customerMessage?: string } = {}) {
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order || order.status === "CANCELLED") return order;
  if (order.status === "SHIPPED" || order.status === "DELIVERED") {
    throw new OrderError("This order is already on its way and can no longer be cancelled", 409);
  }

  const updated = await prisma.$transaction(async (tx) => {
    // Guard against double cancellation racing with itself
    const res = await tx.order.updateMany({
      where: { id: orderId, status: { notIn: ["CANCELLED", "SHIPPED", "DELIVERED"] } },
      data: { status: "CANCELLED", cancelledAt: new Date(), cancelReason: reason.slice(0, 200) },
    });
    if (res.count === 0) return null;
    await restock(tx, orderId);
    // The customer gets the promo code back
    await tx.promoRedemption.deleteMany({ where: { orderId } });
    // ...and the invite code (it was not used up)
    await tx.referral.deleteMany({ where: { orderId, rewardedAt: null } });
    if (order.courierId) {
      await tx.courier.updateMany({ where: { id: order.courierId, currentOrderId: orderId }, data: { currentOrderId: null } });
    }
    return tx.order.findUnique({ where: { id: orderId } });
  });
  if (!updated) return order;

  if (order.stripePaymentIntentId) {
    try {
      if (order.paymentStatus === "SUCCEEDED") {
        const refundable = order.totalCents - order.refundedCents;
        if (refundable > 0) {
          await getStripe().refunds.create(
            { payment_intent: order.stripePaymentIntentId, amount: refundable },
            { idempotencyKey: `cancel-refund-${orderId}` }
          );
          await prisma.order.update({ where: { id: orderId }, data: { paymentStatus: "REFUNDED", refundedCents: order.totalCents } });
        }
      } else {
        await getStripe().paymentIntents.cancel(order.stripePaymentIntentId).catch(() => {});
      }
    } catch (err: any) {
      // The order stays cancelled; the refund must be retried from the Stripe dashboard.
      logger.error({ orderId, err: err?.message }, "Refund after cancellation failed — needs manual follow-up");
    }
  }

  emitOrderStatus(orderId, { status: "CANCELLED", cancelReason: reason });
  emitToStore(order.storeId, "order:status", { orderId, status: "CANCELLED" });
  if (order.fulfilment === "DELIVERY" && !order.courierId) emitToAllCouriers("courier:offer_closed", { orderId, reason: "cancelled" });
  if (opts.notifyCustomer !== false) {
    const money = order.paymentStatus === "SUCCEEDED" ? "Your money is on its way back to you." : "You have not been charged.";
    pushToUser(order.userId, {
      title: `Order #${orderId} was cancelled`,
      body: opts.customerMessage ? `${opts.customerMessage} ${money}` : money,
      data: { type: "order", orderId: String(orderId) },
    }).catch(() => {});
  }
  return updated;
}

/** Customer cancels before the store has accepted the order. */
export async function cancelOrderByCustomer(orderId: number, userId: number) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { user: true } });
  if (!order || order.userId !== userId) throw new OrderError("Order not found", 404);
  if (order.status !== "PENDING") {
    throw new OrderError("The store has already accepted this order. Please contact support or use your 14-day return right after delivery.", 409);
  }
  const updated = await cancelOrderInternal(orderId, "Cancelled by customer");
  sendOrderStatusEmail(orderId, order.user.email, "CANCELLED").catch(() => {});
  return updated;
}

/**
 * Who may move an order from which status to which. Anything not listed is rejected.
 *  PENDING ──vendor accepts──▶ CONFIRMED ──vendor──▶ PROCESSING (preparing)
 *  CONFIRMED/PROCESSING ──assigned courier picks up──▶ SHIPPED ──courier──▶ DELIVERED
 *  vendor/admin may cancel until pickup (automatic refund)
 */
const TRANSITIONS: Record<"vendor" | "courier" | "admin", Partial<Record<OrderStatus, OrderStatus[]>>> = {
  vendor: { PENDING: ["CONFIRMED", "CANCELLED"], CONFIRMED: ["PROCESSING", "CANCELLED"], PROCESSING: ["CANCELLED"] },
  courier: { CONFIRMED: ["SHIPPED"], PROCESSING: ["SHIPPED"], SHIPPED: ["DELIVERED"] },
  admin: { PENDING: ["CANCELLED"], CONFIRMED: ["CANCELLED"], PROCESSING: ["CANCELLED"], SHIPPED: ["DELIVERED"] },
};

export async function updateOrderStatus(orderId: number, actor: Actor, next: OrderStatus) {
  const relation = await getOrderRelation(orderId, actor);
  if (!relation || relation === "customer") throw new OrderError("Forbidden", 403);

  const order = await prisma.order.findUniqueOrThrow({ where: { id: orderId }, include: { user: true } });
  const allowed = TRANSITIONS[relation][order.status] ?? [];
  if (!allowed.includes(next)) {
    throw new OrderError(`Cannot change order from ${order.status} to ${next}`, 409);
  }
  if (next === "CONFIRMED" && order.paymentStatus !== "SUCCEEDED") {
    throw new OrderError("This order has not been paid yet", 409);
  }
  if (next === "DELIVERED" && relation === "courier") {
    throw new OrderError("Confirm the handover in the app to complete this delivery", 409);
  }
  if ((next === "SHIPPED" || next === "DELIVERED") && order.fulfilment === "PICKUP") {
    throw new OrderError("The store completes a pickup order by entering the customer's pickup code", 409);
  }

  if (next === "CANCELLED") {
    const cancelled = await cancelOrderInternal(orderId, relation === "vendor" ? "Declined by store" : "Cancelled by Malvoya");
    sendOrderStatusEmail(orderId, order.user.email, "CANCELLED").catch(() => {});
    return cancelled;
  }

  const updated = await prisma.$transaction(async (tx) => {
    const res = await tx.order.updateMany({
      where: { id: orderId, status: order.status },
      data: {
        status: next,
        ...(next === "DELIVERED" ? { deliveredAt: new Date(), handoverMethod: "ADMIN" } : {}),
        ...(next === "SHIPPED" ? { pickedUpAt: new Date() } : {}),
        ...(next === "CONFIRMED" ? { confirmedAt: new Date() } : {}),
        // PROCESSING = the store has the order ready (pickup: starts the hold time; delivery: ends paid waiting)
        ...(next === "PROCESSING" ? { readyAt: new Date() } : {}),
      },
    });
    if (res.count === 0) throw new OrderError("The order changed in the meantime, please refresh", 409);
    if (next === "SHIPPED") await addWaitingPay(tx, orderId);
    if (next === "DELIVERED" && order.courierId) {
      await tx.courier.updateMany({ where: { id: order.courierId, currentOrderId: orderId }, data: { currentOrderId: null } });
    }
    return tx.order.findUniqueOrThrow({ where: { id: orderId } });
  });

  afterStatusChange(updated, order.user.email, next);
  return updated;
}

type CourierPosition = { latitude: number | null; longitude: number | null; locationAt: Date | null };

/**
 * Straight-line km from a courier's position to the order's shop, or null when either is unknown. Only a fresh
 * position counts (reported within the last 2 minutes): an old or missing one gives no ride-to-shop pay.
 */
function approachStraightKm(courier: CourierPosition, store: { latitude: number | null; longitude: number | null }) {
  const pos = freshPosition(courier);
  if (!pos || store.latitude === null || store.longitude === null) return null;
  return haversineKm(pos.lat, pos.lng, store.latitude, store.longitude);
}

/**
 * On acceptance: the ride to the shop (courier's last known position → shop, × road factor) beyond the
 * free km is added to the courier's pay (formula mode).
 */
async function addApproachPay(tx: Prisma.TransactionClient, orderId: number, courier: CourierPosition) {
  const o = await tx.order.findUniqueOrThrow({
    where: { id: orderId },
    select: {
      courierPay: true, courierFeeCents: true, tipCents: true, deliveryFeeCents: true,
      store: { select: { latitude: true, longitude: true } },
    },
  });
  if (o.courierPay === null) return;
  const pay = courierPayOf(o);
  if (pay.mode !== "formula") return;
  const next = withApproach(pay, approachStraightKm(courier, o.store));
  await tx.order.update({
    where: { id: orderId },
    data: { courierPay: next as unknown as Prisma.InputJsonValue, courierFeeCents: next.totalCents },
  });
}

/**
 * At pickup: waiting is paid only while the shop was not ready. It counts from the check-in at the shop
 * (POST /orders/:id/arrived-at-store), but never from earlier than acceptance + the expected ride to the shop
 * (at 15 km/h), until the shop marked the order ready (PROCESSING) or pickup, whichever came first.
 * Whole minutes beyond the free ones are added to the courier's pay (formula mode, capped).
 */
async function addWaitingPay(tx: Prisma.TransactionClient, orderId: number) {
  const o = await tx.order.findUniqueOrThrow({
    where: { id: orderId },
    select: {
      courierArrivedAt: true, acceptedAt: true, readyAt: true, pickedUpAt: true, courierPay: true, courierFeeCents: true,
      tipCents: true, deliveryFeeCents: true,
    },
  });
  if (!o.courierArrivedAt || !o.pickedUpAt || o.courierPay === null) return;
  const pay = courierPayOf(o);
  if (pay.mode !== "formula") return;
  const rideMs = ((pay.approachKm ?? 0) / RIDE_SPEED_KMH) * 3_600_000;
  const start = Math.max(o.courierArrivedAt.getTime(), o.acceptedAt ? o.acceptedAt.getTime() + rideMs : 0);
  const end = o.readyAt && o.readyAt < o.pickedUpAt ? o.readyAt.getTime() : o.pickedUpAt.getTime();
  const waitMinutes = Math.floor(Math.max(0, end - start) / 60_000);
  const next = withWaiting(pay, waitMinutes);
  await tx.order.update({
    where: { id: orderId },
    data: { courierPay: next as unknown as Prisma.InputJsonValue, courierFeeCents: next.totalCents },
  });
}

/**
 * The assigned courier says they are at the shop: starts the waiting clock. Set once; repeating it
 * changes nothing. Only before pickup (CONFIRMED or PROCESSING).
 */
export async function markArrivedAtStore(orderId: number, userId: number) {
  const courier = await requireApprovedCourier(userId);
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { store: { select: { latitude: true, longitude: true } } } });
  if (!order || order.courierId !== courier.id) throw new OrderError("Order not found", 404);
  if (order.status !== "CONFIRMED" && order.status !== "PROCESSING") {
    throw new OrderError("You can only check in at the shop before pickup", 409);
  }
  // The waiting clock starts only with a fresh position at the shop (within 300 m)
  const pos = freshPosition(courier);
  const atShop = !!pos && order.store.latitude !== null && order.store.longitude !== null
    && haversineKm(pos.lat, pos.lng, order.store.latitude, order.store.longitude) <= ARRIVAL_RADIUS_KM;
  if (!atShop) {
    throw new OrderError("Check in when you are at the shop: your current position is not within 300 m of it. Keep location sharing on.", 409);
  }
  const res = await prisma.order.updateMany({
    where: { id: orderId, courierId: courier.id, courierArrivedAt: null, status: { in: ["CONFIRMED", "PROCESSING"] } },
    data: { courierArrivedAt: new Date() },
  });
  const updated = await prisma.order.findUniqueOrThrow({ where: { id: orderId }, omit: { courierPay: false } });
  if (res.count > 0) {
    emitToStore(updated.storeId, "order:status", { orderId, status: updated.status, courierArrivedAt: updated.courierArrivedAt });
  }
  return { ...updated, courierPay: presentCourierPay(updated) };
}

const STATUS_PUSH: Partial<Record<OrderStatus, (o: { id: number; etaMinutes: number | null }) => { title: string; body: string }>> = {
  CONFIRMED: (o) => ({ title: `Order #${o.id} accepted`, body: "The store is getting your order ready." }),
  PROCESSING: (o) => ({ title: `Order #${o.id} is being packed`, body: "A courier will pick it up soon." }),
  SHIPPED: (o) => ({ title: `Order #${o.id} is on its way`, body: "Follow your courier live in the app." }),
  DELIVERED: (o) => ({ title: `Order #${o.id} delivered`, body: "Enjoy! You can rate the store and return items within 14 days." }),
};

/** Reserve & collect: what the customer hears instead of the courier messages. */
const PICKUP_PUSH: Partial<Record<OrderStatus, (o: { id: number; storeName: string }) => { title: string; body: string }>> = {
  CONFIRMED: (o) => ({ title: `Order #${o.id} accepted`, body: `${o.storeName} is getting your order ready for pickup.` }),
  PROCESSING: (o) => ({ title: `Ready for pickup at ${o.storeName}`, body: `Order #${o.id} is waiting for you. Show your pickup code at the store.` }),
  DELIVERED: (o) => ({ title: `Order #${o.id} collected`, body: "Enjoy! You can rate the store and return items within 14 days." }),
};

type StatusOrder = { id: number; storeId: number; userId: number; etaMinutes: number | null; fulfilment: Fulfilment; readyAt?: Date | null };

function afterStatusChange(order: StatusOrder, email: string, next: OrderStatus) {
  const pickup = order.fulfilment === "PICKUP";
  emitOrderStatus(order.id, { status: next, ...(pickup && next === "PROCESSING" ? { readyAt: order.readyAt } : {}) });
  emitToStore(order.storeId, "order:status", { orderId: order.id, status: next });
  const emailStatus = pickup && next === "PROCESSING" ? "READY_FOR_PICKUP" : pickup && next === "DELIVERED" ? "COLLECTED" : next;
  sendOrderStatusEmail(order.id, email, emailStatus).catch(() => {});
  if (pickup) {
    prisma.store.findUnique({ where: { id: order.storeId }, select: { name: true } }).then((s) => {
      const push = PICKUP_PUSH[next]?.({ id: order.id, storeName: s?.name ?? "the store" });
      if (push) return pushToUser(order.userId, { ...push, data: { type: "order", orderId: String(order.id) } });
    }).catch(() => {});
  } else {
    const push = STATUS_PUSH[next]?.(order);
    if (push) pushToUser(order.userId, { ...push, data: { type: "order", orderId: String(order.id) } }).catch(() => {});
  }

  if (next === "CONFIRMED" && !pickup) offerOrderToCouriers(order.id).catch((e) => logger.error({ orderId: order.id, e }, "Dispatch failed"));
  if (next === "DELIVERED") {
    createPayoutsForOrder(order.id).catch((e) => logger.error({ orderId: order.id, err: e?.message }, "Payout creation failed"));
    rewardReferralForOrder(order.id).catch((e) => logger.error({ orderId: order.id, err: e?.message }, "Referral reward failed"));
  }
}

/** An OrderError the store app can act on: how many tries are left, and until when the handover is locked. */
class PickupCodeError extends OrderError {
  constructor(message: string, public attemptsLeft: number, public lockedUntil?: Date) {
    super(message, 400);
  }
}
export { PickupCodeError };

/**
 * Reserve & collect handover: the store types in the customer's 6-digit code. A wrong code costs one of
 * 5 attempts; then the handover is locked for 15 minutes. The right code completes the order (DELIVERED,
 * handoverMethod PICKUP), which starts the 14-day withdrawal period and schedules the store payout.
 */
export async function collectOrder(orderId: number, userId: number, code: string) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      id: true, status: true, fulfilment: true, paymentStatus: true, pickupCode: true, pickupFailedAttempts: true,
      pickupLockedUntil: true, store: { select: { ownerId: true } }, user: { select: { email: true } },
    },
  });
  if (!order || order.store.ownerId !== userId) throw new OrderError("Order not found", 404);
  if (order.fulfilment !== "PICKUP") throw new OrderError("This order is delivered by a courier", 409);
  if (order.paymentStatus !== "SUCCEEDED" || !order.pickupCode) throw new OrderError("This order has not been paid", 409);
  if (order.status === "CONFIRMED") throw new OrderError("Mark the order ready before handing it over", 409);
  if (order.status !== "PROCESSING") throw new OrderError("This order can no longer be handed over", 409);

  const now = new Date();
  if (order.pickupLockedUntil && order.pickupLockedUntil > now) {
    const min = Math.max(1, Math.ceil((order.pickupLockedUntil.getTime() - now.getTime()) / 60_000));
    throw new PickupCodeError(`Too many wrong codes. Try again in ${min} min.`, 0, order.pickupLockedUntil);
  }

  const given = Buffer.from(code.trim());
  const expected = Buffer.from(order.pickupCode);
  const match = given.length === expected.length && crypto.timingSafeEqual(given, expected);
  if (!match) {
    // A lock that has run out starts a fresh round of attempts
    const fresh = order.pickupLockedUntil !== null;
    const updated = await prisma.order.update({
      where: { id: orderId },
      data: fresh ? { pickupFailedAttempts: 1, pickupLockedUntil: null } : { pickupFailedAttempts: { increment: 1 } },
      select: { pickupFailedAttempts: true },
    });
    const attemptsLeft = Math.max(0, PICKUP_MAX_ATTEMPTS - updated.pickupFailedAttempts);
    if (attemptsLeft === 0) {
      const lockedUntil = new Date(Date.now() + PICKUP_LOCK_MINUTES * 60_000);
      await prisma.order.update({ where: { id: orderId }, data: { pickupLockedUntil: lockedUntil, pickupFailedAttempts: 0 } });
      throw new PickupCodeError(`Wrong code. Too many tries: the handover is locked for ${PICKUP_LOCK_MINUTES} minutes.`, 0, lockedUntil);
    }
    throw new PickupCodeError(`Wrong code. ${attemptsLeft} ${attemptsLeft === 1 ? "try" : "tries"} left.`, attemptsLeft);
  }

  const updated = await prisma.$transaction(async (tx) => {
    const res = await tx.order.updateMany({
      where: { id: orderId, status: "PROCESSING", fulfilment: "PICKUP" },
      data: { status: "DELIVERED", deliveredAt: new Date(), handoverMethod: "PICKUP", pickupFailedAttempts: 0, pickupLockedUntil: null },
    });
    if (res.count === 0) throw new OrderError("The order changed in the meantime, please refresh", 409);
    return tx.order.findUniqueOrThrow({ where: { id: orderId } });
  });
  afterStatusChange(updated, order.user.email, "DELIVERED");
  return updated;
}

/**
 * The courier completes a delivery: handed over in person, or left at the door with a photo.
 * The courier's position at handover is stored with the order as proof of delivery.
 */
export async function deliverOrder(orderId: number, userId: number, input: {
  method: "IN_PERSON" | "PHOTO"; upload?: UploadProof; latitude?: number; longitude?: number;
}) {
  const courier = await requireApprovedCourier(userId);
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { user: { select: { email: true } } } });
  if (!order || order.courierId !== courier.id) throw new OrderError("Order not found", 404);
  if (order.status !== "SHIPPED") throw new OrderError("Pick the order up before completing the delivery", 409);

  let proofId: string | null = null;
  if (input.method === "PHOTO") {
    if (!input.upload) throw new OrderError("Take a photo of where you left the order");
    await verifyOwnedUpload("delivery_proof", { id: userId, role: "COURIER" }, input.upload, orderId);
    proofId = input.upload.publicId;
  }

  const updated = await prisma.$transaction(async (tx) => {
    const res = await tx.order.updateMany({
      where: { id: orderId, status: "SHIPPED", courierId: courier.id },
      data: {
        status: "DELIVERED",
        deliveredAt: new Date(),
        handoverMethod: input.method,
        deliveryProofPublicId: proofId,
        deliveredLat: input.latitude ?? null,
        deliveredLng: input.longitude ?? null,
      },
    });
    if (res.count === 0) throw new OrderError("The order changed in the meantime, please refresh", 409);
    await tx.courier.updateMany({ where: { id: courier.id, currentOrderId: orderId }, data: { currentOrderId: null } });
    return tx.order.findUniqueOrThrow({ where: { id: orderId }, omit: { courierPay: false } });
  });

  afterStatusChange(updated, order.user.email, "DELIVERED");
  return updated;
}

/** Delivery photo, for the customer, the courier who took it and Malvoya only. */
export async function getDeliveryProof(orderId: number, actor: Actor) {
  const relation = await getOrderRelation(orderId, actor);
  if (!relation || relation === "vendor") throw new OrderError("Order not found", 404);
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: { handoverMethod: true, deliveryProofPublicId: true, deliveredAt: true, deliveredLat: true, deliveredLng: true },
  });
  if (!order?.deliveredAt) throw new OrderError("This order has not been delivered yet", 409);
  return {
    method: order.handoverMethod,
    deliveredAt: order.deliveredAt,
    photoUrl: order.deliveryProofPublicId ? authenticatedImageUrl(order.deliveryProofPublicId) : null,
    location: order.deliveredLat !== null && order.deliveredLng !== null ? { lat: order.deliveredLat, lng: order.deliveredLng } : null,
  };
}

/** Delivery photos are kept 30 days, long enough to settle "where is my parcel" questions. */
export async function purgeOldDeliveryProofs() {
  const old = await prisma.order.findMany({
    where: { deliveryProofPublicId: { not: null }, deliveredAt: { lt: new Date(Date.now() - 30 * 86_400_000) } },
    select: { id: true, deliveryProofPublicId: true },
    take: 100,
  });
  for (const o of old) {
    await destroyResource(o.deliveryProofPublicId!, "image", "authenticated").catch(() => {});
    await prisma.order.update({ where: { id: o.id }, data: { deliveryProofPublicId: null, deliveredLat: null, deliveredLng: null } });
  }
  return old.length;
}

// ─── Reading orders ─────────────────────────────────────────────────────────

const courierPublic = { select: { id: true, name: true, latitude: true, longitude: true } };

const orderDetailInclude = {
  items: { include: { product: { select: { id: true, name: true, images: true } }, variant: { select: { size: true, color: true } } } },
  courier: courierPublic,
  store: { select: { id: true, name: true, address: true, latitude: true, longitude: true, logoUrl: true, phone: true } },
  promoCode: { select: { code: true, description: true } },
} satisfies Prisma.OrderInclude;

/** The pickup code is the customer's alone, and only while it is needed (accepted or ready, not yet collected). */
function withPickupCode<T extends { status: OrderStatus; pickupCode: string | null }>(order: T): T {
  return { ...order, pickupCode: order.status === "CONFIRMED" || order.status === "PROCESSING" ? order.pickupCode : null };
}

export async function getOrder(id: number, actor: Actor) {
  const relation = await getOrderRelation(id, actor);
  if (!relation) throw new OrderError("Order not found", 404);
  if (relation === "customer") {
    return withPickupCode(await prisma.order.findUniqueOrThrow({ where: { id }, omit: { pickupCode: false }, include: orderDetailInclude }));
  }
  return prisma.order.findUniqueOrThrow({ where: { id }, include: orderDetailInclude });
}

/** The same endpoint serves every app; what you get depends on your role. */
export async function listOrdersFor(actor: Actor) {
  const include = {
    items: { include: { product: { select: { name: true, images: true } }, variant: { select: { size: true, color: true } } } },
    store: { select: { id: true, name: true, logoUrl: true, address: true, latitude: true, longitude: true } },
    review: { select: { storeRating: true } },
  };

  if (actor.role === "VENDOR") {
    const store = await prisma.store.findUnique({ where: { ownerId: actor.id }, select: { id: true } });
    if (!store) return [];
    // Unpaid orders are invisible to stores
    return prisma.order.findMany({
      where: { storeId: store.id, paymentStatus: { in: ["SUCCEEDED", "REFUNDED"] } },
      include: { ...include, courier: courierPublic },
      orderBy: { createdAt: "desc" },
      take: 200,
    });
  }
  if (actor.role === "COURIER") return listCourierOrders(actor.id);

  const mine = await prisma.order.findMany({
    where: { userId: actor.id }, omit: { pickupCode: false }, include, orderBy: { createdAt: "desc" }, take: 200,
  });
  return mine.map(withPickupCode);
}

// ─── Courier side ───────────────────────────────────────────────────────────

export async function requireApprovedCourier(userId: number) {
  const courier = await getCourierForUser(userId);
  if (!courier) throw new OrderError("Courier profile not found", 404);
  if (!courier.isApproved) throw new OrderError("Your courier account is awaiting approval", 403);
  return courier;
}

/** Paid, store-accepted, unassigned orders. Customer address is withheld until the courier accepts. */
export async function listAvailableOrders(userId: number) {
  const courier = await requireApprovedCourier(userId);
  const orders = await prisma.order.findMany({
    where: { courierId: null, fulfilment: "DELIVERY", paymentStatus: "SUCCEEDED", status: { in: ["CONFIRMED", "PROCESSING"] } },
    omit: { courierPay: false },
    include: {
      store: { select: { id: true, name: true, address: true, latitude: true, longitude: true } },
      items: { select: { quantity: true } },
    },
    orderBy: { createdAt: "asc" },
    take: 30,
  });
  return orders.map((o) => {
    // Expected pay for this courier before any waiting, explained in fi/en; the ride to the shop is
    // estimated from the courier's last known position and fixed when they accept.
    const courierPay = presentCourierPay(o, { approachStraightKm: approachStraightKm(courier, o.store) });
    return {
      id: o.id,
      status: o.status,
      store: o.store,
      itemCount: o.items.reduce((sum, i) => sum + i.quantity, 0),
      deliveryFeeCents: o.deliveryFeeCents,
      courierFeeCents: courierPay.totalCents, // tip included; = courierPay.totalCents
      tipCents: o.tipCents,
      courierPay,
      deliveryAreaLat: o.deliveryLat === null ? null : Math.round(o.deliveryLat * 100) / 100,
      deliveryAreaLng: o.deliveryLng === null ? null : Math.round(o.deliveryLng * 100) / 100,
      // When the job was first offered (the store accepted it)
      offeredAt: o.confirmedAt ?? o.lastOfferAt,
      createdAt: o.createdAt,
    };
  });
}

export async function listCourierOrders(userId: number) {
  const courier = await getCourierForUser(userId);
  if (!courier) return [];
  const orders = await prisma.order.findMany({
    where: { courierId: courier.id },
    omit: { courierPay: false },
    include: {
      store: { select: { id: true, name: true, address: true, latitude: true, longitude: true, phone: true } },
      items: { include: { product: { select: { name: true, images: true } } } },
      user: { select: { name: true } },
    },
    orderBy: { updatedAt: "desc" },
    take: 100,
  });
  // courierArrivedAt is a plain column; courierPay is the final breakdown (waiting is added at pickup)
  return orders.map((o) => ({ ...o, courierPay: presentCourierPay(o) }));
}

/** First courier to accept wins; the conditional update makes double assignment impossible. */
export async function acceptOrder(orderId: number, userId: number) {
  const courier = await requireApprovedCourier(userId);
  if (!courier.isActive) throw new OrderError("Go online before accepting deliveries", 409);
  if (courier.currentOrderId) throw new OrderError("Finish your current delivery first", 409);
  // A courier whose fresh position is beyond the maximum ride cannot take the job (and cannot inflate ride pay)
  const target = await prisma.order.findUnique({ where: { id: orderId }, select: { store: { select: { latitude: true, longitude: true } } } });
  const km = target ? approachStraightKm(courier, target.store) : null;
  if (km !== null && km > env.courierPay.approachMaxKm) {
    throw new OrderError("You are too far from the shop to take this job", 409);
  }

  const updated = await prisma.$transaction(async (tx) => {
    const res = await tx.order.updateMany({
      where: { id: orderId, courierId: null, fulfilment: "DELIVERY", paymentStatus: "SUCCEEDED", status: { in: ["CONFIRMED", "PROCESSING"] } },
      data: { courierId: courier.id, acceptedAt: new Date() },
    });
    if (res.count === 0) throw new OrderError("This delivery is no longer available", 409);
    await tx.courier.update({ where: { id: courier.id }, data: { currentOrderId: orderId } });
    await addApproachPay(tx, orderId, courier);
    return tx.order.findUniqueOrThrow({ where: { id: orderId }, omit: { courierPay: false } });
  });

  emitToAllCouriers("courier:offer_closed", { orderId, reason: "taken" });
  emitOrderStatus(orderId, { status: updated.status, courierId: courier.id, courierName: courier.name });
  emitToStore(updated.storeId, "order:status", { orderId, status: updated.status, courierName: courier.name });
  pushToUser(updated.userId, {
    title: `${courier.name.split(" ")[0]} is delivering your order`,
    body: "Your courier is heading to the store.",
    data: { type: "order", orderId: String(orderId) },
  }).catch(() => {});
  return updated;
}

// ─── RENTALS ─────────────────────────────────────────────────────────────────

export async function createRental(userId: number, input: {
  startDate: string; endDate: string; deliveryAddress: string; items: ItemInput[];
}) {
  const start = new Date(input.startDate);
  const end   = new Date(input.endDate);
  const days  = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
  if (days < 1 || days > 60) throw new OrderError("Rentals must last between 1 and 60 days");

  let totalSubCents = 0;
  let totalDepositCents = 0;
  const itemsData: Prisma.RentalItemCreateManyRentalInput[] = [];

  for (const item of input.items) {
    const product = await prisma.product.findUnique({ where: { id: item.productId }, include: { store: true } });
    if (!product || !product.store.isVerified) throw new OrderError(`Product ${item.productId} not found`, 404);
    if (!product.canBeRented || !product.isAvailable || product.rentalDayCents === null || product.depositCents === null) {
      throw new OrderError(`${product.name} is not available for rent`);
    }

    const conflict = await prisma.rentalItem.findFirst({
      where: {
        productId: item.productId,
        rental: { status: { in: ["PENDING", "CONFIRMED", "ACTIVE"] }, startDate: { lt: end }, endDate: { gt: start } },
      },
    });
    if (conflict) throw new OrderError(`${product.name} is already rented for those dates`, 409);

    const pricing = calcRentalPricing(product.rentalDayCents, item.quantity, days, product.depositCents);
    totalSubCents     += pricing.subtotalCents;
    totalDepositCents += pricing.depositCents;
    itemsData.push({ productId: item.productId, variantId: item.variantId, quantity: item.quantity, dailyCents: product.rentalDayCents });
  }

  const commissionCents  = Math.round(totalSubCents * 0.10);
  const deliveryFeeCents = env.deliveryFeeCents;
  const totalCents       = totalSubCents + totalDepositCents + deliveryFeeCents;

  const rental = await prisma.rental.create({
    data: {
      userId, startDate: start, endDate: end, rentalDays: days,
      subtotalCents: totalSubCents, depositCents: totalDepositCents,
      commissionCents, deliveryFeeCents, totalCents,
      items: { createMany: { data: itemsData } },
    },
    include: { items: true },
  });

  try {
    const paymentIntent = await getStripe().paymentIntents.create(
      {
        amount: totalCents,
        currency: "eur",
        automatic_payment_methods: { enabled: true },
        metadata: { type: "RENTAL", rentalId: String(rental.id), userId: String(userId) },
        description: `Malvoya rental #${rental.id}`,
      },
      { idempotencyKey: `rental-${rental.id}` }
    );
    await prisma.rental.update({ where: { id: rental.id }, data: { stripePaymentIntentId: paymentIntent.id } });
    return { rental, clientSecret: paymentIntent.client_secret };
  } catch (err) {
    await prisma.rental.update({ where: { id: rental.id }, data: { status: "CANCELLED" } });
    throw err;
  }
}

export async function markRentalPaid(rentalId: number, paymentIntentId: string, amountReceived: number) {
  const rental = await prisma.rental.findUnique({ where: { id: rentalId } });
  if (!rental || rental.stripePaymentIntentId !== paymentIntentId || rental.paymentStatus === "SUCCEEDED") return;
  if (amountReceived !== rental.totalCents) {
    logger.error({ rentalId, amountReceived, expected: rental.totalCents }, "Paid amount does not match rental total");
    return;
  }
  await prisma.rental.update({ where: { id: rentalId }, data: { paymentStatus: "SUCCEEDED", status: "CONFIRMED" } });
}

export async function getRental(id: number, userId: number) {
  const rental = await prisma.rental.findUnique({
    where: { id },
    include: { items: { include: { product: true } }, courier: courierPublic },
  });
  if (!rental || rental.userId !== userId) throw new OrderError("Rental not found", 404);
  return rental;
}

export async function listRentals(userId: number) {
  return prisma.rental.findMany({
    where: { userId },
    include: { items: { include: { product: { select: { name: true, images: true } } } } },
    orderBy: { createdAt: "desc" },
  });
}

// ─── RETURNS (14-day right of withdrawal) ───────────────────────────────────

type ReturnLine = { orderItemId: number; quantity: number };
type PlanItem = { id: number; quantity: number; unitCents: number; product?: { name: string } };
type PlanReturn = {
  id: number; status: string; refundCents: number | null; damageDedCents: number | null; items: ReturnLine[];
};
type PlanOrder = {
  subtotalCents: number; deliveryFeeCents: number; serviceFeeCents: number; smallOrderFeeCents: number; discountCents: number;
  items: PlanItem[]; returns: PlanReturn[];
};

/** Order lines a return covers. Returns made before 2.8 have no rows and cover the whole order. */
function linesOf(ret: { items: ReturnLine[] }, orderItems: { id: number; quantity: number }[]): ReturnLine[] {
  return ret.items.length
    ? ret.items.map((i) => ({ orderItemId: i.orderItemId, quantity: i.quantity }))
    : orderItems.map((i) => ({ orderItemId: i.id, quantity: i.quantity }));
}

function sumQuantities(returns: { items: ReturnLine[] }[], orderItems: { id: number; quantity: number }[]) {
  const used = new Map<number, number>();
  for (const r of returns) for (const l of linesOf(r, orderItems)) used.set(l.orderItemId, (used.get(l.orderItemId) ?? 0) + l.quantity);
  return used;
}

/**
 * What a return refunds by default (before any deduction):
 *  - some items: Σ unit price × quantity, less the promo discount in proportion (Malvoya's discount is shared
 *    over the items; service and small-order fees stay with the order while part of it is kept);
 *  - the return that completes the order (with the earlier refunded returns): everything paid for the sale —
 *    items, the original delivery fee, service and small-order fees, less the discount — minus what earlier
 *    returns already refunded or deducted. So a whole order returned at once or in parts refunds the same total
 *    (Kuluttajansuojalaki 6:16). The courier tip is not part of the sale.
 * `goodsCents` is the undiscounted value of the returned goods, used to reduce the store payout.
 */
function refundPlan(order: PlanOrder, ret: PlanReturn) {
  const lines = linesOf(ret, order.items);
  const byId = new Map(order.items.map((i) => [i.id, i]));
  const goodsCents = lines.reduce((s, l) => s + (byId.get(l.orderItemId)?.unitCents ?? 0) * l.quantity, 0);
  const bought = order.items.reduce((s, i) => s + i.quantity, 0);
  const refunded = order.returns.filter((r) => r.id !== ret.id && r.status === "REFUNDED");
  const refundedQty = [...sumQuantities(refunded, order.items).values()].reduce((a, b) => a + b, 0);
  const completesOrder = refundedQty + lines.reduce((s, l) => s + l.quantity, 0) >= bought;
  let refundCents: number;
  if (completesOrder) {
    const paidForSale = order.subtotalCents + order.deliveryFeeCents + order.serviceFeeCents + order.smallOrderFeeCents - order.discountCents;
    const accounted = refunded.reduce((s, r) => s + (r.refundCents ?? 0) + (r.damageDedCents ?? 0), 0);
    refundCents = paidForSale - accounted;
  } else {
    const share = order.subtotalCents > 0 ? Math.round((order.discountCents * goodsCents) / order.subtotalCents) : 0;
    refundCents = goodsCents - share;
  }
  return { lines, goodsCents, completesOrder, refundCents: Math.max(0, refundCents) };
}

/**
 * Return payload: `items` = [{ orderItemId, quantity, name, unitCents }], `refundCents` = what was refunded
 * (null until then) and `expectedRefundCents` = what refunding it now would give back by default.
 */
function presentReturn<R extends PlanReturn>(ret: R, order: PlanOrder | null) {
  if (!order) return { ...ret, items: [] as { orderItemId: number; quantity: number; name: string; unitCents: number }[], expectedRefundCents: null };
  const plan = refundPlan(order, ret);
  const byId = new Map(order.items.map((i) => [i.id, i]));
  return {
    ...ret,
    items: plan.lines.map((l) => ({
      orderItemId: l.orderItemId,
      quantity: l.quantity,
      name: byId.get(l.orderItemId)?.product?.name ?? "",
      unitCents: byId.get(l.orderItemId)?.unitCents ?? 0,
    })),
    expectedRefundCents: ret.status === "REFUNDED" ? ret.refundCents : ret.status === "REJECTED" ? null : plan.refundCents,
  };
}

const returnItemsSelect = { select: { orderItemId: true, quantity: true } } as const;
const planOrderSelect = {
  subtotalCents: true, deliveryFeeCents: true, serviceFeeCents: true, smallOrderFeeCents: true, discountCents: true,
  items: { select: { id: true, quantity: true, unitCents: true, productId: true, variantId: true, product: { select: { name: true } } } },
  returns: { select: { id: true, status: true, refundCents: true, damageDedCents: true, items: returnItemsSelect } },
} satisfies Prisma.OrderSelect;

export async function createReturn(userId: number, input: {
  orderId?: number; rentalId?: number; reason: string; conditionNote?: string; items?: ReturnLine[];
}) {
  let lines: ReturnLine[] = [];
  if (input.orderId) {
    const order = await prisma.order.findUnique({
      where: { id: input.orderId },
      select: { id: true, userId: true, status: true, deliveredAt: true, ...planOrderSelect },
    });
    if (!order || order.userId !== userId) throw new OrderError("Order not found", 404);
    if (order.status !== "DELIVERED" || !order.deliveredAt) throw new OrderError("You can return an order once it has been delivered");
    // Kuluttajansuojalaki 6:14 — 14 days from the day the consumer received the goods
    const windowMs = env.returnWindowDays * 24 * 60 * 60 * 1000;
    if (Date.now() - order.deliveredAt.getTime() > windowMs) {
      throw new OrderError(`The ${env.returnWindowDays}-day return period has ended`);
    }
    // What is still returnable: bought − in every return that was not rejected
    const used = sumQuantities(order.returns.filter((r) => r.status !== "REJECTED"), order.items);
    const left = new Map(order.items.map((i) => [i.id, i.quantity - (used.get(i.id) ?? 0)]));
    if (input.items) {
      const wanted = new Map<number, number>();
      for (const it of input.items) wanted.set(it.orderItemId, (wanted.get(it.orderItemId) ?? 0) + it.quantity);
      for (const [orderItemId, quantity] of wanted) {
        const line = order.items.find((i) => i.id === orderItemId);
        if (!line) throw new OrderError(`Item ${orderItemId} is not part of this order`);
        const max = left.get(orderItemId) ?? 0;
        if (quantity > max) {
          throw new OrderError(max === 0
            ? `${line.product.name} has already been returned`
            : `You can return at most ${max} × ${line.product.name}`);
        }
        lines.push({ orderItemId, quantity });
      }
    } else {
      // The whole order (what is left of it), as before
      lines = [...left].filter(([, q]) => q > 0).map(([orderItemId, quantity]) => ({ orderItemId, quantity }));
      if (!lines.length) throw new OrderError("A return for this order already exists", 409);
    }
  }

  if (input.rentalId) {
    const rental = await prisma.rental.findUnique({ where: { id: input.rentalId } });
    if (!rental || rental.userId !== userId) throw new OrderError("Rental not found", 404);
    if (!["ACTIVE", "OVERDUE"].includes(rental.status)) throw new OrderError("Rental must be active to initiate return");
  }

  const created = await prisma.return.create({
    data: {
      userId, orderId: input.orderId, rentalId: input.rentalId, reason: input.reason as any, conditionNote: input.conditionNote,
      ...(lines.length ? { items: { createMany: { data: lines } } } : {}),
    },
    include: { items: returnItemsSelect },
  });
  return getReturn(created.id, { id: userId, role: "CUSTOMER" });
}

/**
 * Store (or admin) processes a return. REFUNDED issues a real Stripe refund for the returned items
 * (see refundPlan) and puts them back into stock.
 * A deduction is only lawful for handling beyond what was needed to inspect the item
 * (Kuluttajansuojalaki 6:17), so any deduction must come with a written condition note.
 */
export async function updateReturnStatus(id: number, actor: Actor, data: {
  status: "APPROVED" | "IN_TRANSIT" | "RECEIVED" | "REFUNDED" | "REJECTED";
  conditionNote?: string; refundCents?: number; damageDedCents?: number;
}) {
  const ret = await prisma.return.findUnique({
    where: { id },
    include: {
      items: returnItemsSelect,
      order: {
        select: {
          id: true, totalCents: true, refundedCents: true, stripePaymentIntentId: true, paymentStatus: true,
          store: { select: { ownerId: true } }, ...planOrderSelect,
        },
      },
    },
  });
  if (!ret || !ret.order) throw new OrderError("Return not found", 404);
  if (actor.role !== "ADMIN" && ret.order.store.ownerId !== actor.id) throw new OrderError("Forbidden", 403);
  if (ret.status === "REFUNDED") throw new OrderError("This return has already been refunded", 409);

  if (data.status !== "REFUNDED") {
    await prisma.return.update({ where: { id }, data: { status: data.status, conditionNote: data.conditionNote } });
    return getReturn(id, actor);
  }

  const order = ret.order;
  const plan = refundPlan(order, ret);
  const deduction = data.damageDedCents ?? 0;
  if (deduction > 0 && !data.conditionNote) throw new OrderError("Explain the deduction in the condition note");
  const refundCents = data.refundCents ?? plan.refundCents - deduction;
  const refundable = order.totalCents - order.refundedCents;
  if (refundCents <= 0 || refundCents > refundable) throw new OrderError(`Refund must be between 0.01 and ${(refundable / 100).toFixed(2)} €`);
  if (!order.stripePaymentIntentId || order.paymentStatus !== "SUCCEEDED") throw new OrderError("Order has no captured payment to refund", 409);

  await getStripe().refunds.create(
    { payment_intent: order.stripePaymentIntentId, amount: refundCents, metadata: { returnId: String(id) } },
    { idempotencyKey: `return-refund-${id}` }
  );

  const byId = new Map(order.items.map((i) => [i.id, i]));
  const returned = plan.lines.map((l) => ({ item: byId.get(l.orderItemId)!, quantity: l.quantity })).filter((r) => r.item);
  await prisma.$transaction([
    prisma.return.update({ where: { id }, data: { status: "REFUNDED", refundCents, damageDedCents: deduction, conditionNote: data.conditionNote } }),
    prisma.order.update({
      where: { id: order.id },
      data: {
        refundedCents: { increment: refundCents },
        ...(order.refundedCents + refundCents >= order.totalCents ? { paymentStatus: "REFUNDED", status: "REFUNDED" } : {}),
      },
    }),
    // Returned goods go back into stock
    ...returned.map((r) => prisma.product.update({ where: { id: r.item.productId }, data: { stockQuantity: { increment: r.quantity } } })),
    ...returned.filter((r) => r.item.variantId).map((r) => prisma.productVariant.update({ where: { id: r.item.variantId! }, data: { stock: { increment: r.quantity } } })),
  ]);
  // The store gives back the value of the returned goods (less the commission on them); with a store-chosen
  // amount the refund itself is scaled back to goods value as before
  await adjustStorePayoutForRefund(order.id, refundCents, data.refundCents === undefined ? Math.max(0, plan.goodsCents - deduction) : undefined);
  pushToUser(ret.userId, {
    title: "Refund sent",
    body: `${(refundCents / 100).toFixed(2).replace(".", ",")} € for order #${order.id} is on its way back to you.`,
    data: { type: "order", orderId: String(order.id) },
  }).catch(() => {});
  return getReturn(id, actor);
}

/** Customers see their own returns; stores see returns of their orders so they can process them. */
export async function listReturns(actor: Actor) {
  let where: Prisma.ReturnWhereInput = { userId: actor.id };
  if (actor.role === "VENDOR") {
    const store = await prisma.store.findUnique({ where: { ownerId: actor.id }, select: { id: true } });
    if (!store) return [];
    where = { order: { storeId: store.id } };
  } else if (actor.role === "ADMIN") {
    where = {};
  }
  const rows = await prisma.return.findMany({
    where,
    include: {
      items: returnItemsSelect,
      order: {
        select: {
          id: true, totalCents: true, subtotalCents: true, deliveryFeeCents: true, refundedCents: true, deliveredAt: true,
          serviceFeeCents: true, smallOrderFeeCents: true, discountCents: true, tipCents: true,
          store: { select: { name: true } },
          items: { select: { id: true, quantity: true, unitCents: true, product: { select: { name: true, images: true } }, variant: { select: { size: true, color: true } } } },
          returns: { select: { id: true, status: true, refundCents: true, damageDedCents: true, items: returnItemsSelect } },
        },
      },
    },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  return rows.map((r) => {
    const presented = presentReturn(r, r.order);
    if (!presented.order) return presented;
    const { returns: _others, ...order } = presented.order;
    return { ...presented, order };
  });
}

export async function getReturn(id: number, actor: Actor) {
  const ret = await prisma.return.findUnique({
    where: { id },
    include: { items: returnItemsSelect, order: { select: { store: { select: { ownerId: true } }, ...planOrderSelect } } },
  });
  if (!ret) throw new OrderError("Return not found", 404);
  const allowed = actor.role === "ADMIN" || ret.userId === actor.id || ret.order?.store.ownerId === actor.id;
  if (!allowed) throw new OrderError("Return not found", 404);
  const { order, ...rest } = presentReturn(ret, ret.order);
  return rest;
}
