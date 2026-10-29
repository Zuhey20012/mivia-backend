import { Router, Response } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";
import { auth, optionalAuth, requireRole, AuthRequest } from "../../middleware/auth";
import { rateLimitStore } from "../../middleware/rateLimiter";
import { positiveId, sendError } from "../../lib/errors";
import { liveConfigured } from "../../lib/livekit";
import { requireAgreement } from "../legal/agreements";
import { REPORT_REASONS } from "../drops/drops.service";
import * as live from "./live.service";

/**
 * Live shopping (since 2.15.0). Video goes through LiveKit; chat, hearts, pins and the end of a live go through the
 * socket (lib/socket.ts, room live:<id>). See live.service.ts.
 */
const router = Router();

const tooMany = { ok: false, error: "Too many requests, please try again later." };
/** Viewer tokens, per client address (guests may watch). */
const joinLimiter = rateLimit({ windowMs: 15 * 60_000, max: 120, standardHeaders: true, legacyHeaders: false, message: tooMany, ...rateLimitStore("live-join") });
/** Reports, per client address. */
const reportLimiter = rateLimit({ windowMs: 60 * 60_000, max: 10, standardHeaders: true, legacyHeaders: false, message: tooMany, ...rateLimitStore("live-report") });

const id = (req: AuthRequest) => positiveId(req.params.id)!;

function location(req: AuthRequest) {
  const lat = req.query.lat !== undefined ? Number(req.query.lat) : null;
  const lng = req.query.lng !== undefined ? Number(req.query.lng) : null;
  const ok = lat !== null && lng !== null && Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  return ok ? { lat, lng } : { lat: null, lng: null };
}

const startSchema = z.object({
  title: z.string().min(3).max(200),
  productIds: z.array(z.number().int().positive()).min(1).max(live.MAX_PRODUCTS),
});

// Going live counts as offering products for sale: the seller terms in force must be accepted (428)
router.post("/live", auth, requireRole("VENDOR"), requireAgreement(), async (req: AuthRequest, res: Response) => {
  const body = startSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: `Give a title (3–100 characters) and choose 1–${live.MAX_PRODUCTS} products`, errors: body.error.flatten() });
  try {
    res.status(201).json({ ok: true, ...(await live.startLive(req.user!, body.data)) });
  } catch (e) { sendError(res, e); }
});

router.get("/live", optionalAuth, async (req: AuthRequest, res: Response) => {
  const { lat, lng } = location(req);
  try {
    res.json({ ok: true, enabled: liveConfigured(), lives: await live.listLive(lat, lng) });
  } catch (e) { sendError(res, e); }
});

router.get("/live/:id(\\d+)", optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, live: await live.getLive(id(req), req.user) });
  } catch (e) { sendError(res, e); }
});

router.post("/live/:id(\\d+)/heartbeat", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  try {
    await live.heartbeat(id(req), req.user!);
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

// A new publisher token for the store's own live (reconnecting after the app was closed or the network changed)
router.post("/live/:id(\\d+)/publish", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, publish: await live.publishToken(id(req), req.user!) });
  } catch (e) { sendError(res, e); }
});

const endSchema = z.object({ reason: z.string().max(500).optional() });

router.post("/live/:id(\\d+)/end", auth, requireRole("VENDOR", "ADMIN"), async (req: AuthRequest, res: Response) => {
  const body = endSchema.safeParse(req.body ?? {});
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    if (req.user!.role === "ADMIN") {
      const r = await live.adminEnd(id(req), req.user!.id, body.data.reason ?? "");
      return res.json({ ok: true, live: r.live });
    }
    res.json({ ok: true, live: await live.endByOwner(id(req), req.user!) });
  } catch (e) { sendError(res, e); }
});

const pinSchema = z.object({ productId: z.number().int().positive().nullable() });

router.post("/live/:id(\\d+)/pin", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  const body = pinSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Choose a product to pin, or null to unpin" });
  try {
    res.json({ ok: true, ...(await live.pin(id(req), req.user!, body.data.productId)) });
  } catch (e) { sendError(res, e); }
});

router.post("/live/:id(\\d+)/join", joinLimiter, optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, watch: await live.join(id(req), req.user) });
  } catch (e) { sendError(res, e); }
});

router.get("/live/:id(\\d+)/messages", optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, messages: await live.recentMessages(id(req), req.user) });
  } catch (e) { sendError(res, e); }
});

const reportSchema = z.object({
  reason: z.enum(REPORT_REASONS),
  details: z.string().max(1000).optional(),
});

router.post("/live/:id(\\d+)/report", reportLimiter, optionalAuth, async (req: AuthRequest, res: Response) => {
  const body = reportSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Choose a reason" });
  try {
    res.json({ ok: true, ...(await live.report(id(req), req.user?.id ?? null, body.data.reason, body.data.details)) });
  } catch (e) { sendError(res, e); }
});

router.get("/stores/my/live", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await live.myLives(req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

// ─── Admin (mounted before /admin, so these have their own checks) ──────────

const admin = [auth, requireRole("ADMIN")] as const;

router.get("/admin/live", ...admin, async (_req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await live.adminList()) });
  } catch (e) { sendError(res, e); }
});

router.post("/admin/live/:id(\\d+)/end", ...admin, async (req: AuthRequest, res: Response) => {
  const body = z.object({ reason: z.string().max(500) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Give the store a clear reason (at least 10 characters)" });
  try {
    res.json({ ok: true, ...(await live.adminEnd(id(req), req.user!.id, body.data.reason)) });
  } catch (e) { sendError(res, e); }
});

router.get("/admin/live/:id(\\d+)/messages", ...admin, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await live.adminMessages(id(req))) });
  } catch (e) { sendError(res, e); }
});

router.post("/admin/live/reports/:id(\\d+)", ...admin, async (req: AuthRequest, res: Response) => {
  const body = z.object({ status: z.enum(["ACTIONED", "DISMISSED"]) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid status" });
  try {
    res.json({ ok: true, report: await live.resolveReport(id(req), req.user!.id, body.data.status) });
  } catch (e) { sendError(res, e); }
});

export default router;
