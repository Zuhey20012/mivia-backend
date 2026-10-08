import { Router, Response } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";
import { optionalAuth, auth, requireRole, AuthRequest } from "../../middleware/auth";
import { prisma } from "../../lib/prisma";
import { sendError, ApiError } from "../../lib/errors";
import { sendEmail, escapeHtml } from "../../services/notificationDeliveryService";
import { isSyntheticEmail } from "../auth/auth.service";

// Requests are always saved for the admin panel; they are also emailed when a support mailbox is set.
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || "";
const router = Router();

// A person can send a handful of requests an hour; more is spam
const supportLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 8, standardHeaders: true, legacyHeaders: false,
  message: { ok: false, error: "You have sent several requests already. We will reply to them by email." } });

const requestSchema = z.object({
  app: z.enum(["customer", "store", "courier"]),
  topic: z.string().trim().min(2).max(80),
  message: z.string().trim().min(5).max(4000),
  email: z.string().trim().email().optional(), // required when signed out
  orderId: z.number().int().positive().optional(),
});

/** Anyone can contact support; signed-in users are answered at their account email. */
router.post("/support", supportLimiter, optionalAuth, async (req: AuthRequest, res: Response) => {
  const body = requestSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Write a short description of what you need help with" });
  try {
    let email = body.data.email;
    if (req.user) {
      const user = await prisma.user.findUnique({ where: { id: req.user.id }, select: { email: true } });
      // Phone-only accounts have no real email address, so they give one here
      email = !user || isSyntheticEmail(user.email) ? body.data.email : user.email;
    }
    if (!email) throw new ApiError("Give an email address we can reply to");

    const request = await prisma.supportRequest.create({
      data: { userId: req.user?.id ?? null, email, app: body.data.app, topic: body.data.topic, message: body.data.message, orderId: body.data.orderId ?? null },
    });

    const text = `Support request #${request.id} (${body.data.app})\nFrom: ${email}${req.user ? ` (user ${req.user.id})` : ""}\n` +
      `${body.data.orderId ? `Order: #${body.data.orderId}\n` : ""}Topic: ${body.data.topic}\n\n${body.data.message}`;
    if (SUPPORT_EMAIL) sendEmail(SUPPORT_EMAIL, `Malvoya support #${request.id}: ${body.data.topic}`, `<pre style="font-family:inherit;white-space:pre-wrap">${escapeHtml(text)}</pre>`, text).catch(() => {});
    const ack = `We received your message (#${request.id}) and will reply to ${email}.\n\nViestisi (#${request.id}) on vastaanotettu. Vastaamme osoitteeseen ${email}.`;
    sendEmail(email, `Malvoya – we got your message #${request.id}`, `<p>${escapeHtml(ack).replace(/\n/g, "<br>")}</p>`, ack).catch(() => {});

    res.status(201).json({ ok: true, id: request.id, replyTo: email });
  } catch (e) { sendError(res, e); }
});

// ─── Admin ──────────────────────────────────────────────────────────────────

router.get("/admin/support", auth, requireRole("ADMIN"), async (req: AuthRequest, res: Response) => {
  const status = typeof req.query.status === "string" ? req.query.status : "OPEN";
  try {
    const requests = await prisma.supportRequest.findMany({ where: { status: status as any }, orderBy: { createdAt: "asc" }, take: 300 });
    res.json({ ok: true, requests });
  } catch (e) { sendError(res, e); }
});

router.patch("/admin/support/:id(\\d+)", auth, requireRole("ADMIN"), async (req: AuthRequest, res: Response) => {
  const status = req.body?.status;
  if (!["OPEN", "ANSWERED", "CLOSED"].includes(status)) return res.status(400).json({ ok: false, error: "Invalid status" });
  try {
    res.json({ ok: true, request: await prisma.supportRequest.update({ where: { id: Number(req.params.id) }, data: { status } }) });
  } catch (e) { sendError(res, e); }
});

export default router;
