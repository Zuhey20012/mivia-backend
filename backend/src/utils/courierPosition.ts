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
