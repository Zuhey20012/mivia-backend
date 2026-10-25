import { Router, Request, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { sendError } from "../../lib/errors";
import { publicCache } from "../../middleware/httpCache";
import { storeAvailability } from "../../utils/openingHours";
import { availableSlots, helsinkiParts } from "../../utils/deliverySlots";
import { REACH_KM, storesInReach } from "./categories";

/**
 * Same-day signal for Home ("Delivered today" rail, docs/design/category-sections-v2.md §1):
 * GET /delivery/today?lat&lng → { possible, slots, date, reach }.
 *  - possible: at least one approved store within reach is open now AND at least one approved courier was online
 *    recently (online switch on and a position reported in the last COURIER_RECENT_MINUTES).
 *  - slots: today's configured DELIVERY_SLOTS that can still be booked at a store within reach (start ≥ lead time,
 *    store open at the start). Empty when DELIVERY_SLOTS is empty. Times only ever come from the configuration.
 */
export const COURIER_RECENT_MINUTES = 10;

export async function sameDay(lat: number | null, lng: number | null, now = new Date()) {
  const ids = await storesInReach(lat, lng);
  const stores = await prisma.store.findMany({
    where: { isVerified: true, ...(ids ? { id: { in: ids } } : {}) },
    select: { id: true, acceptingOrders: true, openingHours: true },
    take: 500,
  });
  const openNow = stores.some((s) => storeAvailability(s, now).openNow);
  const courier = await prisma.courier.findFirst({
    where: { isApproved: true, isActive: true, locationAt: { gte: new Date(now.getTime() - COURIER_RECENT_MINUTES * 60_000) } },
    select: { id: true },
  });
  const today = helsinkiParts(now).date;
  const slots = new Map<string, { label: { en: string; fi: string }; start: string; end: string; date: string }>();
  for (const s of stores) {
    if (!s.acceptingOrders) continue;
    for (const slot of availableSlots(s, now)) {
      if (slot.date !== today) continue;
      if (!slots.has(slot.start)) slots.set(slot.start, { label: slot.label, start: slot.start, end: slot.end, date: slot.date });
    }
  }
  return {
    possible: openNow && !!courier,
    slots: [...slots.values()].sort((a, b) => (a.start < b.start ? -1 : 1)),
    date: today,
    reach: { km: REACH_KM, located: ids !== null, stores: stores.length },
  };
}

const q = z.object({
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
});

export const sameDayRoutes = Router();
sameDayRoutes.get("/delivery/today", publicCache(30, 60), async (req: Request, res: Response) => {
  const p = q.safeParse(req.query);
  if (!p.success) return res.status(400).json({ ok: false, error: "lat and lng must be valid" });
  try {
    res.json({ ok: true, ...(await sameDay(p.data.lat ?? null, p.data.lng ?? null)) });
  } catch (e) { sendError(res, e); }
});
