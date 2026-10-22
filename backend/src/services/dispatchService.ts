import pino from "pino";
import { prisma } from "../lib/prisma";
import { haversineKm } from "../utils/distance";
import { emitToAllCouriers, emitToCourier } from "../lib/socket";
import { pushToUser, pushToUsers } from "../lib/push";
import { euros, lowerFirst, t } from "../lib/i18n";
import { presentCourierPay } from "../utils/courierPay";
import { freshPosition } from "../utils/courierPosition";
import { env } from "../config/env";
import { beforeDispatch, windowText } from "../utils/deliverySlots";

const logger = pino({ name: "dispatch" });

/** Couriers within this radius of the store get a direct offer; if none, every online courier sees it. */
const OFFER_RADIUS_KM = 7.5;
/** Location reports older than this are ignored for distance ranking. */
const LOCATION_FRESH_MS = 10 * 60 * 1000;

/** Coordinates rounded to ~1 km so couriers see the delivery area before accepting, not the exact home. */
function approximate(value: number | null) {
  return value === null ? null : Math.round(value * 100) / 100;
}

/**
 * Offer-based dispatch: couriers decide whether to take a job (no automatic assignment).
 * The only ranking factor is distance to the store, which is logged so every decision can be
 * explained to the courier (EU Platform Work Directive, Art. 9 — transparency of automated systems).
 */
export async function offerOrderToCouriers(orderId: number) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    omit: { courierPay: false },
    include: { store: { select: { id: true, name: true, address: true, latitude: true, longitude: true, prepMinutes: true } } },
  });
  // Pickup orders are collected by the customer: couriers never see them
  if (!order || order.courierId || order.paymentStatus !== "SUCCEEDED" || order.fulfilment !== "DELIVERY") return;
  if (!["CONFIRMED", "PROCESSING"].includes(order.status)) return;
  // Scheduled delivery: nobody is offered the job before slot start − prep time − 15 min (the watchdog starts it)
  if (beforeDispatch(order, order.store.prepMinutes)) return;

  // The first offer of a scheduled order: tell the customer, once (conditional update)
  if (order.scheduledStart && order.scheduledEnd && !order.dispatchStartedAt) {
    const claimed = await prisma.order.updateMany({ where: { id: orderId, dispatchStartedAt: null }, data: { dispatchStartedAt: new Date() } });
    if (claimed.count) {
      order.dispatchStartedAt = new Date();
      const win = lowerFirst(windowText(order.scheduledStart, order.scheduledEnd));
      pushToUser(order.userId, {
        title: t(`Finding a courier for order #${order.id}`, `Etsimme lähettiä tilaukselle #${order.id}`),
        body: t(`Your delivery ${win.en} is starting: we are offering it to couriers now.`, `Toimituksesi (${win.fi}) alkaa: tarjoamme sitä nyt läheteille.`),
        data: { type: "order", orderId: String(order.id) },
      }).catch(() => {});
    }
  }

  const offer = {
    orderId: order.id,
    storeId: order.store.id,
    storeName: order.store.name,
    storeAddress: order.store.address,
    storeLat: order.store.latitude,
    storeLng: order.store.longitude,
    deliveryAreaLat: approximate(order.deliveryLat),
    deliveryAreaLng: approximate(order.deliveryLng),
    deliveryFeeCents: order.deliveryFeeCents,
    courierFeeCents: order.courierFeeCents, // tip included; = courierPay.totalCents
    tipCents: order.tipCents,
    // Before the courier accepts (Platform Work Directive). Ride to the shop: estimated per nearby courier,
    // fixed on acceptance; waiting at the shop is added at pickup.
    courierPay: presentCourierPay(order),
    // When the job was first offered (the store accepted it, or dispatch for its slot started)
    offeredAt: (order.scheduledStart ? order.dispatchStartedAt : order.confirmedAt) ?? order.lastOfferAt ?? new Date(),
    // Scheduled delivery: hand it over within this window (null = as soon as possible)
    scheduledStart: order.scheduledStart,
    scheduledEnd: order.scheduledEnd,
    createdAt: order.createdAt,
  };

  await prisma.order.update({ where: { id: orderId }, data: { lastOfferAt: new Date() } });

  // Only couriers inside a box around the store are read (the radius check below is exact); when none is near,
  // the offer goes to every online courier, read in a bounded batch. Keeps dispatch cheap with thousands online.
  const courierSelect = { id: true, userId: true, latitude: true, longitude: true, locationAt: true, updatedAt: true } as const;
  const online = { isApproved: true, isActive: true, currentOrderId: null };
  const sLat = order.store.latitude, sLng = order.store.longitude;
  const dLat = OFFER_RADIUS_KM / 111;
  const dLng = sLat !== null ? OFFER_RADIUS_KM / (111 * Math.max(0.01, Math.cos((sLat * Math.PI) / 180))) : 0;
  let couriers = sLat !== null && sLng !== null
    ? await prisma.courier.findMany({
        where: { ...online, latitude: { gte: sLat - dLat, lte: sLat + dLat }, longitude: { gte: sLng - dLng, lte: sLng + dLng } },
        select: courierSelect, take: 500,
      })
    : [];
  const anyNearby = couriers.some((c) => c.latitude !== null && c.longitude !== null && Date.now() - c.updatedAt.getTime() < LOCATION_FRESH_MS
    && haversineKm(sLat!, sLng!, c.latitude, c.longitude) <= OFFER_RADIUS_KM);
  if (!anyNearby) {
    couriers = await prisma.courier.findMany({ where: online, select: courierSelect, orderBy: { updatedAt: "desc" }, take: 2_000 });
  }

  const nearby =
    order.store.latitude !== null && order.store.longitude !== null
      ? couriers
          .filter((c) => c.latitude !== null && c.longitude !== null && Date.now() - c.updatedAt.getTime() < LOCATION_FRESH_MS)
          .map((c) => ({
            id: c.id, userId: c.userId, fresh: !!freshPosition(c),
            km: haversineKm(order.store.latitude!, order.store.longitude!, c.latitude!, c.longitude!),
          }))
          .filter((c) => c.km <= OFFER_RADIUS_KM)
          .sort((a, b) => a.km - b.km)
      : [];

  if (nearby.length) {
    for (const c of nearby) {
      // This courier's ride to the shop is part of their pay estimate (fixed when they accept); only a fresh
      // position counts, as on acceptance
      const courierPay = presentCourierPay(order, { approachStraightKm: c.fresh && c.km <= env.courierPay.approachMaxKm ? c.km : null });
      emitToCourier(c.id, "courier:dispatch_offer", {
        ...offer, courierPay, courierFeeCents: courierPay.totalCents, pickupDistanceKm: Number(c.km.toFixed(2)),
      });
    }
  } else {
    emitToAllCouriers("courier:dispatch_offer", offer);
  }
  // Same offer as a push, for couriers who are online but have the app in the background
  const recipients = (nearby.length ? nearby : couriers).map((c) => c.userId).filter((id): id is number => id !== null);
  const pay = euros(order.courierFeeCents);
  pushToUsers(recipients, {
    title: t(`New delivery · ${pay.en}`, `Uusi toimitus · ${pay.fi}`),
    body: t(`Pick up at ${order.store.name}. Open Malvoya Courier to accept.`, `Nouto: ${order.store.name}. Hyväksy Malvoya Courier -sovelluksessa.`),
    data: { type: "offer", orderId: String(order.id) },
  }).catch(() => {});

  logger.info(
    {
      orderId,
      onlineCouriers: couriers.length,
      offeredTo: nearby.length ? nearby.map((c) => ({ courierId: c.id, distanceKm: Number(c.km.toFixed(2)) })) : "all-online",
      rule: `offer to approved online couriers within ${OFFER_RADIUS_KM} km of the store, nearest first; courier accepts or ignores`,
    },
    "Dispatch offer sent"
  );
}
