import { Router, Response, Request } from "express";
import { z } from "zod";
import pino from "pino";
import { auth, AuthRequest } from "../../middleware/auth";
import { sendError } from "../../lib/errors";
import { prisma } from "../../lib/prisma";
import { pushToUsers } from "../../lib/push";
import { haversineKm } from "../../utils/distance";

const logger = pino({ name: "launch-alerts" });

/** A store this close to someone's pinned spot counts as "open near you". */
export const LAUNCH_ALERT_RADIUS_KM = 10;

const alertSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  area: z.string().trim().max(120).optional(),
});

export const launchAlertRoutes = Router();

/** "Tell me when Malvoya opens near me". One location per customer; re-saving moves it and re-arms it. */
launchAlertRoutes.get("/me/launch-alert", auth, async (req: AuthRequest, res: Response) => {
  try {
    const alert = await prisma.launchAlert.findUnique({ where: { userId: req.user!.id } });
    res.json({ ok: true, alert });
  } catch (e) { sendError(res, e); }
});

launchAlertRoutes.put("/me/launch-alert", auth, async (req: AuthRequest, res: Response) => {
  const body = alertSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Pick your delivery address first" });
  try {
    const data = { ...body.data, notifiedAt: null };
    const alert = await prisma.launchAlert.upsert({
      where: { userId: req.user!.id },
      create: { userId: req.user!.id, ...data },
      update: data,
    });
    res.json({ ok: true, alert });
  } catch (e) { sendError(res, e); }
});

launchAlertRoutes.delete("/me/launch-alert", auth, async (req: AuthRequest, res: Response) => {
  try {
    await prisma.launchAlert.deleteMany({ where: { userId: req.user!.id } });
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

/** Called when a store goes live: tells everyone waiting nearby, once. */
export async function notifyLaunchAlertsNear(store: { id: number; name: string; latitude: number | null; longitude: number | null }) {
  if (store.latitude === null || store.longitude === null) return 0;
  // Rough bounding box first (1° latitude ≈ 111 km), exact distance after
  const dLat = LAUNCH_ALERT_RADIUS_KM / 111;
  const dLng = LAUNCH_ALERT_RADIUS_KM / (111 * Math.max(0.2, Math.cos((store.latitude * Math.PI) / 180)));
  const candidates = await prisma.launchAlert.findMany({
    where: {
      notifiedAt: null,
      latitude: { gte: store.latitude - dLat, lte: store.latitude + dLat },
      longitude: { gte: store.longitude - dLng, lte: store.longitude + dLng },
    },
    select: { id: true, userId: true, latitude: true, longitude: true },
  });
  const near = candidates.filter((a) => haversineKm(a.latitude, a.longitude, store.latitude!, store.longitude!) <= LAUNCH_ALERT_RADIUS_KM);
  if (!near.length) return 0;

  await prisma.launchAlert.updateMany({ where: { id: { in: near.map((a) => a.id) } }, data: { notifiedAt: new Date() } });
  await pushToUsers(near.map((a) => a.userId), {
    title: "Malvoya is open near you",
    body: `${store.name} now delivers to your area. Take a look!`,
    data: { type: "store", storeId: String(store.id) },
  }).catch((e) => logger.error({ err: e?.message }, "Launch alert push failed"));
  logger.info({ storeId: store.id, notified: near.length }, "Launch alerts sent");
  return near.length;
}

/** Admin: where people are waiting, grouped into ~10 km squares, busiest first. */
export async function launchDemand(_req: Request, res: Response) {
  try {
    const alerts = await prisma.launchAlert.findMany({
      where: { notifiedAt: null },
      select: { latitude: true, longitude: true, area: true },
    });
    const groups = new Map<string, { latitude: number; longitude: number; waiting: number; areas: Map<string, number> }>();
    for (const a of alerts) {
      const lat = Math.round(a.latitude * 10) / 10;
      const lng = Math.round(a.longitude * 5) / 5;
      const key = `${lat},${lng}`;
      const g = groups.get(key) ?? { latitude: lat, longitude: lng, waiting: 0, areas: new Map() };
      g.waiting++;
      if (a.area) g.areas.set(a.area, (g.areas.get(a.area) ?? 0) + 1);
      groups.set(key, g);
    }
    const demand = [...groups.values()]
      .sort((a, b) => b.waiting - a.waiting)
      .map((g) => ({
        latitude: g.latitude,
        longitude: g.longitude,
        waiting: g.waiting,
        // Most mentioned place names, so the admin sees "Kallio, Helsinki" instead of coordinates
        areas: [...g.areas.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([name]) => name),
      }));
    res.json({ ok: true, totalWaiting: alerts.length, demand });
  } catch (e) { sendError(res, e); }
}
