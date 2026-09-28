import { Router, Response } from "express";
import { z } from "zod";
import { AuthRequest } from "../../middleware/auth";
import { sendError, positiveId } from "../../lib/errors";
import { prisma } from "../../lib/prisma";
import * as drops from "../drops/drops.service";
import * as payouts from "../payouts/payouts.service";

/** Mounted under /admin, which already requires an ADMIN session. */
const router = Router();

router.get("/drops", async (req: AuthRequest, res: Response) => {
  const status = typeof req.query.status === "string" ? req.query.status : undefined;
  try {
    res.json({ ok: true, drops: await drops.adminList(status) });
  } catch (e) { sendError(res, e); }
});

const moderateSchema = z.object({ action: z.enum(["remove", "restore"]), reason: z.string().max(500).optional() });

router.patch("/drops/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  const body = moderateSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await drops.moderate(Number(req.params.id), req.user!.id, body.data.action, body.data.reason)) });
  } catch (e) { sendError(res, e); }
});

router.get("/reports", async (req: AuthRequest, res: Response) => {
  const status = typeof req.query.status === "string" ? req.query.status : "OPEN";
  try {
    res.json({ ok: true, reports: await drops.adminReports(status) });
  } catch (e) { sendError(res, e); }
});

router.patch("/reports/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  const status = req.body?.status;
  if (status !== "ACTIONED" && status !== "DISMISSED") return res.status(400).json({ ok: false, error: "Invalid status" });
  try {
    res.json({ ok: true, report: await drops.resolveReport(Number(req.params.id), req.user!.id, status) });
  } catch (e) { sendError(res, e); }
});

router.get("/payouts", async (req: AuthRequest, res: Response) => {
  const status = typeof req.query.status === "string" ? req.query.status : undefined;
  try {
    res.json({ ok: true, payouts: await payouts.adminList(status) });
  } catch (e) { sendError(res, e); }
});

router.post("/payouts/:id(\\d+)/retry", async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, payout: await payouts.retry(Number(req.params.id)) });
  } catch (e) { sendError(res, e); }
});

router.get("/reviews", async (_req: AuthRequest, res: Response) => {
  try {
    const reviews = await prisma.review.findMany({
      orderBy: { createdAt: "desc" },
      take: 200,
      select: {
        id: true, orderId: true, storeRating: true, courierRating: true, comment: true, isHidden: true, createdAt: true,
        store: { select: { id: true, name: true } }, user: { select: { id: true, name: true } },
      },
    });
    res.json({ ok: true, reviews });
  } catch (e) { sendError(res, e); }
});

/** Hiding a review (e.g. unlawful content) also recalculates the store's rating. */
router.patch("/reviews/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  const id = positiveId(req.params.id)!;
  const isHidden = req.body?.isHidden;
  if (typeof isHidden !== "boolean") return res.status(400).json({ ok: false, error: "isHidden must be true or false" });
  try {
    const review = await prisma.review.update({ where: { id }, data: { isHidden } });
    const agg = await prisma.review.aggregate({ where: { storeId: review.storeId, isHidden: false }, _avg: { storeRating: true }, _count: { _all: true } });
    await prisma.store.update({
      where: { id: review.storeId },
      data: { rating: Math.round((agg._avg.storeRating ?? 0) * 10) / 10, totalReviews: agg._count._all },
    });
    res.json({ ok: true, review });
  } catch (e) { sendError(res, e); }
});

export default router;
