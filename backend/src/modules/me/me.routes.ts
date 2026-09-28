import { Router, Response } from "express";
import { z } from "zod";
import { auth, AuthRequest } from "../../middleware/auth";
import { sendError, positiveId, ApiError } from "../../lib/errors";
import { prisma } from "../../lib/prisma";
import { priceInfoFor, presentProduct } from "../products/pricing";
import { getOrderRelation } from "../orders/access";

const router = Router();

// ─── Favourites (wishlist) ──────────────────────────────────────────────────

router.get("/me/favorites", auth, async (req: AuthRequest, res: Response) => {
  try {
    const favs = await prisma.favorite.findMany({
      where: { userId: req.user!.id, product: { store: { isVerified: true } } },
      include: {
        product: {
          include: {
            variants: { orderBy: { id: "asc" } },
            store: { select: { id: true, name: true, logoUrl: true, sellerType: true, rating: true } },
          },
        },
      },
      orderBy: { createdAt: "desc" },
      take: 200,
    });
    const info = await priceInfoFor(favs.map((f) => f.product));
    res.json({ ok: true, products: favs.map((f) => ({ ...presentProduct(f.product, info.get(f.product.id)), isFavorite: true })) });
  } catch (e) { sendError(res, e); }
});

router.put("/me/favorites/:productId(\\d+)", auth, async (req: AuthRequest, res: Response) => {
  const productId = Number(req.params.productId);
  try {
    const product = await prisma.product.findFirst({ where: { id: productId, store: { isVerified: true } }, select: { id: true } });
    if (!product) throw new ApiError("Product not found", 404);
    await prisma.favorite.upsert({
      where: { userId_productId: { userId: req.user!.id, productId } },
      create: { userId: req.user!.id, productId },
      update: {},
    });
    res.json({ ok: true, isFavorite: true });
  } catch (e) { sendError(res, e); }
});

router.delete("/me/favorites/:productId(\\d+)", auth, async (req: AuthRequest, res: Response) => {
  try {
    await prisma.favorite.deleteMany({ where: { userId: req.user!.id, productId: Number(req.params.productId) } });
    res.json({ ok: true, isFavorite: false });
  } catch (e) { sendError(res, e); }
});

// ─── Push devices ───────────────────────────────────────────────────────────

const deviceSchema = z.object({
  token: z.string().min(20).max(4096),
  platform: z.enum(["android", "ios"]),
});

router.post("/me/devices", auth, async (req: AuthRequest, res: Response) => {
  const body = deviceSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid device" });
  try {
    // A phone signs into one account at a time: the token moves to whoever is signed in now
    await prisma.deviceToken.upsert({
      where: { token: body.data.token },
      create: { token: body.data.token, platform: body.data.platform, userId: req.user!.id },
      update: { userId: req.user!.id, platform: body.data.platform },
    });
    const max = await prisma.deviceToken.findMany({ where: { userId: req.user!.id }, orderBy: { updatedAt: "desc" }, skip: 10, select: { token: true } });
    if (max.length) await prisma.deviceToken.deleteMany({ where: { token: { in: max.map((d) => d.token) } } });
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

router.delete("/me/devices", auth, async (req: AuthRequest, res: Response) => {
  const token = typeof req.body?.token === "string" ? req.body.token : "";
  try {
    await prisma.deviceToken.deleteMany({ where: { token, userId: req.user!.id } });
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

// ─── Verified reviews ───────────────────────────────────────────────────────

const REVIEW_WINDOW_DAYS = 30;

const reviewSchema = z.object({
  storeRating: z.number().int().min(1).max(5),
  courierRating: z.number().int().min(1).max(5).optional(),
  comment: z.string().trim().max(1000).optional(),
});

async function refreshRatings(tx: typeof prisma | any, storeId: number, courierId: number | null) {
  const s = await tx.review.aggregate({ where: { storeId, isHidden: false }, _avg: { storeRating: true }, _count: { _all: true } });
  await tx.store.update({ where: { id: storeId }, data: { rating: Math.round((s._avg.storeRating ?? 0) * 10) / 10, totalReviews: s._count._all } });
  if (courierId) {
    const c = await tx.review.aggregate({ where: { courierId, courierRating: { not: null } }, _avg: { courierRating: true }, _count: { courierRating: true } });
    await tx.courier.update({ where: { id: courierId }, data: { rating: Math.round((c._avg.courierRating ?? 0) * 10) / 10, totalRatings: c._count.courierRating } });
  }
}

router.post("/orders/:id(\\d+)/review", auth, async (req: AuthRequest, res: Response) => {
  const body = reviewSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, errors: body.error.flatten() });
  const orderId = Number(req.params.id);
  try {
    const order = await prisma.order.findUnique({ where: { id: orderId }, select: { userId: true, storeId: true, courierId: true, status: true, deliveredAt: true } });
    if (!order || order.userId !== req.user!.id) throw new ApiError("Order not found", 404);
    if (order.status !== "DELIVERED" || !order.deliveredAt) throw new ApiError("You can review an order once it has been delivered", 409);
    if (Date.now() - order.deliveredAt.getTime() > REVIEW_WINDOW_DAYS * 86_400_000) throw new ApiError("Reviews can be left within 30 days of delivery", 409);

    const review = await prisma.$transaction(async (tx) => {
      const created = await tx.review.create({
        data: {
          orderId, userId: req.user!.id, storeId: order.storeId, courierId: order.courierId,
          storeRating: body.data.storeRating,
          courierRating: order.courierId ? body.data.courierRating ?? null : null,
          comment: body.data.comment || null,
        },
      });
      await refreshRatings(tx, order.storeId, order.courierId);
      return created;
    });
    res.status(201).json({ ok: true, review });
  } catch (e: any) {
    if (e?.code === "P2002") return res.status(409).json({ ok: false, error: "You have already reviewed this order" });
    sendError(res, e);
  }
});

router.get("/orders/:id(\\d+)/review", auth, async (req: AuthRequest, res: Response) => {
  const orderId = Number(req.params.id);
  try {
    if (!(await getOrderRelation(orderId, req.user!))) throw new ApiError("Order not found", 404);
    const review = await prisma.review.findUnique({ where: { orderId }, select: { storeRating: true, courierRating: true, comment: true, createdAt: true } });
    res.json({ ok: true, review });
  } catch (e) { sendError(res, e); }
});

/** Public store reviews. Every review comes from a delivered order, which the app says. */
router.get("/stores/:id(\\d+)/reviews", async (req: AuthRequest, res: Response) => {
  const storeId = positiveId(req.params.id)!;
  const page = Math.max(1, Math.min(200, Number(req.query.page) || 1));
  try {
    const where = { storeId, isHidden: false, store: { isVerified: true } };
    const [rows, total] = await Promise.all([
      prisma.review.findMany({
        where, orderBy: { createdAt: "desc" }, skip: (page - 1) * 20, take: 20,
        select: { id: true, storeRating: true, comment: true, createdAt: true, user: { select: { name: true, deletedAt: true } } },
      }),
      prisma.review.count({ where }),
    ]);
    const reviews = rows.map((r) => ({
      id: r.id,
      rating: r.storeRating,
      comment: r.comment,
      createdAt: r.createdAt,
      verifiedPurchase: true,
      // First name and initial only
      author: r.user.deletedAt ? "Former customer" : shortName(r.user.name),
    }));
    res.json({ ok: true, reviews, total, page });
  } catch (e) { sendError(res, e); }
});

function shortName(name: string) {
  const [first, ...rest] = name.trim().split(/\s+/);
  const initial = rest.length ? ` ${rest[rest.length - 1][0].toUpperCase()}.` : "";
  return `${first}${initial}`;
}

export default router;
