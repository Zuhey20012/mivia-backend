import pino from "pino";
import { prisma } from "../lib/prisma";
import { haversineKm } from "../utils/distance";
import { emitToAllCouriers, emitToCourier } from "../lib/socket";

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
    include: { store: { select: { id: true, name: true, address: true, latitude: true, longitude: true } } },
  });
  if (!order || order.courierId || order.paymentStatus !== "SUCCEEDED") return;
  if (!["CONFIRMED", "PROCESSING"].includes(order.status)) return;

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
    createdAt: order.createdAt,
  };

  const couriers = await prisma.courier.findMany({
    where: { isApproved: true, isActive: true, currentOrderId: null },
    select: { id: true, latitude: true, longitude: true, updatedAt: true },
  });

  const nearby =
    order.store.latitude !== null && order.store.longitude !== null
      ? couriers
          .filter((c) => c.latitude !== null && c.longitude !== null && Date.now() - c.updatedAt.getTime() < LOCATION_FRESH_MS)
          .map((c) => ({ id: c.id, km: haversineKm(order.store.latitude!, order.store.longitude!, c.latitude!, c.longitude!) }))
          .filter((c) => c.km <= OFFER_RADIUS_KM)
          .sort((a, b) => a.km - b.km)
      : [];

  if (nearby.length) {
    for (const c of nearby) emitToCourier(c.id, "courier:dispatch_offer", { ...offer, pickupDistanceKm: Number(c.km.toFixed(2)) });
  } else {
    emitToAllCouriers("courier:dispatch_offer", offer);
  }

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
