import { Router, Response } from "express";
import { z } from "zod";
import { auth, optionalAuth, requireRole, AuthRequest } from "../../middleware/auth";
import { sendError, positiveId } from "../../lib/errors";
import { escapeHtml } from "../../services/notificationDeliveryService";
import { env } from "../../config/env";
import * as drops from "./drops.service";

const router = Router();

function location(req: AuthRequest) {
  const lat = req.query.lat !== undefined ? Number(req.query.lat) : null;
  const lng = req.query.lng !== undefined ? Number(req.query.lng) : null;
  const ok = lat !== null && lng !== null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  return ok ? { lat, lng } : { lat: null, lng: null };
}

const feedQuery = z.object({
  mode: z.enum(["foryou", "latest"]).default("foryou"),
  cursor: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(20).default(8),
});

router.get("/drops/feed", optionalAuth, async (req: AuthRequest, res: Response) => {
  const q = feedQuery.safeParse(req.query);
  if (!q.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await drops.getFeed({ ...q.data, ...location(req) }, req.user)) });
  } catch (e) { sendError(res, e); }
});

// How the feed is ranked, shown in the app (DSA Art. 27 recommender transparency)
router.get("/drops/ranking", (_req, res) => res.json({ ok: true, ranking: drops.RANKING_EXPLANATION, reportReasons: drops.REPORT_REASONS }));

router.get("/drops/mine", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, drops: await drops.listMine(req.user!.id) });
  } catch (e) { sendError(res, e); }
});

router.get("/stores/:storeId(\\d+)/drops", optionalAuth, async (req: AuthRequest, res: Response) => {
  const q = feedQuery.safeParse(req.query);
  if (!q.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await drops.getFeed({ ...q.data, mode: "latest", storeId: Number(req.params.storeId), ...location(req) }, req.user)) });
  } catch (e) { sendError(res, e); }
});

router.get("/drops/:id(\\d+)", optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, drop: await drops.getDrop(Number(req.params.id), req.user, location(req)) });
  } catch (e) { sendError(res, e); }
});

const createSchema = z.object({
  productId: z.number().int().positive(),
  caption: z.string().max(300).optional(),
  kind: z.enum(["VIDEO", "IMAGE"]),
  upload: z.object({
    publicId: z.string().min(5).max(200),
    version: z.union([z.string().max(20), z.number().int()]),
    signature: z.string().length(40),
  }),
});

router.post("/drops", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  const body = createSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, errors: body.error.flatten() });
  try {
    res.status(201).json({ ok: true, drop: await drops.createDrop(req.user!, body.data) });
  } catch (e) { sendError(res, e); }
});

router.delete("/drops/:id(\\d+)", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  try {
    await drops.deleteMine(req.user!.id, Number(req.params.id));
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

router.post("/drops/:id(\\d+)/like", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await drops.like(Number(req.params.id), req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

router.delete("/drops/:id(\\d+)/like", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await drops.unlike(Number(req.params.id), req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

const viewSchema = z.object({
  installId: z.string().min(8).max(100).optional(),
  watchedSec: z.number().min(0).max(3600).default(0),
  completed: z.boolean().default(false),
});

router.post("/drops/:id(\\d+)/view", optionalAuth, async (req: AuthRequest, res: Response) => {
  const body = viewSchema.safeParse(req.body ?? {});
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await drops.recordView(Number(req.params.id), req.user, { ...body.data, ip: req.ip })) });
  } catch (e) { sendError(res, e); }
});

router.post("/drops/:id(\\d+)/share", optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await drops.share(Number(req.params.id))) });
  } catch (e) { sendError(res, e); }
});

const reportSchema = z.object({
  reason: z.enum(drops.REPORT_REASONS),
  details: z.string().max(1000).optional(),
});

router.post("/drops/:id(\\d+)/report", optionalAuth, async (req: AuthRequest, res: Response) => {
  const body = reportSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Choose a reason" });
  try {
    res.json({ ok: true, ...(await drops.report(Number(req.params.id), req.user?.id ?? null, body.data.reason, body.data.details)) });
  } catch (e) { sendError(res, e); }
});

export default router;

/**
 * Share links (https://…/d/12): a small page with a preview image for chat apps and a button to
 * open or get the app. Mounted outside /api/v1.
 */
export const shareRouter = Router();

shareRouter.get("/d/:id", async (req, res) => {
  const id = positiveId(req.params.id);
  let drop: Awaited<ReturnType<typeof drops.getDrop>> | null = null;
  if (id) drop = await drops.getDrop(id, undefined, { lat: null, lng: null }).catch(() => null);

  const title = drop ? `${drop.product.name} – ${drop.store.name}` : "Malvoya";
  const description = drop?.caption || "Local fashion, delivered fast. Watch drops from stores near you on Malvoya.";
  const image = drop?.media.poster ?? "";
  const price = drop?.product.pricing.priceCents != null ? `${(drop.product.pricing.priceCents / 100).toFixed(2).replace(".", ",")} €` : "";
  const appLink = `malvoya://drops/${id ?? ""}`;

  res.set("Cache-Control", "public, max-age=300");
  // The API's default policy blocks third-party images; this page only needs Cloudinary images and inline styles
  res.set("Content-Security-Policy", "default-src 'none'; img-src https://res.cloudinary.com; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  res.type("html").send(`<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta property="og:type" content="video.other">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
${image ? `<meta property="og:image" content="${escapeHtml(image)}">` : ""}
<meta name="twitter:card" content="summary_large_image">
<meta name="robots" content="noindex">
</head>
<body style="margin:0;font-family:-apple-system,system-ui,sans-serif;background:#17131C;color:#F6F3EE;display:flex;min-height:100vh;align-items:center;justify-content:center">
<main style="max-width:420px;width:100%;padding:24px;text-align:center">
${image ? `<img src="${escapeHtml(image)}" alt="" style="width:100%;border-radius:20px;aspect-ratio:9/16;object-fit:cover;background:#2a2230">` : ""}
<h1 style="font-size:20px;margin:18px 0 4px">${escapeHtml(drop?.product.name ?? "Malvoya")}</h1>
<p style="margin:0 0 4px;color:#cbbfd6">${escapeHtml(drop?.store.name ?? "")}${price ? ` · ${escapeHtml(price)}` : ""}</p>
<p style="margin:0 0 20px;color:#cbbfd6">${escapeHtml(description)}</p>
<a href="${escapeHtml(appLink)}" style="display:block;background:#6D2E8C;color:#fff;text-decoration:none;padding:14px;border-radius:14px;font-weight:600;margin-bottom:10px">Open in Malvoya</a>
<a href="${escapeHtml(env.playStoreUrl)}" style="display:block;color:#F6F3EE;text-decoration:none;padding:12px;border:1px solid #4a3f52;border-radius:14px">Get the app</a>
</main></body></html>`);
});
