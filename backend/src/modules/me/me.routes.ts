import { Router, Response } from "express";
import { z } from "zod";
import { auth, optionalAuth, forgetSessionState, AuthRequest } from "../../middleware/auth";
import { blockedIdsFor } from "./safety";
import { hasPassword } from "../auth/session";
import { sendError, positiveId, ApiError } from "../../lib/errors";
import { prisma } from "../../lib/prisma";
import { priceInfoFor, presentProduct, productInclude } from "../products/pricing";
import { getOrderRelation } from "../orders/access";
import { agreementRoutes } from "../legal/agreements";

const router = Router();

// ─── Profile ────────────────────────────────────────────────────────────────

const profileSchema = z.object({ name: z.string().trim().min(1).max(80) });

/** Only the display name is editable here; email and phone change only through a verified sign-in. */
router.patch("/me/profile", auth, async (req: AuthRequest, res: Response) => {
  const body = profileSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Enter a name between 1 and 80 characters" });
  try {
    const user = await prisma.user.update({
      where: { id: req.user!.id },
      data: { name: body.data.name },
      select: { id: true, name: true, email: true, phone: true, role: true },
    });
    res.json({ ok: true, user });
  } catch (e) { sendError(res, e); }
});

/**
 * Account settings: the language of push notifications and emails ("fi" | "en"; the apps call this when the
 * user changes language) and, optionally, the display name.
 */
const meSchema = z.object({
  locale: z.enum(["fi", "en"]).optional(),
  name: z.string().trim().min(1).max(80).optional(),
  // Optional emails (launch alerts, referral and promo messages; 2.16.0). Service emails cannot be switched off.
  emailMarketing: z.boolean().optional(),
}).strict().refine((d) => d.locale !== undefined || d.name !== undefined || d.emailMarketing !== undefined, { message: "Nothing to change" });

/** The signed-in account, as in the session payload plus phone and language. */
router.get("/me", auth, async (req: AuthRequest, res: Response) => {
  try {
    const u = await prisma.user.findUnique({
      where: { id: req.user!.id },
      select: {
        id: true, name: true, email: true, phone: true, role: true, locale: true, googleSub: true, passwordHash: true, termsAcceptedAt: true, termsVersion: true,
        ageConfirmedAt: true, emailMarketingOptOutAt: true,
      },
    });
    if (!u) throw new ApiError("Account not found", 404);
    const { googleSub, passwordHash, emailMarketingOptOutAt, ...user } = u;
    res.json({
      ok: true,
      user: {
        ...user, googleLinked: !!googleSub, hasPassword: hasPassword(passwordHash),
        ageConfirmed: !!user.ageConfirmedAt, emailMarketing: !emailMarketingOptOutAt,
      },
    });
  } catch (e) { sendError(res, e); }
});

router.patch("/me", auth, async (req: AuthRequest, res: Response) => {
  const body = meSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Send locale (fi or en) and/or a name of 1–80 characters" });
  try {
    const { emailMarketing, ...rest } = body.data;
    const u = await prisma.user.update({
      where: { id: req.user!.id },
      data: {
        ...rest,
        ...(emailMarketing === undefined ? {} : { emailMarketingOptOutAt: emailMarketing ? null : new Date() }),
      },
      select: { id: true, name: true, email: true, phone: true, role: true, locale: true, emailMarketingOptOutAt: true },
    });
    forgetSessionState(req.user!.id); // the next request reads the new language
    const { emailMarketingOptOutAt, ...user } = u;
    res.json({ ok: true, user: { ...user, emailMarketing: !emailMarketingOptOutAt } });
  } catch (e) { sendError(res, e); }
});

// ─── Favourites (wishlist) ──────────────────────────────────────────────────

router.get("/me/favorites", auth, async (req: AuthRequest, res: Response) => {
  try {
    const favs = await prisma.favorite.findMany({
      where: { userId: req.user!.id, product: { deletedAt: null, store: { isVerified: true } } },
      include: {
        product: {
          include: {
            ...productInclude,
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
    const product = await prisma.product.findFirst({ where: { id: productId, deletedAt: null, store: { isVerified: true } }, select: { id: true } });
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

/**
 * Public store reviews. Every review comes from a delivered order, which the app says. Reviews by users the
 * signed-in viewer blocked are left out for that viewer; authorId lets the app offer "Report" and "Block user".
 */
router.get("/stores/:id(\\d+)/reviews", optionalAuth, async (req: AuthRequest, res: Response) => {
  const storeId = positiveId(req.params.id)!;
  const page = Math.max(1, Math.min(200, Number(req.query.page) || 1));
  try {
    const blocked = await blockedIdsFor(req.user?.id);
    const where = { storeId, isHidden: false, store: { isVerified: true }, ...(blocked.length ? { userId: { notIn: blocked } } : {}) };
    const [rows, total] = await Promise.all([
      prisma.review.findMany({
        where, orderBy: { createdAt: "desc" }, skip: (page - 1) * 20, take: 20,
        select: { id: true, storeRating: true, comment: true, createdAt: true, userId: true, user: { select: { name: true, deletedAt: true } } },
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
      authorId: r.user.deletedAt ? null : r.userId,
      mine: req.user?.id === r.userId,
    }));
    res.json({ ok: true, reviews, total, page });
  } catch (e) { sendError(res, e); }
});

function shortName(name: string) {
  const [first, ...rest] = name.trim().split(/\s+/);
  const initial = rest.length ? ` ${rest[rest.length - 1][0].toUpperCase()}.` : "";
  return `${first}${initial}`;
}

// Agreements (2.11): GET /me/agreements, POST /me/agreements/accept, copies and their signed links
router.use(agreementRoutes);

export default router;
