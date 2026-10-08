import { Prisma, OrderStatus } from "@prisma/client";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { getStripe } from "../../lib/stripe";
import { calcOrderPricing, calcRentalPricing, deliveryFeeForDistance } from "../../utils/pricing";
import { haversineKm } from "../../utils/distance";
import { env } from "../../config/env";
import { emitOrderStatus, emitToStore } from "../../lib/socket";
import { offerOrderToCouriers } from "../../services/dispatchService";
import { sendOrderConfirmation, sendOrderStatusEmail } from "../../services/notificationDeliveryService";
import { pushToUser } from "../../lib/push";
import { authenticatedImageUrl, destroyResource } from "../../lib/cloudinary";
import { estimateDelivery } from "../../utils/distance";
import { verifyOwnedUpload, UploadProof } from "../media/media.service";
import { adjustStorePayoutForRefund, createPayoutsForOrder } from "../payouts/payouts.service";
import { Actor, getCourierForUser, getOrderRelation } from "./access";
import { storeAvailability } from "../../utils/openingHours";

const logger = pino({ name: "orders" });

export class OrderError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

type ItemInput = { productId: number; variantId?: number; quantity: number };

// ─── ORDERS (SALE) ──────────────────────────────────────────────────────────

export async function createOrder(userId: number, input: {
  storeId: number; deliveryAddress: string; deliveryLat?: number;
  deliveryLng?: number; notes?: string; items: ItemInput[];
}) {
  const store = await prisma.store.findUnique({ where: { id: input.storeId } });
  if (!store || !store.isVerified) throw new OrderError("This store is not accepting orders", 404);
  const availability = storeAvailability(store);
  if (!availability.openNow) {
    const opens = availability.opensAt ? ` It opens again at ${availability.opensAt.time}.` : "";
    throw new OrderError(
      availability.closedReason === "paused" ? "This store is not taking orders right now." : `This store is closed right now.${opens}`,
      409,
    );
  }

  // Price is always computed server-side from the database.
  const order = await prisma.$transaction(async (tx) => {
    let subtotalCents = 0;
    const itemsData: Prisma.OrderItemCreateManyOrderInput[] = [];

    for (const item of input.items) {
      const product = await tx.product.findUnique({ where: { id: item.productId } });
      if (!product || product.storeId !== store.id) throw new OrderError(`Product ${item.productId} is not sold by this store`);
      if (!product.canBeSold || !product.isAvailable || product.salePriceCents === null) {
        throw new OrderError(`${product.name} is not available for purchase`);
      }

      let unitCents = product.salePriceCents;
      if (item.variantId) {
        const variant = await tx.productVariant.findUnique({ where: { id: item.variantId } });
        if (!variant || variant.productId !== product.id) throw new OrderError(`Invalid option for ${product.name}`);
        const reserved = await tx.productVariant.updateMany({
          where: { id: variant.id, stock: { gte: item.quantity } },
          data: { stock: { decrement: item.quantity } },
        });
        if (reserved.count === 0) throw new OrderError(`${product.name} (${variant.size ?? variant.color ?? "option"}) is out of stock`);
        unitCents += variant.priceAdjustCents;
      }

      // Conditional decrement: never oversell when two customers check out at the same time.
      const reserved = await tx.product.updateMany({
        where: { id: product.id, stockQuantity: { gte: item.quantity } },
        data: { stockQuantity: { decrement: item.quantity } },
      });
      if (reserved.count === 0) throw new OrderError(`Insufficient stock for ${product.name}`);

      subtotalCents += unitCents * item.quantity;
      itemsData.push({ productId: product.id, variantId: item.variantId, quantity: item.quantity, unitCents });
    }

    const distanceKm =
      store.latitude !== null && store.longitude !== null && input.deliveryLat !== undefined && input.deliveryLng !== undefined
        ? haversineKm(store.latitude, store.longitude, input.deliveryLat, input.deliveryLng)
        : null;
    const pricing = calcOrderPricing(subtotalCents, store.commissionRate, deliveryFeeForDistance(distanceKm));
    const courierFeeCents = Math.round(pricing.deliveryFeeCents * env.courierFeeShare);
    const etaMinutes = distanceKm === null ? null : estimateDelivery(distanceKm, store.prepMinutes).etaMinutes;

    return tx.order.create({
      data: {
        userId,
        storeId: store.id,
        deliveryAddress: input.deliveryAddress,
        deliveryLat: input.deliveryLat,
        deliveryLng: input.deliveryLng,
        notes: input.notes,
        ...pricing,
        courierFeeCents,
        etaMinutes,
        items: { createMany: { data: itemsData } },
      },
      include: { items: true },
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
    include: { user: true, store: true, items: { include: { product: { select: { name: true } } } } },
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

  await prisma.order.update({ where: { id: orderId }, data: { paymentStatus: "SUCCEEDED", paidAt: new Date() } });

  emitToStore(order.storeId, "order:new", {
    id: order.id,
    status: order.status,
    totalCents: order.totalCents,
    deliveryAddress: order.deliveryAddress,
    items: order.items.map((i) => ({ name: i.product.name, quantity: i.quantity, unitCents: i.unitCents })),
    createdAt: order.createdAt,
  });
  emitOrderStatus(orderId, { status: order.status, paymentStatus: "SUCCEEDED" });
  pushToUser(order.store.ownerId, {
    title: `New order #${order.id}`,
    body: `${order.items.reduce((n, i) => n + i.quantity, 0)} item(s) · ${(order.subtotalCents / 100).toFixed(2).replace(".", ",")} € — accept it in Malvoya Store.`,
    data: { type: "order", orderId: String(order.id) },
  }).catch(() => {});

  sendOrderConfirmation({
    orderId: order.id,
    customerName: order.user.name,
    email: order.user.email,
    storeName: order.store.name,
    items: order.items.map((i) => ({ name: i.product.name, quantity: i.quantity, unitCents: i.unitCents })),
    subtotalCents: order.subtotalCents,
    deliveryFeeCents: order.deliveryFeeCents,
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
      },
    });
    if (res.count === 0) throw new OrderError("The order changed in the meantime, please refresh", 409);
    if (next === "DELIVERED" && order.courierId) {
      await tx.courier.updateMany({ where: { id: order.courierId, currentOrderId: orderId }, data: { currentOrderId: null } });
    }
    return tx.order.findUniqueOrThrow({ where: { id: orderId } });
  });

  afterStatusChange(updated, order.user.email, next);
  return updated;
}

const STATUS_PUSH: Partial<Record<OrderStatus, (o: { id: number; etaMinutes: number | null }) => { title: string; body: string }>> = {
  CONFIRMED: (o) => ({ title: `Order #${o.id} accepted`, body: "The store is getting your order ready." }),
  PROCESSING: (o) => ({ title: `Order #${o.id} is being packed`, body: "A courier will pick it up soon." }),
  SHIPPED: (o) => ({ title: `Order #${o.id} is on its way`, body: "Follow your courier live in the app." }),
  DELIVERED: (o) => ({ title: `Order #${o.id} delivered`, body: "Enjoy! You can rate the store and return items within 14 days." }),
};

function afterStatusChange(order: { id: number; storeId: number; userId: number; etaMinutes: number | null }, email: string, next: OrderStatus) {
  emitOrderStatus(order.id, { status: next });
  emitToStore(order.storeId, "order:status", { orderId: order.id, status: next });
  sendOrderStatusEmail(order.id, email, next).catch(() => {});
  const push = STATUS_PUSH[next]?.(order);
  if (push) pushToUser(order.userId, { ...push, data: { type: "order", orderId: String(order.id) } }).catch(() => {});

  if (next === "CONFIRMED") offerOrderToCouriers(order.id).catch((e) => logger.error({ orderId: order.id, e }, "Dispatch failed"));
  if (next === "DELIVERED") createPayoutsForOrder(order.id).catch((e) => logger.error({ orderId: order.id, err: e?.message }, "Payout creation failed"));
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
    return tx.order.findUniqueOrThrow({ where: { id: orderId } });
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

export async function getOrder(id: number, actor: Actor) {
  const relation = await getOrderRelation(id, actor);
  if (!relation) throw new OrderError("Order not found", 404);
  return prisma.order.findUniqueOrThrow({
    where: { id },
    include: {
      items: { include: { product: { select: { id: true, name: true, images: true } }, variant: { select: { size: true, color: true } } } },
      courier: courierPublic,
      store: { select: { id: true, name: true, address: true, latitude: true, longitude: true, logoUrl: true, phone: true } },
    },
  });
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

  return prisma.order.findMany({ where: { userId: actor.id }, include, orderBy: { createdAt: "desc" }, take: 200 });
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
  await requireApprovedCourier(userId);
  const orders = await prisma.order.findMany({
    where: { courierId: null, paymentStatus: "SUCCEEDED", status: { in: ["CONFIRMED", "PROCESSING"] } },
    include: {
      store: { select: { id: true, name: true, address: true, latitude: true, longitude: true } },
      items: { select: { quantity: true } },
    },
    orderBy: { createdAt: "asc" },
    take: 30,
  });
  return orders.map((o) => ({
    id: o.id,
    status: o.status,
    store: o.store,
    itemCount: o.items.reduce((sum, i) => sum + i.quantity, 0),
    deliveryFeeCents: o.deliveryFeeCents,
    courierFeeCents: o.courierFeeCents,
    deliveryAreaLat: o.deliveryLat === null ? null : Math.round(o.deliveryLat * 100) / 100,
    deliveryAreaLng: o.deliveryLng === null ? null : Math.round(o.deliveryLng * 100) / 100,
    createdAt: o.createdAt,
  }));
}

export async function listCourierOrders(userId: number) {
  const courier = await getCourierForUser(userId);
  if (!courier) return [];
  return prisma.order.findMany({
    where: { courierId: courier.id },
    include: {
      store: { select: { id: true, name: true, address: true, latitude: true, longitude: true, phone: true } },
      items: { include: { product: { select: { name: true, images: true } } } },
      user: { select: { name: true } },
    },
    orderBy: { updatedAt: "desc" },
    take: 100,
  });
}

/** First courier to accept wins; the conditional update makes double assignment impossible. */
export async function acceptOrder(orderId: number, userId: number) {
  const courier = await requireApprovedCourier(userId);
  if (!courier.isActive) throw new OrderError("Go online before accepting deliveries", 409);
  if (courier.currentOrderId) throw new OrderError("Finish your current delivery first", 409);

  const updated = await prisma.$transaction(async (tx) => {
    const res = await tx.order.updateMany({
      where: { id: orderId, courierId: null, paymentStatus: "SUCCEEDED", status: { in: ["CONFIRMED", "PROCESSING"] } },
      data: { courierId: courier.id, acceptedAt: new Date() },
    });
    if (res.count === 0) throw new OrderError("This delivery is no longer available", 409);
    await tx.courier.update({ where: { id: courier.id }, data: { currentOrderId: orderId } });
    return tx.order.findUniqueOrThrow({ where: { id: orderId } });
  });

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

export async function createReturn(userId: number, input: {
  orderId?: number; rentalId?: number; reason: string; conditionNote?: string;
}) {
  if (input.orderId) {
    const order = await prisma.order.findUnique({ where: { id: input.orderId } });
    if (!order || order.userId !== userId) throw new OrderError("Order not found", 404);
    if (order.status !== "DELIVERED" || !order.deliveredAt) throw new OrderError("You can return an order once it has been delivered");
    // Kuluttajansuojalaki 6:14 — 14 days from the day the consumer received the goods
    const windowMs = env.returnWindowDays * 24 * 60 * 60 * 1000;
    if (Date.now() - order.deliveredAt.getTime() > windowMs) {
      throw new OrderError(`The ${env.returnWindowDays}-day return period has ended`);
    }
    const open = await prisma.return.findFirst({ where: { orderId: order.id, status: { notIn: ["REJECTED"] } } });
    if (open) throw new OrderError("A return for this order already exists", 409);
  }

  if (input.rentalId) {
    const rental = await prisma.rental.findUnique({ where: { id: input.rentalId } });
    if (!rental || rental.userId !== userId) throw new OrderError("Rental not found", 404);
    if (!["ACTIVE", "OVERDUE"].includes(rental.status)) throw new OrderError("Rental must be active to initiate return");
  }

  return prisma.return.create({
    data: { userId, orderId: input.orderId, rentalId: input.rentalId, reason: input.reason as any, conditionNote: input.conditionNote },
  });
}

/**
 * Store (or admin) processes a return. REFUNDED issues a real Stripe refund.
 * A deduction is only lawful for handling beyond what was needed to inspect the item
 * (Kuluttajansuojalaki 6:17), so any deduction must come with a written condition note.
 */
export async function updateReturnStatus(id: number, actor: Actor, data: {
  status: "APPROVED" | "IN_TRANSIT" | "RECEIVED" | "REFUNDED" | "REJECTED";
  conditionNote?: string; refundCents?: number; damageDedCents?: number;
}) {
  const ret = await prisma.return.findUnique({ where: { id }, include: { order: { include: { store: true, items: true } } } });
  if (!ret || !ret.order) throw new OrderError("Return not found", 404);
  if (actor.role !== "ADMIN" && ret.order.store.ownerId !== actor.id) throw new OrderError("Forbidden", 403);
  if (ret.status === "REFUNDED") throw new OrderError("This return has already been refunded", 409);

  if (data.status !== "REFUNDED") {
    return prisma.return.update({ where: { id }, data: { status: data.status, conditionNote: data.conditionNote } });
  }

  const order = ret.order;
  const itemsCents = order.subtotalCents;
  const deduction = data.damageDedCents ?? 0;
  if (deduction > 0 && !data.conditionNote) throw new OrderError("Explain the deduction in the condition note");
  // Full withdrawal refunds the original delivery fee as well (Kuluttajansuojalaki 6:16)
  const refundCents = data.refundCents ?? itemsCents + order.deliveryFeeCents - deduction;
  const refundable = order.totalCents - order.refundedCents;
  if (refundCents <= 0 || refundCents > refundable) throw new OrderError(`Refund must be between 0.01 and ${(refundable / 100).toFixed(2)} €`);
  if (!order.stripePaymentIntentId || order.paymentStatus !== "SUCCEEDED") throw new OrderError("Order has no captured payment to refund", 409);

  await getStripe().refunds.create(
    { payment_intent: order.stripePaymentIntentId, amount: refundCents, metadata: { returnId: String(id) } },
    { idempotencyKey: `return-refund-${id}` }
  );

  const [updated] = await prisma.$transaction([
    prisma.return.update({ where: { id }, data: { status: "REFUNDED", refundCents, damageDedCents: deduction, conditionNote: data.conditionNote } }),
    prisma.order.update({
      where: { id: order.id },
      data: {
        refundedCents: { increment: refundCents },
        ...(order.refundedCents + refundCents >= order.totalCents ? { paymentStatus: "REFUNDED", status: "REFUNDED" } : {}),
      },
    }),
    // Returned goods go back into stock
    ...order.items.map((i) => prisma.product.update({ where: { id: i.productId }, data: { stockQuantity: { increment: i.quantity } } })),
    ...order.items.filter((i) => i.variantId).map((i) => prisma.productVariant.update({ where: { id: i.variantId! }, data: { stock: { increment: i.quantity } } })),
  ]);
  await adjustStorePayoutForRefund(order.id, refundCents);
  pushToUser(ret.userId, {
    title: "Refund sent",
    body: `${(refundCents / 100).toFixed(2).replace(".", ",")} € for order #${order.id} is on its way back to you.`,
    data: { type: "order", orderId: String(order.id) },
  }).catch(() => {});
  return updated;
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
  return prisma.return.findMany({
    where,
    include: {
      order: {
        select: {
          id: true, totalCents: true, subtotalCents: true, deliveryFeeCents: true, refundedCents: true, deliveredAt: true,
          store: { select: { name: true } },
          items: { select: { quantity: true, unitCents: true, product: { select: { name: true, images: true } }, variant: { select: { size: true, color: true } } } },
        },
      },
    },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
}

export async function getReturn(id: number, actor: Actor) {
  const ret = await prisma.return.findUnique({ where: { id }, include: { order: { select: { store: { select: { ownerId: true } } } } } });
  if (!ret) throw new OrderError("Return not found", 404);
  const allowed = actor.role === "ADMIN" || ret.userId === actor.id || ret.order?.store.ownerId === actor.id;
  if (!allowed) throw new OrderError("Return not found", 404);
  const { order, ...rest } = ret;
  return rest;
}
