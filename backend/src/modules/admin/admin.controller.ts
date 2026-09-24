import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { revokeAllSessions } from "../auth/session";

function idParam(req: Request) {
  const id = Number(req.params.id);
  return Number.isInteger(id) && id > 0 ? id : null;
}

// ─── Overview Stats ────────────────────────────────────────────────────────────
export async function getStats(_req: Request, res: Response) {
  const [customers, stores, couriers, orders, revenue, pendingVendors, pendingCouriers, activeOrders] = await Promise.all([
    prisma.user.count({ where: { role: "CUSTOMER", isActive: true } }),
    prisma.store.count(),
    prisma.courier.count({ where: { userId: { not: null } } }),
    prisma.order.count(),
    prisma.order.aggregate({ where: { paymentStatus: "SUCCEEDED" }, _sum: { totalCents: true, commissionCents: true } }),
    prisma.store.count({ where: { isVerified: false } }),
    prisma.courier.count({ where: { isApproved: false, userId: { not: null } } }),
    prisma.order.count({ where: { status: { in: ["PENDING", "CONFIRMED", "PROCESSING", "SHIPPED"] }, paymentStatus: "SUCCEEDED" } }),
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
      commissionCents: revenue._sum.commissionCents ?? 0,
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
    },
    orderBy: { createdAt: "desc" },
  });
  res.json({ ok: true, stores });
}

export async function approveVendor(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const store = await prisma.store.update({ where: { id }, data: { isVerified: true } }).catch(() => null);
  if (!store) return res.status(404).json({ ok: false, error: "Store not found" });
  res.json({ ok: true, store });
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
      user: { select: { id: true, email: true, isActive: true } },
      _count: { select: { orders: true } },
    },
    orderBy: { createdAt: "desc" },
  });
  res.json({ ok: true, couriers });
}

export async function approveCourier(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Courier not found" });
  const courier = await prisma.courier.update({ where: { id }, data: { isApproved: true } }).catch(() => null);
  if (!courier) return res.status(404).json({ ok: false, error: "Courier not found" });
  res.json({ ok: true, courier });
}

export async function suspendCourier(req: Request, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Courier not found" });
  const courier = await prisma.courier.update({
    where: { id },
    data: { isApproved: false, isActive: false, latitude: null, longitude: null },
  }).catch(() => null);
  if (!courier) return res.status(404).json({ ok: false, error: "Courier not found" });
  res.json({ ok: true, courier });
}

// ─── Orders ───────────────────────────────────────────────────────────────────
export async function getOrders(_req: Request, res: Response) {
  const orders = await prisma.order.findMany({
    include: {
      user:  { select: { name: true, email: true } },
      store: { select: { name: true } },
      courier: { select: { id: true, name: true } },
      items: { include: { product: { select: { name: true } } } },
    },
    orderBy: { createdAt: "desc" },
    take: 200,
  });
  res.json({ ok: true, orders });
}
