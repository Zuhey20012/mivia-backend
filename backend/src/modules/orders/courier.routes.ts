import { Router, Response } from "express";
import { z } from "zod";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { prisma } from "../../lib/prisma";
import { getCourierForUser, getOrderRelation } from "./access";
import { getIo } from "../../lib/socket";
import { translateChatMessage } from "../../services/translationService";
import * as ordersService from "./orders.service";
import { sendOrderError } from "./orders.controller";
import { requireAgreement } from "../legal/agreements";
import { courierOnboarding, checkReadyForApproval } from "../onboarding/onboarding";

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
      courier: {
        id: courier.id, name: courier.name, isApproved: courier.isApproved, isOnline: courier.isActive, currentOrderId: courier.currentOrderId,
        phone: courier.phone, vehicleType: courier.vehicleType, locationDisclosureAt: courier.locationDisclosureAt,
      },
    });
  } catch (e) { sendOrderError(res, e); }
});

// ─── Onboarding (2.11) ───────────────────────────────────────────────────────
// { steps:[{key, done, title:{en,fi}, action}], percent, approved, readyForApproval }
router.get("/courier/me/onboarding", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    if (!(await getCourierForUser(req.user!.id))) {
      const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
      await prisma.courier.create({ data: { userId: user.id, name: user.name, phone: user.phone, isActive: false } });
    }
    const o = await courierOnboarding(req.user!.id);
    if (o.readyForApproval) await checkReadyForApproval(req.user!.id, "COURIER");
    res.json({ ok: true, ...o });
  } catch (e) { sendOrderError(res, e); }
});

export const VEHICLE_TYPES = ["bicycle", "ebike", "moped", "scooter", "car", "on_foot"] as const;
const courierProfileSchema = z.object({
  vehicleType: z.enum(VEHICLE_TYPES).optional(),
  phone: z.string().trim().regex(/^\+?[0-9 ()-]{5,20}$/, "Enter a phone number").optional(),
}).strict().refine((d) => d.vehicleType !== undefined || d.phone !== undefined, { message: "Nothing to change" });

/** Vehicle type and contact phone for the courier profile. */
router.patch("/courier/me", ...courierOnly, async (req: AuthRequest, res: Response) => {
  const body = courierProfileSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid request", vehicleTypes: VEHICLE_TYPES });
  try {
    const courier = await getCourierForUser(req.user!.id);
    if (!courier) return res.status(404).json({ ok: false, error: "Courier profile not found" });
    const updated = await prisma.courier.update({
      where: { id: courier.id },
      data: body.data,
      select: { id: true, name: true, phone: true, vehicleType: true, isApproved: true, locationDisclosureAt: true },
    });
    checkReadyForApproval(req.user!.id, "COURIER").catch(() => {});
    res.json({ ok: true, courier: updated });
  } catch (e) { sendOrderError(res, e); }
});

/** The courier read how location is used while online (the in-app disclosure). Recorded once; repeating is harmless. */
router.post("/courier/me/disclosures", ...courierOnly, async (req: AuthRequest, res: Response) => {
  const body = z.object({ locationDisclosure: z.literal(true) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "locationDisclosure: true is required" });
  try {
    const courier = await getCourierForUser(req.user!.id);
    if (!courier) return res.status(404).json({ ok: false, error: "Courier profile not found" });
    await prisma.courier.updateMany({ where: { id: courier.id, locationDisclosureAt: null }, data: { locationDisclosureAt: new Date() } });
    const after = await prisma.courier.findUniqueOrThrow({ where: { id: courier.id }, select: { locationDisclosureAt: true } });
    checkReadyForApproval(req.user!.id, "COURIER").catch(() => {});
    res.json({ ok: true, locationDisclosureAt: after.locationDisclosureAt });
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
    // Optional ?limit= (≤ 100) and ?before=<id>
    const limit = Number(req.query.limit), before = Number(req.query.before);
    res.json({ ok: true, orders: await ordersService.listCourierOrders(req.user!.id, {
      ...(Number.isInteger(limit) && limit > 0 ? { limit } : {}), ...(Number.isInteger(before) && before > 0 ? { before } : {}),
    }) });
  } catch (e) { sendOrderError(res, e); }
});

// Taking a job needs the Courier Agreement in force to be accepted (428 AGREEMENT_REQUIRED)
router.patch("/orders/:id(\\d+)/assign-courier", ...courierOnly, requireAgreement(), async (req: AuthRequest, res: Response) => {
  try {
    const order = await ordersService.acceptOrder(Number(req.params.id), req.user!.id);
    res.json({ ok: true, order, message: "Delivery accepted" });
  } catch (e) { sendOrderError(res, e); }
});

// The assigned courier is at the shop: starts the waiting clock (waiting pay is added at pickup). Idempotent.
router.post("/orders/:id(\\d+)/arrived-at-store", ...courierOnly, async (req: AuthRequest, res: Response) => {
  try {
    const order = await ordersService.markArrivedAtStore(Number(req.params.id), req.user!.id);
    res.json({ ok: true, order });
  } catch (e) { sendOrderError(res, e); }
});

// ─── Online / offline + location ────────────────────────────────────────────
// The app sends null coordinates when GPS is not available yet
const statusSchema = z.object({
  isOnline: z.boolean(),
  latitude: z.number().min(-90).max(90).nullish(),
  longitude: z.number().min(-180).max(180).nullish(),
});

// Going online needs the Courier Agreement in force to be accepted; going offline never does
router.post("/courier/status", ...courierOnly, requireAgreement((req) => req.body?.isOnline === true), async (req: AuthRequest, res: Response) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, errors: parsed.error.flatten() });
  try {
    const courier = await ordersService.requireApprovedCourier(req.user!.id);
    const { isOnline, latitude, longitude } = parsed.data;
    const updated = await prisma.courier.update({
      where: { id: courier.id },
      data: isOnline
        ? { isActive: true, ...(latitude != null && longitude != null ? { latitude, longitude, locationAt: new Date() } : {}) }
        // Going offline drops the stored location (data minimisation)
        : { isActive: false, latitude: null, longitude: null, locationAt: null },
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

    await prisma.courier.update({ where: { id: courier.id }, data: { latitude, longitude, locationAt: new Date() } });

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
