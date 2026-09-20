import { Router, Response } from "express";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { prisma } from "../../lib/prisma";
import { ingestCourierTelemetry, triggerGdprTelemetrySunset, createMaskedPhoneBridge } from "../../services/telemetryService";
import { releaseEscrowOnDelivery, getEscrowRecord } from "../../services/paymentSplittingService";
import { translateChatMessage } from "../../services/translationService";
import { dispatchNotifications } from "../../services/notificationDeliveryService";
import { getIo } from "../../lib/socket";

const router = Router();

/**
 * Helper to resolve or upsert a Courier record corresponding to the authenticated user.
 */
async function resolveCourierForUser(userId: number, email: string, name: string) {
  let courier = await prisma.courier.findFirst({
    where: { email },
  });

  if (!courier) {
    courier = await prisma.courier.create({
      data: {
        name,
        email,
        isActive: true,
      },
    });
  }
  return courier;
}

// ─── 1. AVAILABLE ORDERS FOR COURIER PICKUP ─────────────────────────────────
router.get("/orders/available", auth, async (req: AuthRequest, res: Response) => {
  try {
    const orders = await prisma.order.findMany({
      where: {
        status: { in: ["PENDING", "CONFIRMED"] },
        courierId: null,
      },
      include: {
        store: { select: { id: true, name: true, address: true, latitude: true, longitude: true } },
        items: { include: { product: { select: { name: true, images: true } } } },
      },
      orderBy: { createdAt: "desc" },
      take: 20,
    });

    res.json({ ok: true, orders });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// Also support query param version: /orders?status=CONFIRMED&unassigned=true
router.get("/orders/unassigned", auth, async (_req: AuthRequest, res: Response) => {
  try {
    const orders = await prisma.order.findMany({
      where: {
        courierId: null,
      },
      include: {
        store: { select: { id: true, name: true, address: true, latitude: true, longitude: true } },
        items: { include: { product: { select: { name: true, images: true } } } },
      },
      orderBy: { createdAt: "desc" },
    });
    res.json({ ok: true, orders });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 2. COURIER'S ASSIGNED ORDERS ───────────────────────────────────────────
router.get("/orders/courier/mine", auth, async (req: AuthRequest, res: Response) => {
  try {
    const user = req.user!;
    const courier = await resolveCourierForUser(user.id, user.email, "Malvoya Courier");

    const orders = await prisma.order.findMany({
      where: { courierId: courier.id },
      include: {
        store: { select: { id: true, name: true, address: true, latitude: true, longitude: true } },
        items: { include: { product: { select: { name: true, images: true } } } },
      },
      orderBy: { updatedAt: "desc" },
    });

    res.json({ ok: true, orders });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 3. ACCEPT DELIVERY ASSIGNMENT ──────────────────────────────────────────
router.patch("/orders/:id/assign-courier", auth, async (req: AuthRequest, res: Response) => {
  try {
    const orderId = Number(req.params.id);
    const user = req.user!;
    const courier = await resolveCourierForUser(user.id, user.email, "Malvoya Courier");

    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order) return res.status(404).json({ ok: false, error: "Order not found" });

    const updated = await prisma.$transaction([
      prisma.order.update({
        where: { id: orderId },
        data: {
          courierId: courier.id,
          status: "CONFIRMED",
        },
      }),
      prisma.courier.update({
        where: { id: courier.id },
        data: { currentOrderId: orderId },
      }),
    ]);

    try {
      const io = getIo();
      io.to(`order:${orderId}`).emit("order:status", {
        status: "CONFIRMED",
        courierId: courier.id,
        courierName: courier.name,
      });
    } catch {}

    res.json({ ok: true, order: updated[0], message: "Delivery successfully accepted" });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 4. UPDATE ORDER STATUS (PICKED UP / DELIVERED) ──────────────────────────
router.patch("/orders/:id/status", auth, async (req: AuthRequest, res: Response) => {
  try {
    const orderId = Number(req.params.id);
    const { status, doorstepPhotoUrl, deliveryProofNotes } = req.body;

    if (!["CONFIRMED", "PROCESSING", "SHIPPED", "DELIVERED", "CANCELLED"].includes(status)) {
      return res.status(400).json({ ok: false, error: "Invalid order status" });
    }

    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: { user: true, store: true, items: { include: { product: true } } },
    });
    if (!order) return res.status(404).json({ ok: false, error: "Order not found" });

    const updatedOrder = await prisma.order.update({
      where: { id: orderId },
      data: {
        status,
        ...(status === "DELIVERED" ? { courier: { update: { currentOrderId: null } } } : {}),
      },
    });

    // Notify clients in tracking room
    try {
      const io = getIo();
      io.to(`order:${orderId}`).emit("order:status", {
        status,
        orderId,
        timestamp: new Date().toISOString(),
      });
    } catch {}

    // When status transitions to DELIVERED:
    // 1. Trigger Stripe Connect multi-sided escrow release
    // 2. Schedule GDPR Article 5(1)(e) telemetry sunset (purges GPS trail in 60 min)
    // 3. Dispatch final tax receipt email
    if (status === "DELIVERED") {
      const settlement = releaseEscrowOnDelivery(orderId);
      triggerGdprTelemetrySunset(orderId, 60 * 60 * 1000); // 60 minutes TTL

      // Dispatch final tax invoice and SMS
      dispatchNotifications({
        event: "DELIVERY_COMPLETED",
        orderId: `MLV-${orderId}`,
        amount: order.totalCents / 100,
        paymentMethod: "Google Pay (Verified Escrow)",
        email: order.user.email,
        phone: order.user.phone || "+358 40 123 4567",
        name: order.user.name,
        address: order.deliveryAddress || "Helsinki, Finland",
        items: order.items.map((i) => ({
          name: i.product.name,
          quantity: i.quantity,
          price: i.unitCents / 100,
        })),
      }).catch(() => {});

      return res.json({
        ok: true,
        order: updatedOrder,
        settlement,
        gdprTelemetryPurgeScheduled: true,
        message: "Delivery marked DELIVERED. Escrow released and GDPR sunset scheduled.",
      });
    }

    res.json({ ok: true, order: updatedOrder });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 5. HIGH-FREQUENCY GPS TELEMETRY INGESTION ──────────────────────────────
router.post("/courier/telemetry", auth, async (req: AuthRequest, res: Response) => {
  try {
    const user = req.user!;
    const courier = await resolveCourierForUser(user.id, user.email, "Malvoya Courier");
    const { latitude, longitude, bearing, speed, accuracy, orderId } = req.body;

    if (latitude === undefined || longitude === undefined) {
      return res.status(400).json({ ok: false, error: "Missing latitude/longitude" });
    }

    const stored = ingestCourierTelemetry({
      courierId: courier.id,
      orderId: orderId ? Number(orderId) : undefined,
      latitude: Number(latitude),
      longitude: Number(longitude),
      bearing: Number(bearing ?? 0),
      speed: Number(speed ?? 0),
      accuracy: Number(accuracy ?? 5.0),
      timestamp: Date.now(),
    });

    res.json({ ok: true, stored });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 6. COURIER ONLINE / OFFLINE TOGGLE ──────────────────────────────────────
router.post("/courier/status", auth, async (req: AuthRequest, res: Response) => {
  try {
    const user = req.user!;
    const courier = await resolveCourierForUser(user.id, user.email, "Malvoya Courier");
    const { isOnline, latitude, longitude } = req.body;

    const updated = await prisma.courier.update({
      where: { id: courier.id },
      data: {
        isActive: Boolean(isOnline),
        ...(latitude !== undefined ? { latitude: Number(latitude) } : {}),
        ...(longitude !== undefined ? { longitude: Number(longitude) } : {}),
      },
    });

    res.json({ ok: true, courier: updated });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 7. ESCROW SETTLEMENT RECEIPT ───────────────────────────────────────────
router.get("/courier/settlement/:orderId", auth, async (req: AuthRequest, res: Response) => {
  try {
    const orderId = req.params.orderId;
    const record = getEscrowRecord(orderId);
    res.json({ ok: true, escrow: record });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 8. DYNAMIC IN-TRANSIT CHAT TRANSLATION ─────────────────────────────────
router.post("/chat/translate", auth, async (req: AuthRequest, res: Response) => {
  try {
    const { text, targetLanguage, orderId, senderRole } = req.body;
    if (!text || !targetLanguage) {
      return res.status(400).json({ ok: false, error: "text and targetLanguage required" });
    }

    const translated = await translateChatMessage({
      text,
      targetLanguage,
      orderId: orderId ? Number(orderId) : undefined,
      senderRole: senderRole || "COURIER",
    });

    res.json({ ok: true, ...translated });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ─── 9. VIRTUAL PHONE PROXY CALL BRIDGE ─────────────────────────────────────
router.get("/courier/proxy-call/:orderId", auth, async (req: AuthRequest, res: Response) => {
  try {
    const orderId = Number(req.params.orderId);
    const bridge = createMaskedPhoneBridge(orderId, "COURIER");
    res.json({ ok: true, bridge });
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

export default router;
