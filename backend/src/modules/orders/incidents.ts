import { Router, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { alertAdmins } from "../../lib/adminAlerts";
import { audit } from "../../lib/audit";
import { pushToUser } from "../../lib/push";
import { t } from "../../lib/i18n";
import { getCourierForUser } from "./access";

/**
 * Courier safety (since 2.17.0). The courier app's Help button: call 112 (on the phone itself) or report an incident.
 * A report reaches every admin at once (push + email) and stays in System → attention until an admin resolves it.
 */
const TYPES = ["ACCIDENT", "THREAT", "DAMAGED", "THEFT", "OTHER"] as const;
const TYPE_TEXT: Record<(typeof TYPES)[number], string> = {
  ACCIDENT: "an accident", THREAT: "a threat or violence", DAMAGED: "damaged goods", THEFT: "a theft", OTHER: "a problem",
};

const incidentSchema = z.object({
  type: z.enum(TYPES),
  orderId: z.number().int().positive().optional(),
  note: z.string().trim().max(1000).optional(),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
});

type Row = { id: number; type: string; status: string; note: string | null; orderId: number | null; createdAt: Date; resolutionNote: string | null; resolvedAt: Date | null };
const present = (i: Row) => ({
  id: i.id, type: i.type, status: i.status, note: i.note, orderId: i.orderId, createdAt: i.createdAt, resolutionNote: i.resolutionNote, resolvedAt: i.resolvedAt,
});

export const incidentRoutes = Router();

incidentRoutes.post("/courier/incident", auth, requireRole("COURIER"), async (req: AuthRequest, res: Response) => {
  const body = incidentSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Choose what happened", errors: body.error.flatten() });
  try {
    const courier = await getCourierForUser(req.user!.id);
    if (!courier) throw new ApiError("Courier profile not found", 404);
    // Only the courier's own jobs can be named
    const orderId = body.data.orderId && (await prisma.order.count({ where: { id: body.data.orderId, courierId: courier.id } })) ? body.data.orderId : null;
    const recent = await prisma.courierIncident.count({ where: { courierId: courier.id, createdAt: { gte: new Date(Date.now() - 60 * 60_000) } } });
    if (recent >= 10) throw new ApiError("You have sent many reports in a short time. Call 112 in an emergency, or contact support.", 429);
    const incident = await prisma.courierIncident.create({
      data: {
        courierId: courier.id, type: body.data.type, orderId, note: body.data.note || null,
        latitude: body.data.lat ?? null, longitude: body.data.lng ?? null,
      },
    });
    alertAdmins(`Courier incident #${incident.id}: ${TYPE_TEXT[body.data.type]}`, [
      `${courier.name} (courier #${courier.id}) reported ${TYPE_TEXT[body.data.type]}${orderId ? ` on order #${orderId}` : ""}.`,
      body.data.note ? `Note: ${body.data.note}` : "",
      courier.phone ? `Courier phone: ${courier.phone}` : "",
      "Contact the courier now. Resolve it under Incidents when it is handled.",
    ].filter(Boolean), { type: "incident", incidentId: String(incident.id) }).catch(() => {});
    res.status(201).json({ ok: true, incident: present(incident) });
  } catch (e) { sendError(res, e); }
});

incidentRoutes.get("/courier/incidents", auth, requireRole("COURIER"), async (req: AuthRequest, res: Response) => {
  try {
    const courier = await getCourierForUser(req.user!.id);
    if (!courier) throw new ApiError("Courier profile not found", 404);
    const rows = await prisma.courierIncident.findMany({ where: { courierId: courier.id }, orderBy: { createdAt: "desc" }, take: 50 });
    res.json({ ok: true, incidents: rows.map(present) });
  } catch (e) { sendError(res, e); }
});

const admin = [auth, requireRole("ADMIN")] as const;

/** GET /admin/incidents?status=OPEN|RESOLVED (default both; open first) */
incidentRoutes.get("/admin/incidents", ...admin, async (req: AuthRequest, res: Response) => {
  const status = String(req.query.status ?? "").toUpperCase();
  try {
    const rows = await prisma.courierIncident.findMany({
      where: status === "OPEN" || status === "RESOLVED" ? { status } : {},
      include: { courier: { select: { id: true, name: true, phone: true, userId: true } } },
      orderBy: [{ status: "asc" }, { createdAt: "desc" }],
      take: 200,
    });
    res.json({
      ok: true,
      incidents: rows.map((r) => ({ ...present(r), latitude: r.latitude, longitude: r.longitude, resolvedById: r.resolvedById, courier: r.courier })),
    });
  } catch (e) { sendError(res, e); }
});

incidentRoutes.post("/admin/incidents/:id(\\d+)/resolve", ...admin, async (req: AuthRequest, res: Response) => {
  const body = z.object({ note: z.string().trim().max(1000).optional() }).safeParse(req.body ?? {});
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid note" });
  try {
    const id = positiveId(req.params.id)!;
    const row = await prisma.courierIncident.findUnique({ where: { id }, include: { courier: { select: { userId: true } } } });
    if (!row) throw new ApiError("Incident not found", 404);
    const updated = await prisma.courierIncident.update({
      where: { id },
      data: { status: "RESOLVED", resolvedAt: new Date(), resolvedById: req.user!.id, resolutionNote: body.data.note || null },
    });
    await audit(req.user!.id, "incident.resolve", "CourierIncident", id, { oldValue: { status: row.status }, newValue: { status: "RESOLVED", note: body.data.note ?? null } });
    if (row.courier.userId) {
      pushToUser(row.courier.userId, {
        title: t("Your report was handled", "Ilmoituksesi on käsitelty"),
        body: body.data.note ? body.data.note.slice(0, 200) : t("The Malvoya team has handled your incident report.", "Malvoyan tiimi on käsitellyt ilmoituksesi."),
        data: { type: "incident", incidentId: String(id) },
      }).catch(() => {});
    }
    res.json({ ok: true, incident: present(updated) });
  } catch (e) { sendError(res, e); }
});
