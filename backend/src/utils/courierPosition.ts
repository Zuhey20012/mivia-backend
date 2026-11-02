/**
 * A courier's reported position counts only while it is fresh. Positions come from the courier app
 * (/courier/status, /courier/telemetry and the socket), so an old one is treated as unknown: it then
 * earns no ride-to-shop pay and does not prove an arrival at the shop.
 */
export const POSITION_FRESH_MS = 2 * 60_000;

export function freshPosition(c: { latitude: number | null; longitude: number | null; locationAt?: Date | null }, now = Date.now()) {
  if (c.latitude === null || c.longitude === null || !c.locationAt) return null;
  if (now - c.locationAt.getTime() > POSITION_FRESH_MS) return null;
  return { lat: c.latitude, lng: c.longitude };
}

/** Faster than this between two reports is not a courier on a bike, scooter or car in a city (2.17). */
export const MAX_PLAUSIBLE_KMH = 120;

/**
 * Whether a new position is believable after the previous one: positions implying more than 120 km/h are ignored
 * (GPS jumps or spoofing). A previous position older than 10 minutes, or none, accepts anything.
 */
export function plausibleMove(prev: { lat: number; lng: number; at: number } | null, next: { lat: number; lng: number }, now = Date.now()) {
  if (!prev || now - prev.at > 10 * 60_000) return true;
  const hours = Math.max(now - prev.at, 1000) / 3_600_000;
  const R = 6371;
  const dLat = ((next.lat - prev.lat) * Math.PI) / 180;
  const dLng = ((next.lng - prev.lng) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos((prev.lat * Math.PI) / 180) * Math.cos((next.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  const km = 2 * R * Math.asin(Math.sqrt(a));
  return km / hours <= MAX_PLAUSIBLE_KMH;
}
