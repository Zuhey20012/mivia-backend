import pino from "pino";
import { prisma } from "../lib/prisma";
import { env } from "../config/env";
import { pushToUser } from "../lib/push";
import { emitToStore } from "../lib/socket";
import { cancelOrderInternal } from "../modules/orders/orders.service";
import { sendOrderStatusEmail } from "./notificationDeliveryService";
import { offerOrderToCouriers } from "./dispatchService";

const logger = pino({ name: "order-watchdog" });
const ago = (min: number) => new Date(Date.now() - min * 60_000);
const BATCH = 100;

/**
 * Makes sure no order waits forever, whoever is (not) responding:
 *  1. unpaid checkouts release their reserved stock,
 *  2. a store that has not answered a paid order is reminded, then the order is refunded,
 *  3. jobs nobody took are offered to couriers again, the customer hears about a delay,
 *     and if still nobody comes the order is refunded.
 * Every step is idempotent and safe to run on several instances (the scheduler holds a lease).
 */
export async function runOrderWatchdog() {
  const t = env.orderTimers;
  const result = { releasedCheckouts: 0, storeReminders: 0, storeTimeouts: 0, reoffers: 0, delayNotices: 0, courierTimeouts: 0 };

  // 1. Checkouts that were never paid (the customer closed the payment sheet, or the card failed)
  const unpaid = await prisma.order.findMany({
    where: { status: "PENDING", paymentStatus: { in: ["PENDING", "FAILED"] }, createdAt: { lt: ago(t.checkoutHold) } },
    select: { id: true },
    take: BATCH,
  });
  for (const o of unpaid) {
    await cancelOrderInternal(o.id, "Payment was not completed", { notifyCustomer: false });
    result.releasedCheckouts++;
  }

  // 2a. Paid orders the store has not accepted yet: one reminder
  const waiting = await prisma.order.findMany({
    where: { status: "PENDING", paymentStatus: "SUCCEEDED", storeRemindedAt: null, paidAt: { lt: ago(t.storeReminder) } },
    select: { id: true, storeId: true, store: { select: { ownerId: true } } },
    take: BATCH,
  });
  for (const o of waiting) {
    const claimed = await prisma.order.updateMany({ where: { id: o.id, storeRemindedAt: null }, data: { storeRemindedAt: new Date() } });
    if (!claimed.count) continue;
    const left = Math.max(1, Math.round(t.storeAccept - t.storeReminder));
    pushToUser(o.store.ownerId, {
      title: `Order #${o.id} is waiting for you`,
      body: `Accept or decline it in Malvoya Store. It is cancelled and refunded automatically in about ${left} min.`,
      data: { type: "order", orderId: String(o.id) },
    }).catch(() => {});
    emitToStore(o.storeId, "order:reminder", { orderId: o.id, cancelsInMinutes: left });
    result.storeReminders++;
  }

  // 2b. ...and after the deadline, cancel with a full refund
  const unanswered = await prisma.order.findMany({
    where: { status: "PENDING", paymentStatus: "SUCCEEDED", paidAt: { lt: ago(t.storeAccept) } },
    select: { id: true, user: { select: { email: true } }, store: { select: { ownerId: true } } },
    take: BATCH,
  });
  for (const o of unanswered) {
    await cancelOrderInternal(o.id, "The store did not respond in time", {
      customerMessage: "The store did not confirm your order in time.",
    });
    sendOrderStatusEmail(o.id, o.user.email, "CANCELLED").catch(() => {});
    pushToUser(o.store.ownerId, {
      title: `Order #${o.id} was cancelled`,
      body: "It was not accepted in time, so the customer was refunded. Pause orders in the app when you cannot answer.",
      data: { type: "order", orderId: String(o.id) },
    }).catch(() => {});
    result.storeTimeouts++;
  }

  // 3. Accepted orders without a courier
  const unassigned = await prisma.order.findMany({
    where: { status: { in: ["CONFIRMED", "PROCESSING"] }, paymentStatus: "SUCCEEDED", courierId: null },
    select: {
      id: true, userId: true, confirmedAt: true, updatedAt: true, lastOfferAt: true, courierSearchNotifiedAt: true,
      user: { select: { email: true } }, store: { select: { ownerId: true } },
    },
    take: BATCH,
  });
  for (const o of unassigned) {
    const since = (o.confirmedAt ?? o.updatedAt).getTime();
    const waitedMin = (Date.now() - since) / 60_000;

    if (waitedMin >= t.courierSearch) {
      await cancelOrderInternal(o.id, "No courier was available", {
        customerMessage: "We could not find a courier for your order.",
      });
      sendOrderStatusEmail(o.id, o.user.email, "CANCELLED").catch(() => {});
      pushToUser(o.store.ownerId, {
        title: `Order #${o.id} was cancelled`,
        body: "No courier was available, so the customer was refunded. Please do not hand it over.",
        data: { type: "order", orderId: String(o.id) },
      }).catch(() => {});
      result.courierTimeouts++;
      continue;
    }

    if (waitedMin >= t.courierDelayNotice && !o.courierSearchNotifiedAt) {
      const claimed = await prisma.order.updateMany({ where: { id: o.id, courierSearchNotifiedAt: null }, data: { courierSearchNotifiedAt: new Date() } });
      if (claimed.count) {
        pushToUser(o.userId, {
          title: `Still looking for a courier`,
          body: `Order #${o.id} is ready, we are finding someone to bring it. If nobody is available you get a full refund automatically.`,
          data: { type: "order", orderId: String(o.id) },
        }).catch(() => {});
        result.delayNotices++;
      }
    }

    if (!o.lastOfferAt || o.lastOfferAt < ago(t.courierReoffer)) {
      await offerOrderToCouriers(o.id).catch((e) => logger.error({ orderId: o.id, err: e?.message }, "Re-offer failed"));
      result.reoffers++;
    }
  }

  const acted = Object.values(result).some((n) => n > 0);
  if (acted) logger.info(result, "Order watchdog acted");
  return result;
}
