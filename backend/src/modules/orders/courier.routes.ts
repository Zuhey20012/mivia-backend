import { Router, Response } from "express";
import { z } from "zod";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { prisma } from "../../lib/prisma";
import { getCourierForUser, getOrderRelation } from "./access";
import { getIo } from "../../lib/socket";
import { translateChatMessage } from "../../services/translationService";
import * as ordersService from "./orders.service";
import { sendOrderError } from "./orders.controller";

const router = Router();
const courierOnly = [auth, requireRole("COURIER")];

// ─── Courier profile / approval state ────────────────────────────────────────
router.get("/courier/me", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    let courier = await getCourierForUser(req.user!.id);
    if (!courier) {
      // Accounts created before couriers had profiles: create one, unapproved.
      const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
      courier = await prisma.courier.create({ data: { userId: user.id, name: user.name, phone: user.phone, isActive: false } });
    }
    res.json({
      ok: true,
      courier: { id: courier.id, name: courier.name, isApproved: courier.isApproved, isOnline: courier.isActive, currentOrderId: courier.currentOrderId },
    });
  } catch (e) { sendOrderError(res, e); }
});

// ─── Job board ──────────────────────────────────────────────────────────────
router.get("/orders/available", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, orders: await ordersService.listAvailableOrders(req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
});
// Older app builds call this path
router.get("/orders/unassigned", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, orders: await ordersService.listAvailableOrders(req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
});

router.get("/orders/courier/mine", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, orders: await ordersService.listCourierOrders(req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
});

router.patch("/orders/:id(\\d+)/assign-courier", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    const order = await ordersService.acceptOrder(Number(req.params.id), req.user!.id);
    res.json({ ok: true, order, message: "Delivery accepted" });
  } catch (e) { sendOrderError(res, e); }
});

// ─── Online / offline + location ────────────────────────────────────────────
// The app sends null coordinates when GPS is not available yet
const statusSchema = z.object({
  isOnline: z.boolean(),
  latitude: z.number().min(-90).max(90).nullish(),
  longitude: z.number().min(-180).max(180).nullish(),
});

router.post("/courier/status", ...courierOnly, async (req: AuthRequest, res: Response) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, errors: parsed.error.flatten() });
  try {
    const courier = await ordersService.requireApprovedCourier(req.user!.id);
    const { isOnline, latitude, longitude } = parsed.data;
    const updated = await prisma.courier.update({
      where: { id: courier.id },
      data: isOnline
        ? { isActive: true, ...(latitude != null && longitude != null ? { latitude, longitude } : {}) }
        // Going offline drops the stored location (data minimisation)
        : { isActive: false, latitude: null, longitude: null },
      select: { id: true, isActive: true, isApproved: true, currentOrderId: true },
    });
    res.json({ ok: true, courier: updated });
  } catch (e) { sendOrderError(res, e); }
});

const telemetrySchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  bearing: z.number().nullish(),
  speed: z.number().nullish(),
  accuracy: z.number().nullish(),
  orderId: z.coerce.number().int().positive().nullish().catch(null),
});

/** HTTP fallback for background location updates when the socket is not connected. */
router.post("/courier/telemetry", ...courierOnly, async (req: AuthRequest, res: Response) => {
  const parsed = telemetrySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, errors: parsed.error.flatten() });
  try {
    const courier = await ordersService.requireApprovedCourier(req.user!.id);
    if (!courier.isActive) return res.status(409).json({ ok: false, error: "You are offline" });
    const { latitude, longitude, bearing, speed, accuracy, orderId } = parsed.data;

    await prisma.courier.update({ where: { id: courier.id }, data: { latitude, longitude } });

    if (orderId) {
      const assigned = await prisma.order.findFirst({
        where: { id: orderId, courierId: courier.id, status: { in: ["CONFIRMED", "PROCESSING", "SHIPPED"] } },
        select: { id: true },
      });
      if (assigned) {
        getIo()?.to(`order:${orderId}`).emit("courier:location", {
          orderId, lat: latitude, lng: longitude, bearing: bearing ?? 0, speed: speed ?? 0, accuracy: accuracy ?? 0, timestamp: Date.now(),
        });
      }
    }
    res.json({ ok: true });
  } catch (e) { sendOrderError(res, e); }
});

// ─── Chat quick-reply translation (phrasebook only) ─────────────────────────
router.post("/chat/translate", auth, async (req: AuthRequest, res: Response) => {
  const { text, targetLanguage, orderId } = req.body ?? {};
  if (typeof text !== "string" || typeof targetLanguage !== "string" || !text.trim()) {
    return res.status(400).json({ ok: false, error: "text and targetLanguage required" });
  }
  if (orderId && !(await getOrderRelation(Number(orderId), req.user!))) {
    return res.status(404).json({ ok: false, error: "Order not found" });
  }
  res.json({ ok: true, ...translateChatMessage({ text: text.slice(0, 1000), targetLanguage }) });
});

export default router;
