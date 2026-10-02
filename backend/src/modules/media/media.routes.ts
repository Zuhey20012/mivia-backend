import express, { Router, Response, Request } from "express";
import pino from "pino";
import { z } from "zod";
import { auth, AuthRequest } from "../../middleware/auth";
import { globalLimiter } from "../../middleware/rateLimiter";
import { sendError } from "../../lib/errors";
import { verifyNotification } from "../../lib/cloudinary";
import { MEDIA_KINDS, signUpload, verifyOwnedUpload, describe, MediaKind } from "./media.service";
import { onVideoProcessed } from "../drops/drops.service";
import { onProductVideoProcessed } from "../products/productVideos";

const logger = pino({ name: "media" });
const router = Router();

/**
 * Mounted before the global JSON parser: the Cloudinary webhook signature covers the raw body,
 * so the other routes here parse JSON themselves.
 */
router.post("/media/cloudinary/notify", express.text({ type: "*/*", limit: "256kb" }), async (req: Request, res: Response) => {
  const raw = typeof req.body === "string" ? req.body : "";
  const ok = verifyNotification(raw, String(req.headers["x-cld-timestamp"] ?? ""), String(req.headers["x-cld-signature"] ?? ""));
  if (!ok) return res.status(401).send("Invalid signature");
  try {
    const body = JSON.parse(raw);
    if (body.notification_type === "eager" && typeof body.public_id === "string") {
      const failed = !!body.error || (Array.isArray(body.eager) && body.eager.some((e: any) => e?.status === "failed"));
      // The public id belongs to either a drop or a product video; each handler ignores ids it does not know
      await onVideoProcessed(body.public_id, failed);
      await onProductVideoProcessed(body.public_id, failed);
    }
    res.json({ received: true });
  } catch (err: any) {
    logger.error({ err: err?.message }, "Cloudinary notification failed");
    res.status(500).send("Handler error");
  }
});

const signSchema = z.object({
  kind: z.enum(MEDIA_KINDS as [MediaKind, ...MediaKind[]]),
  orderId: z.number().int().positive().optional(),
});

router.post("/media/sign", express.json({ limit: "10kb" }), globalLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = signSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await signUpload(body.data.kind, req.user!, body.data.orderId)) });
  } catch (e) { sendError(res, e); }
});

const confirmSchema = signSchema.extend({
  publicId: z.string().min(5).max(200),
  version: z.union([z.string().max(20), z.number().int()]),
  signature: z.string().length(40),
});

/** Turns a finished upload into the canonical URLs the app should use. */
router.post("/media/confirm", express.json({ limit: "10kb" }), globalLimiter, auth, async (req: AuthRequest, res: Response) => {
  const body = confirmSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    const { kind, orderId, ...proof } = body.data;
    await verifyOwnedUpload(kind, req.user!, proof, orderId);
    res.json({ ok: true, media: describe(kind, proof.publicId) });
  } catch (e) { sendError(res, e); }
});

export default router;
