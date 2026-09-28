import { env } from "../config/env";

/**
 * Haversine formula — distance between two lat/lng points in km.
 */
export function haversineKm(
  lat1: number, lng1: number,
  lat2: number, lng2: number
): number {
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(deg: number) { return (deg * Math.PI) / 180; }

/**
 * Delivery estimate shown before ordering and stored on the order: the store's preparation time,
 * a courier reaching the store, cycling at city speed, and the handover. Given as a 10-minute window.
 */
export function estimateDelivery(distanceKm: number, prepMinutes = 10) {
  const cyclingKmh = 15;
  const toStoreMinutes = 6;
  const handoverMinutes = 3;
  const travel = (distanceKm / cyclingKmh) * 60;
  const eta = Math.min(120, Math.max(15, Math.round(prepMinutes + toStoreMinutes + travel + handoverMinutes)));
  return { etaMinutes: eta, etaMaxMinutes: eta + 10 };
}

/** Kept for older callers: lower bound of the estimate with the default preparation time. */
export function calcEtaMinutes(distanceKm: number): number {
  return estimateDelivery(distanceKm).etaMinutes;
}
