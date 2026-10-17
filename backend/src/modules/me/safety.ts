import { Router, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";

/**
 * User-generated content safety (Google Play UGC policy, DSA notice-and-action):
 *  - blocking: a blocked user's drop comments and reviews are hidden for the blocker (nobody else is affected);
 *  - reporting reviews: admins see reported reviews and hide them or keep them.
 */

const MAX_BLOCKS = 1000;

/** Ids of the users this viewer blocked (empty for anonymous viewers). */
export async function blockedIdsFor(viewerId?: number): Promise<number[]> {
  if (!viewerId) return [];
  const rows = await prisma.userBlock.findMany({ where: { blockerId: viewerId }, select: { blockedId: true }, take: MAX_BLOCKS });
  return rows.map((r) => r.blockedId);
}

const firstName = (name: string) => name.trim().split(/\s+/)[0] || "User";

export async function listBlocks(userId: number) {
  const rows = await prisma.userBlock.findMany({
    where: { blockerId: userId },
    select: { blockedId: true, createdAt: true, blocked: { select: { name: true, deletedAt: true } } },
    orderBy: { createdAt: "desc" },
    take: MAX_BLOCKS,
  });
  return rows.map((r) => ({ userId: r.blockedId, name: r.blocked.deletedAt ? "Deleted user" : firstName(r.blocked.name), createdAt: r.createdAt }));
}

export async function block(userId: number, targetId: number) {
  if (targetId === userId) throw new ApiError("You cannot block yourself", 400);
  const target = await prisma.user.findUnique({ where: { id: targetId }, select: { id: true } });
  if (!target) throw new ApiError("User not found", 404);
  const count = await prisma.userBlock.count({ where: { blockerId: userId } });
  if (count >= MAX_BLOCKS) throw new ApiError(`You can block up to ${MAX_BLOCKS} users`, 409);
  await prisma.userBlock.upsert({
    where: { blockerId_blockedId: { blockerId: userId, blockedId: targetId } },
    create: { blockerId: userId, blockedId: targetId },
    update: {},
  });
  return { blocked: true, userId: targetId };
}

export async function unblock(userId: number, targetId: number) {
  await prisma.userBlock.deleteMany({ where: { blockerId: userId, blockedId: targetId } });
  return { blocked: false, userId: targetId };
}

// ─── Review reports ─────────────────────────────────────────────────────────

export async function reportReview(reviewId: number, reporterId: number, reason: string) {
  const review = await prisma.review.findUnique({ where: { id: reviewId }, select: { id: true, userId: true, isHidden: true } });
  if (!review || review.isHidden) throw new ApiError("Review not found", 404);
  if (review.userId === reporterId) throw new ApiError("You cannot report your own review", 400);
  await prisma.reviewReport.upsert({
    where: { reviewId_reporterId: { reviewId, reporterId } },
    create: { reviewId, reporterId, reason },
    // Reporting again after an admin kept the review opens it for review again
    update: { reason, resolvedAt: null, resolution: null },
  });
  return { reported: true };
}

/** Reviews with reports nobody has decided on yet, most reported first. */
export async function reportedReviews() {
  const rows = await prisma.review.findMany({
    where: { reports: { some: { resolvedAt: null } } },
    select: {
      id: true, orderId: true, storeRating: true, comment: true, isHidden: true, createdAt: true,
      store: { select: { id: true, name: true } }, user: { select: { id: true, name: true } },
      reports: { where: { resolvedAt: null }, select: { reason: true, createdAt: true }, orderBy: { createdAt: "desc" }, take: 20 },
      _count: { select: { reports: { where: { resolvedAt: null } } } },
    },
    take: 100,
  });
  return rows
    .map(({ _count, ...r }) => ({ ...r, reportCount: _count.reports }))
    .sort((a, b) => b.reportCount - a.reportCount || b.id - a.id);
}

/** Store rating from the visible reviews (same rule as everywhere else). */
async function refreshStoreRating(storeId: number) {
  const agg = await prisma.review.aggregate({ where: { storeId, isHidden: false }, _avg: { storeRating: true }, _count: { _all: true } });
  await prisma.store.update({ where: { id: storeId }, data: { rating: Math.round((agg._avg.storeRating ?? 0) * 10) / 10, totalReviews: agg._count._all } });
}

/** An admin hides the reported review (rating recalculated) or keeps it; either way its open reports are closed. */
export async function resolveReviewReports(reviewId: number, action: "hide" | "keep") {
  const review = await prisma.review.findUnique({ where: { id: reviewId }, select: { id: true, storeId: true } });
  if (!review) throw new ApiError("Review not found", 404);
  await prisma.$transaction([
    ...(action === "hide" ? [prisma.review.update({ where: { id: reviewId }, data: { isHidden: true } })] : []),
    prisma.reviewReport.updateMany({ where: { reviewId, resolvedAt: null }, data: { resolvedAt: new Date(), resolution: action === "hide" ? "HIDDEN" : "KEPT" } }),
  ]);
  if (action === "hide") await refreshStoreRating(review.storeId);
  return prisma.review.findUnique({ where: { id: reviewId }, select: { id: true, isHidden: true } });
}

// ─── Routes ─────────────────────────────────────────────────────────────────

export const safetyRoutes = Router();

safetyRoutes.get("/me/blocks", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, blocks: await listBlocks(req.user!.id) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.post("/me/blocks", auth, async (req: AuthRequest, res: Response) => {
  const body = z.object({ userId: z.number().int().positive() }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Say which user to block" });
  try {
    res.json({ ok: true, ...(await block(req.user!.id, body.data.userId)) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.delete("/me/blocks/:userId(\\d+)", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await unblock(req.user!.id, positiveId(req.params.userId)!)) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.post("/reviews/:id(\\d+)/report", auth, async (req: AuthRequest, res: Response) => {
  const body = z.object({ reason: z.string().trim().min(2).max(300) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Choose or write a reason" });
  try {
    res.json({ ok: true, ...(await reportReview(positiveId(req.params.id)!, req.user!.id, body.data.reason)) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.get("/admin/reviews/reported", auth, requireRole("ADMIN"), async (_req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, reviews: await reportedReviews() });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.post("/admin/reviews/:id(\\d+)/resolve", auth, requireRole("ADMIN"), async (req: AuthRequest, res: Response) => {
  const body = z.object({ action: z.enum(["hide", "keep"]) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Action must be hide or keep" });
  try {
    res.json({ ok: true, review: await resolveReviewReports(positiveId(req.params.id)!, body.data.action) });
  } catch (e) { sendError(res, e); }
});
