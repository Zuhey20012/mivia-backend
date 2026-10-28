import { Router, Response } from "express";
import { z } from "zod";
import { auth, optionalAuth, AuthRequest } from "../../middleware/auth";
import { positiveId, sendError } from "../../lib/errors";
import * as sounds from "./sounds.service";

/**
 * Sound library (since 2.14.0).
 *  - Public (mounted under /api/v1): GET /sounds (signed in, active sounds, search), GET /sounds/:id and
 *    GET /sounds/:id/drops (sound page: the drops that use it).
 *  - Admin (`adminSoundRoutes`, mounted inside the /admin router, ADMIN session): list, add (licence required), edit.
 */
const router = Router();

const listQuery = z.object({
  q: z.string().max(100).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
  before: z.coerce.number().int().positive().optional(),
});

router.get("/sounds", auth, async (req: AuthRequest, res: Response) => {
  const q = listQuery.safeParse(req.query);
  if (!q.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await sounds.listActive(q.data)) });
  } catch (e) { sendError(res, e); }
});

router.get("/sounds/:id(\\d+)", async (req, res: Response) => {
  try {
    res.json({ ok: true, sound: await sounds.getSound(Number(req.params.id)) });
  } catch (e) { sendError(res, e); }
});

const dropsQuery = z.object({
  cursor: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(30).default(18),
});

router.get("/sounds/:id(\\d+)/drops", optionalAuth, async (req: AuthRequest, res: Response) => {
  const q = dropsQuery.safeParse(req.query);
  if (!q.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await sounds.soundDrops(Number(req.params.id), q.data, req.user)) });
  } catch (e) { sendError(res, e); }
});

export default router;

// ─── Admin ──────────────────────────────────────────────────────────────────

export const adminSoundRoutes = Router();

const httpsUrl = z.string().trim().max(500).url().refine((u) => u.startsWith("https://"), { message: "Use an https:// link" });
const uploadProof = z.object({
  publicId: z.string().min(5).max(200),
  version: z.union([z.string().max(20), z.number().int()]),
  signature: z.string().length(40),
});

const createSchema = z.object({
  title: z.string().trim().min(1).max(100),
  artist: z.string().trim().max(100).nullable().optional(),
  // What licence Malvoya holds and from whom (e.g. "Commercial licence, Epidemic Sound, order 1234")
  licence: z.string().trim().min(5, "Describe the licence (at least 5 characters)").max(300),
  licenceUrl: httpsUrl.nullable().optional(),
  // Required: the admin confirms Malvoya holds a licence for commercial use of this track
  rightsConfirmed: z.literal(true, { errorMap: () => ({ message: "Confirm that Malvoya holds a licence for commercial use of this track" }) }),
  upload: uploadProof,
});

adminSoundRoutes.get("/sounds", async (_req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, sounds: await sounds.adminList() });
  } catch (e) { sendError(res, e); }
});

adminSoundRoutes.post("/sounds", async (req: AuthRequest, res: Response) => {
  const body = createSchema.safeParse(req.body);
  if (!body.success) {
    const first = body.error.issues[0];
    return res.status(400).json({ ok: false, error: first?.message || "Invalid request", errors: body.error.flatten() });
  }
  try {
    res.status(201).json({ ok: true, sound: await sounds.adminCreate(req.user!, body.data) });
  } catch (e) { sendError(res, e); }
});

const patchSchema = z.object({
  title: z.string().trim().min(1).max(100).optional(),
  // null clears the field
  artist: z.string().trim().max(100).nullable().optional(),
  licence: z.string().trim().min(5, "Describe the licence (at least 5 characters)").max(300).optional(),
  licenceUrl: httpsUrl.nullable().optional(),
  active: z.boolean().optional(),
}).refine((d) => Object.keys(d).length > 0, { message: "Nothing to change" });

adminSoundRoutes.patch("/sounds/:id", async (req: AuthRequest, res: Response) => {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Sound not found" });
  const body = patchSchema.safeParse(req.body);
  if (!body.success) {
    const first = body.error.issues[0];
    return res.status(400).json({ ok: false, error: first?.message || "Invalid request", errors: body.error.flatten() });
  }
  try {
    res.json({ ok: true, sound: await sounds.adminUpdate(req.user!.id, id, body.data) });
  } catch (e) { sendError(res, e); }
});
