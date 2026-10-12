import { Router, Request, Response } from "express";
import { z } from "zod";
import { positiveId, sendError, ApiError } from "../../lib/errors";
import { createPromoCode, listPromoCodes, updatePromoCode } from "./promos.service";

/** Admin-only promo code management. Mounted inside the admin router (auth + ADMIN already applied). */
const router = Router();

const isoDate = z.string().datetime({ offset: true });

const createSchema = z.object({
  code: z.string().trim().min(3).max(32).regex(/^[A-Za-z0-9_-]+$/, "Use letters, numbers, - and _ only"),
  description: z.string().trim().min(3).max(200),
  kind: z.enum(["PERCENT", "AMOUNT"]),
  value: z.number().int().min(1).max(100_000),
  maxDiscountCents: z.number().int().min(1).max(100_000).nullable().optional(),
  minSubtotalCents: z.number().int().min(0).max(1_000_000).optional(),
  firstOrderOnly: z.boolean().optional(),
  maxRedemptions: z.number().int().min(1).max(1_000_000).nullable().optional(),
  perUserLimit: z.number().int().min(1).max(100).optional(),
  startsAt: isoDate.nullable().optional(),
  endsAt: isoDate.nullable().optional(),
  active: z.boolean().optional(),
}).refine((d) => d.kind !== "PERCENT" || d.value <= 100, { message: "A percentage code can give at most 100 %", path: ["value"] });

const updateSchema = z.object({
  active: z.boolean().optional(),
  endsAt: isoDate.nullable().optional(),
  description: z.string().trim().min(3).max(200).optional(),
  maxRedemptions: z.number().int().min(1).max(1_000_000).nullable().optional(),
}).refine((d) => Object.keys(d).length > 0, { message: "Nothing to change" });

router.get("/promo-codes", async (_req: Request, res: Response) => {
  try {
    res.json({ ok: true, promoCodes: await listPromoCodes() });
  } catch (e) { sendError(res, e); }
});

router.post("/promo-codes", async (req: Request, res: Response) => {
  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, error: parsed.error.issues[0]?.message ?? "Invalid promo code", errors: parsed.error.flatten() });
  try {
    res.status(201).json({ ok: true, promoCode: await createPromoCode(parsed.data) });
  } catch (e) { sendError(res, e); }
});

router.patch("/promo-codes/:id", async (req: Request, res: Response) => {
  const id = positiveId(req.params.id);
  const parsed = updateSchema.safeParse(req.body);
  try {
    if (!id) throw new ApiError("Promo code not found", 404);
    if (!parsed.success) return res.status(400).json({ ok: false, error: parsed.error.issues[0]?.message ?? "Invalid change", errors: parsed.error.flatten() });
    res.json({ ok: true, promoCode: await updatePromoCode(id, parsed.data) });
  } catch (e) { sendError(res, e); }
});

export default router;
