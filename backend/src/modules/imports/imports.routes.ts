import express, { NextFunction, Request, Response, Router } from "express";
import { z } from "zod";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { positiveId, sendError } from "../../lib/errors";
import * as imports from "./imports.service";
import { requireAgreement } from "../legal/agreements";

/**
 * Catalogue import for stores: /products/import/{shopify,woocommerce,csv} start a job (202), GET reads jobs,
 * /products/import/:id/publish makes the job's drafts visible.
 */

export const MAX_CSV_BYTES = 1024 * 1024;

/**
 * Body parser for the CSV route only, mounted in index.ts BEFORE the global 100 kB parser: 1 MB of CSV
 * can grow to ~1.5 MB once escaped as a JSON string. Everything else keeps the 100 kB limit.
 */
export const csvBodyParser = [
  express.json({ limit: "1536kb" }),
  (err: any, _req: Request, res: Response, next: NextFunction) => {
    if (err?.type === "entity.too.large") return res.status(413).json({ ok: false, error: "The CSV file is too large (max 1 MB)." });
    next(err);
  },
];

const rights = z.literal(true, {
  errorMap: () => ({ message: "Confirm that your store may use these photos and texts (rightsConfirmed: true)" }),
});
const shopifySchema = z.object({ shopUrl: z.string().trim().min(3).max(300), rightsConfirmed: rights });
// WooCommerce REST API keys (WooCommerce → Settings → Advanced → REST API, permission "Read"); never stored
const wooSchema = z.object({
  siteUrl: z.string().trim().min(3).max(300),
  consumerKey: z.string().trim().regex(/^ck_[A-Za-z0-9]{20,64}$/, "Paste the consumer key (starts with ck_)"),
  consumerSecret: z.string().trim().regex(/^cs_[A-Za-z0-9]{20,64}$/, "Paste the consumer secret (starts with cs_)"),
  rightsConfirmed: rights,
}).strict();
const csvSchema = z.object({ csv: z.string().min(1), rightsConfirmed: rights });

const router = Router();
const vendor = [auth, requireRole("VENDOR")];

router.post("/products/import/shopify", ...vendor, async (req: AuthRequest, res: Response) => {
  const parsed = shopifySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, error: parsed.error.issues[0]?.message ?? "Invalid request", errors: parsed.error.flatten() });
  try {
    res.status(202).json({ ok: true, job: await imports.startShopifyImport(req.user!.id, parsed.data.shopUrl) });
  } catch (e) { sendError(res, e); }
});

router.post("/products/import/woocommerce", ...vendor, async (req: AuthRequest, res: Response) => {
  const parsed = wooSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, error: parsed.error.issues[0]?.message ?? "Invalid request", errors: parsed.error.flatten() });
  const { siteUrl, consumerKey, consumerSecret } = parsed.data;
  try {
    res.status(202).json({ ok: true, job: await imports.startWooImport(req.user!.id, siteUrl, { consumerKey, consumerSecret }) });
  } catch (e) { sendError(res, e); }
});

router.post("/products/import/csv", ...vendor, async (req: AuthRequest, res: Response) => {
  const parsed = csvSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ ok: false, error: parsed.error.issues[0]?.message ?? "Invalid request", errors: parsed.error.flatten() });
  if (Buffer.byteLength(parsed.data.csv, "utf8") > MAX_CSV_BYTES) {
    return res.status(413).json({ ok: false, error: "The CSV file is too large (max 1 MB)." });
  }
  try {
    res.status(202).json({ ok: true, job: await imports.startCsvImport(req.user!.id, parsed.data.csv) });
  } catch (e) { sendError(res, e); }
});

router.get("/products/import", ...vendor, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, jobs: await imports.listJobs(req.user!.id) });
  } catch (e) { sendError(res, e); }
});

router.get("/products/import/:id(\\d+)", ...vendor, async (req: AuthRequest, res: Response) => {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Import not found" });
  try {
    res.json({ ok: true, job: await imports.getJob(req.user!.id, id) });
  } catch (e) { sendError(res, e); }
});

router.post("/products/import/:id(\\d+)/publish", ...vendor, requireAgreement(), async (req: AuthRequest, res: Response) => {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Import not found" });
  try {
    // { published: n, incomplete: [{ productId, name, missing: [field issues] }] } (drafts that miss required information)
    res.json({ ok: true, ...(await imports.publishJob(req.user!.id, id)) });
  } catch (e) { sendError(res, e); }
});

export default router;
