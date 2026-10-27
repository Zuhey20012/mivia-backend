import { Request, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { AuthRequest } from "../../middleware/auth";
import { revokeAllSessions } from "../auth/session";
import { notifyLaunchAlertsNear } from "../me/launchAlerts";
import { platformRevenue } from "./revenue";
import { taxInfoComplete, taxRowSelect } from "../sellers/taxInfo";
import { forgetSessionState } from "../../middleware/auth";
import { pushToUser } from "../../lib/push";
import { disconnectUser, leaveCourierRooms } from "../../lib/socket";
import { localeOfUser, t } from "../../lib/i18n";
import { sendApprovalEmail } from "../../services/notificationDeliveryService";
import { businessCheckOf, runBusinessCheck } from "../stores/businessCheck";

/** "You're approved": push and email, sent on the first approval only (never on a repeated click). */
async function tellApproved(userId: number, kind: "store" | "courier") {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
  if (!user) return;
  await pushToUser(userId, kind === "store"
    ? {
        title: t("You're approved", "Sinut on hyväksytty"),
        body: t("Your store is live on Malvoya: you can start selling.", "Kauppasi on nyt Malvoyassa: voit aloittaa myynnin."),
        data: { type: "approval", kind },
      }
    : {
        title: t("You're approved", "Sinut on hyväksytty"),
        body: t("You can start delivering: go online in Malvoya Courier to get offers.", "Voit aloittaa toimitukset: siirry linjoille Malvoya Courierissa saadaksesi tarjouksia."),
        data: { type: "approval", kind },
      });
  await sendApprovalEmail(user.email, kind, await localeOfUser(userId));
}

function idParam(req: Request) {
  const id = Number(req.params.id);
  return Number.isInteger(id) && id > 0 ? id : null;
}

// ─── Overview Stats ────────────────────────────────────────────────────────────

export async function getStats(_req: Request, res: Response) {
  const [customers, stores, couriers, orders, revenue, earned, pendingVendors, pendingCouriers, activeOrders, liveDrops, openReports, failedPayouts, waitlist] = await Promise.all([
    prisma.user.count({ where: { role: "CUSTOMER", isActive: true } }),
    prisma.store.count(),
    prisma.courier.count({ where: { userId: { not: null } } }),
    prisma.order.count(),
    prisma.order.aggregate({ where: { paymentStatus: "SUCCEEDED" }, _sum: { totalCents: true } }),
    // Malvoya's own revenue: paid orders that were not refunded or cancelled
    prisma.order.aggregate({
      where: { paymentStatus: "SUCCEEDED", status: { not: "CANCELLED" } },
      _sum: {
        commissionCents: true, serviceFeeCents: true, smallOrderFeeCents: true, discountCents: true,
        deliveryFeeCents: true, courierFeeCents: true, tipCents: true,
      },
    }),
    prisma.store.count({ where: { isVerified: false } }),
    prisma.courier.count({ where: { isApproved: false, userId: { not: null } } }),
    prisma.order.count({ where: { status: { in: ["PENDING", "CONFIRMED", "PROCESSING", "SHIPPED"] }, paymentStatus: "SUCCEEDED" } }),
    prisma.drop.count({ where: { status: "READY" } }),
    prisma.dropReport.count({ where: { status: "OPEN" } }),
    prisma.payout.count({ where: { status: "FAILED" } }),
    prisma.launchAlert.count({ where: { notifiedAt: null } }),
  ]);

  res.json({
    ok: true,
    stats: {
      customers,
      vendors: stores,
      couriers,
      totalOrders: orders,
      activeOrders,
      pendingApprovals: pendingVendors + pendingCouriers,
      pendingVendors,
      pendingCouriers,
      revenueCents: revenue._sum.totalCents ?? 0,
      ...platformRevenue(earned._sum),
      liveDrops,
      openReports,
      failedPayouts,
      waitlist,
    },
  });
}

// ─── Users ────────────────────────────────────────────────────────────────────
export async function getUsers(_req: Request, res: Response) {
  const users = await prisma.user.findMany({
    where: { deletedAt: null },
    select: { id: true, name: true, email: true, role: true, phone: true, isActive: true, createdAt: true },
    orderBy: { createdAt: "desc" },
    take: 500,
  });
  res.json({ ok: true, users });
}

/** Bans deactivate the account and end its sessions; records are kept for bookkeeping and disputes. */
export async function banUser(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "User not found" });
  const user = await prisma.user.findUnique({ where: { id } });
  if (!user) return res.status(404).json({ ok: false, error: "User not found" });
  if (user.role === "ADMIN") return res.status(400).json({ ok: false, error: "Admins cannot be banned here" });

  await prisma.user.update({ where: { id }, data: { isActive: false } });
  await prisma.courier.updateMany({ where: { userId: id }, data: { isActive: false, isApproved: false } });
  await prisma.store.updateMany({ where: { ownerId: id }, data: { isVerified: false } });
  await revokeAllSessions(id);
  forgetSessionState(id);
  disconnectUser(id); // open app connections end too (no more offers, chat or tracking)
  res.json({ ok: true, message: "User deactivated" });
}

// ─── Vendors (Stores) ─────────────────────────────────────────────────────────
export async function getVendors(req: Request, res: Response) {
  const status = String(req.query.status || "").toUpperCase();
  const stores = await prisma.store.findMany({
    where: status === "PENDING" ? { isVerified: false } : status === "APPROVED" ? { isVerified: true } : {},
    include: {
      owner: { select: { name: true, email: true } },
      _count: { select: { products: true, orders: true } },
      taxInfo: { select: taxRowSelect },
    },
    orderBy: { createdAt: "desc" },
    take: 500,
  });
  // DAC7: whether each store has given its tax data; the data itself is only in the DAC7 report
  // businessCheck: the PRH/YTJ lookup of the Y-tunnus (pre-fills the decision; never approves)
  res.json({ ok: true, stores: stores.map(({ taxInfo, ...s }) => ({ ...s, taxInfoComplete: taxInfoComplete(s, taxInfo), businessCheck: businessCheckOf(s) })) });
}

/** Runs the PRH/YTJ business check again (e.g. after the register was unavailable). */
export async function rerunBusinessCheck(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const store = await prisma.store.findUnique({ where: { id }, select: { sellerType: true, businessId: true } });
  if (!store) return res.status(404).json({ ok: false, error: "Store not found" });
  if (store.sellerType !== "BUSINESS" || !store.businessId) return res.status(409).json({ ok: false, error: "Private sellers have no Y-tunnus to check" });
  try {
    const result = await runBusinessCheck(id);
    if (!result) return res.status(409).json({ ok: false, error: "The store's Y-tunnus is not valid" });
    res.json({ ok: true, businessCheck: { required: true, businessId: result.businessId, verificationStatus: result.status, registeredName: result.registeredName, registeredAt: result.registeredAt, checkedAt: result.checkedAt } });
  } catch {
    res.status(500).json({ ok: false, error: "Something went wrong" });
  }
}

export async function approveVendor(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const before = await prisma.store.findUnique({ where: { id }, select: { isVerified: true } });
  if (!before) return res.status(404).json({ ok: false, error: "Store not found" });
  const store = await prisma.store.update({ where: { id }, data: { isVerified: true } });
  // First time live: tell customers who asked to hear when Malvoya opens near them
  const notified = before.isVerified ? 0 : await notifyLaunchAlertsNear(store).catch(() => 0);
  if (!before.isVerified) tellApproved(store.ownerId, "store").catch(() => {});
  res.json({ ok: true, store, launchAlertsSent: notified, approvalSent: !before.isVerified });
}

// Commission is a fraction of the item subtotal with two decimals (0.12 = 12 %), at most 50 %
const commissionSchema = z.object({
  commissionRate: z.number().min(0).max(0.5).refine((v) => Math.abs(Math.round(v * 100) - v * 100) < 1e-9, {
    message: "Use at most two decimals (0.12 = 12 %)",
  }),
});

/**
 * Per-store commission. Applies to orders placed from now on: every order keeps the commission it was
 * priced with (Order.commissionCents). Each change is written to the admin audit log (who, when, old, new).
 */
export async function setVendorCommission(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const body = commissionSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Commission must be between 0 and 0.5", errors: body.error.flatten() });
  const before = await prisma.store.findUnique({ where: { id }, select: { commissionRate: true } });
  if (!before) return res.status(404).json({ ok: false, error: "Store not found" });
  const rate = Math.round(body.data.commissionRate * 100) / 100;
  const [store, change] = await prisma.$transaction([
    prisma.store.update({ where: { id }, data: { commissionRate: rate }, select: { id: true, name: true, commissionRate: true } }),
    prisma.adminAuditLog.create({
      data: {
        adminId: req.user!.id, action: "store.commission", entity: "Store", entityId: id,
        oldValue: { commissionRate: before.commissionRate }, newValue: { commissionRate: rate },
      },
    }),
  ]);
  res.json({ ok: true, store, change });
}

/** The store's commission changes, newest first. */
export async function vendorCommissionHistory(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const rows = await prisma.adminAuditLog.findMany({
    where: { entity: "Store", entityId: id, action: "store.commission" },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
  const admins = await prisma.user.findMany({ where: { id: { in: [...new Set(rows.map((r) => r.adminId))] } }, select: { id: true, name: true, email: true } });
  const byId = new Map(admins.map((a) => [a.id, a]));
  res.json({ ok: true, history: rows.map((r) => ({ ...r, admin: byId.get(r.adminId) ?? null })) });
}

/** Rejecting hides the store; stores with orders cannot be deleted (bookkeeping). */
export async function rejectVendor(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const store = await prisma.store.findUnique({ where: { id }, include: { _count: { select: { orders: true } } } });
  if (!store) return res.status(404).json({ ok: false, error: "Store not found" });

  if (store._count.orders > 0) {
    await prisma.store.update({ where: { id }, data: { isVerified: false } });
    await prisma.product.updateMany({ where: { storeId: id }, data: { isAvailable: false } });
    return res.json({ ok: true, message: "Store suspended (it has order history, so it is kept)" });
  }
  await prisma.$transaction([
    // No orders means nothing to report under DAC7, so its tax data can go with it
    prisma.storeTaxInfo.deleteMany({ where: { storeId: id } }),
    prisma.productVariant.deleteMany({ where: { product: { storeId: id } } }),
    prisma.product.deleteMany({ where: { storeId: id } }),
    prisma.store.delete({ where: { id } }),
  ]);
  res.json({ ok: true, message: "Store rejected and removed" });
}

// ─── Couriers ─────────────────────────────────────────────────────────────────
export async function getCouriers(req: Request, res: Response) {
  const status = String(req.query.status || "").toUpperCase();
  const couriers = await prisma.courier.findMany({
    where: {
      userId: { not: null },
      ...(status === "PENDING" ? { isApproved: false } : status === "APPROVED" ? { isApproved: true } : {}),
    },
    select: {
      id: true, name: true, phone: true, email: true, isApproved: true, isActive: true, currentOrderId: true, createdAt: true,
      vehicleType: true, locationDisclosureAt: true, payoutsEnabled: true, readyForApprovalAt: true,
      user: { select: { id: true, email: true, isActive: true } },
      _count: { select: { orders: true } },
    },
    orderBy: { createdAt: "desc" },
    take: 500, // bounded like the user and vendor lists
  });
  res.json({ ok: true, couriers });
}

export async function approveCourier(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Courier not found" });
  const before = await prisma.courier.findUnique({ where: { id }, select: { isApproved: true } });
  if (!before) return res.status(404).json({ ok: false, error: "Courier not found" });
  const courier = await prisma.courier.update({ where: { id }, data: { isApproved: true } });
  if (!before.isApproved && courier.userId) tellApproved(courier.userId, "courier").catch(() => {});
  res.json({ ok: true, courier, approvalSent: !before.isApproved && !!courier.userId });
}

export async function suspendCourier(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Courier not found" });
  const courier = await prisma.courier.update({
    where: { id },
    data: { isApproved: false, isActive: false, latitude: null, longitude: null },
  }).catch(() => null);
  if (!courier) return res.status(404).json({ ok: false, error: "Courier not found" });
  if (courier.userId) leaveCourierRooms(courier.userId, courier.id);
  res.json({ ok: true, courier });
}

// ─── Orders ───────────────────────────────────────────────────────────────────
export async function getOrders(_req: Request, res: Response) {
  const orders = await prisma.order.findMany({
    omit: { courierPay: false },
    include: {
      user:  { select: { name: true, email: true } },
      store: { select: { name: true } },
      courier: { select: { id: true, name: true } },
      items: { include: { product: { select: { name: true } } } },
    },
    // scheduledStart/scheduledEnd (delivery window) and deliveryProblemAt/Reason/Note, returnedToStoreAt are columns
    orderBy: { createdAt: "desc" },
    take: 200,
  });
  res.json({ ok: true, orders });
}
