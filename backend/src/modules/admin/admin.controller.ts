import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";

// ─── Overview Stats ────────────────────────────────────────────────────────────
export async function getStats(_req: Request, res: Response) {
  const [users, stores, couriers, orders, revenue] = await Promise.all([
    prisma.user.count({ where: { role: "CUSTOMER" } }),
    prisma.store.count(),
    prisma.user.count({ where: { role: "COURIER" } }),
    prisma.order.count(),
    prisma.order.aggregate({
      where: { paymentStatus: "SUCCEEDED" },
      _sum: { totalCents: true },
    }),
  ]);

  const pendingVendors  = await prisma.store.count({ where: { isVerified: false } });
  const activeOrders    = await prisma.order.count({
    where: { status: { in: ["PENDING", "CONFIRMED", "PROCESSING", "SHIPPED"] } },
  });

  res.json({
    ok: true,
    stats: {
      customers:       users,
      vendors:         stores,
      couriers,
      totalOrders:     orders,
      activeOrders,
      pendingApprovals: pendingVendors,
      revenueCents:    revenue._sum.totalCents ?? 0,
    },
  });
}

// ─── Users ────────────────────────────────────────────────────────────────────
export async function getUsers(_req: Request, res: Response) {
  const users = await prisma.user.findMany({
    select: { id: true, name: true, email: true, role: true, phone: true, createdAt: true },
    orderBy: { createdAt: "desc" },
  });
  res.json({ ok: true, users });
}

export async function banUser(req: Request, res: Response) {
  const id = Number(req.params.id);
  await prisma.user.delete({ where: { id } });
  res.json({ ok: true, message: "User removed" });
}

// ─── Vendors (Stores) ─────────────────────────────────────────────────────────
export async function getVendors(_req: Request, res: Response) {
  const stores = await prisma.store.findMany({
    include: {
      owner: { select: { name: true, email: true } },
      _count: { select: { products: true, orders: true } },
    },
    orderBy: { createdAt: "desc" },
  });
  res.json({ ok: true, stores });
}

export async function approveVendor(req: Request, res: Response) {
  const id = Number(req.params.id);
  const store = await prisma.store.update({
    where: { id },
    data: { isVerified: true },
  });
  res.json({ ok: true, store });
}

export async function rejectVendor(req: Request, res: Response) {
  const id = Number(req.params.id);
  await prisma.store.delete({ where: { id } });
  res.json({ ok: true, message: "Store rejected and removed" });
}

// ─── Orders ───────────────────────────────────────────────────────────────────
export async function getOrders(_req: Request, res: Response) {
  const orders = await prisma.order.findMany({
    include: {
      user:  { select: { name: true, email: true } },
      store: { select: { name: true } },
      items: { include: { product: { select: { name: true } } } },
    },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  res.json({ ok: true, orders });
}
