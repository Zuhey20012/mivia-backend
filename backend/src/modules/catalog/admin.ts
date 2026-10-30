import { Router, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { AuthRequest } from "../../middleware/auth";
import { pushToUser } from "../../lib/push";
import { asLocale } from "../../lib/i18n";
import { escapeHtml, sendEmail } from "../../services/notificationDeliveryService";
import { invalidateCategories } from "./categories";
import { SCHEMES, presentCertificate } from "./certificates";
import { checkClaims } from "./claims";
import { ownerPublishCheck } from "./productWrite";
import { presentProduct, priceInfoFor, productInclude } from "../products/pricing";
import { workingDaysAfter } from "./safety";
import { recallAdminRoutes } from "./recalls";

/**
 * Admin (mounted under /admin, ADMIN session required): Categories (rename, reorder, hide, counts), the Certificates
 * queue, the Product reports queue, Recalls, and a product's compliance view with the claims-checker warnings.
 * Every decision goes to AdminAuditLog.
 */
export const catalogAdminRoutes = Router();
catalogAdminRoutes.use(recallAdminRoutes);

const audit = (adminId: number, action: string, entity: string, entityId: number, oldValue: unknown, newValue: unknown) =>
  prisma.adminAuditLog.create({ data: { adminId, action, entity, entityId, oldValue: oldValue as any, newValue: newValue as any } });

// ─── Categories ──────────────────────────────────────────────────────────────

catalogAdminRoutes.get("/categories", async (_req: AuthRequest, res: Response) => {
  try {
    const [rows, counts, visible] = await Promise.all([
      prisma.category.findMany({ orderBy: [{ sort: "asc" }, { id: "asc" }] }),
      prisma.product.groupBy({ by: ["categoryId"], where: { deletedAt: null }, _count: { _all: true } }),
      prisma.product.groupBy({ by: ["categoryId"], where: { deletedAt: null, isAvailable: true }, _count: { _all: true } }),
    ]);
    const all = new Map(counts.map((c) => [c.categoryId ?? 0, c._count._all]));
    const live = new Map(visible.map((c) => [c.categoryId ?? 0, c._count._all]));
    const sum = (m: Map<number, number>, id: number) => rows.filter((r) => r.parentId === id).reduce((s, r) => s + (m.get(r.id) ?? 0), 0) + (m.get(id) ?? 0);
    res.json({
      ok: true,
      categories: rows.map((r) => ({
        id: r.id, slug: r.slug, parentId: r.parentId, nameEn: r.nameEn, nameFi: r.nameFi, icon: r.icon, tileColor: r.tileColor,
        sort: r.sort, template: r.template, collection: r.isCollection, active: r.active,
        products: sum(all, r.id), visibleProducts: sum(live, r.id),
      })),
      uncategorised: { products: all.get(0) ?? 0, visibleProducts: live.get(0) ?? 0 },
    });
  } catch (e) { sendError(res, e); }
});

const catEdit = z.object({
  nameEn: z.string().trim().min(2).max(60).optional(),
  nameFi: z.string().trim().min(2).max(60).optional(),
  sort: z.number().int().min(0).max(10_000).optional(),
  active: z.boolean().optional(),
}).refine((d) => Object.keys(d).length > 0, { message: "Nothing to change" });

/** Rename, reorder, hide/show. Slugs, parents and templates are fixed by the code (catalog/taxonomy.ts). */
catalogAdminRoutes.patch("/categories/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  const body = catEdit.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid change" });
  try {
    const id = positiveId(req.params.id)!;
    const cur = await prisma.category.findUnique({ where: { id } });
    if (!cur) throw new ApiError("Category not found", 404);
    const updated = await prisma.category.update({ where: { id }, data: body.data });
    await audit(req.user!.id, "category.edit", "Category", id,
      Object.fromEntries(Object.keys(body.data).map((k) => [k, (cur as any)[k]])), body.data);
    invalidateCategories();
    res.json({ ok: true, category: updated });
  } catch (e) { sendError(res, e); }
});

// ─── Certificates queue ──────────────────────────────────────────────────────

catalogAdminRoutes.get("/certificates", async (req: AuthRequest, res: Response) => {
  const status = ["PENDING", "VERIFIED", "REJECTED"].includes(String(req.query.status)) ? String(req.query.status) as any : "PENDING";
  try {
    const rows = await prisma.certificate.findMany({
      where: { status }, orderBy: { createdAt: "asc" }, take: 200,
      include: { store: { select: { id: true, name: true } }, _count: { select: { products: true } } },
    });
    res.json({ ok: true, certificates: rows.map((c) => ({ ...presentCertificate(c, { owner: true }), store: c.store, productCount: c._count.products, submittedAt: c.createdAt, reviewedAt: c.reviewedAt })) });
  } catch (e) { sendError(res, e); }
});

const reviewSchema = z.object({ decision: z.enum(["verify", "reject"]), reason: z.string().trim().max(500).optional() })
  .refine((d) => d.decision !== "reject" || (d.reason?.length ?? 0) >= 5, { message: "Say why the certificate is rejected", path: ["reason"] });

catalogAdminRoutes.post("/certificates/:id(\\d+)/review", async (req: AuthRequest, res: Response) => {
  const body = reviewSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid decision" });
  try {
    const id = positiveId(req.params.id)!;
    const cur = await prisma.certificate.findUnique({ where: { id }, include: { store: { select: { ownerId: true, name: true } } } });
    if (!cur) throw new ApiError("Certificate not found", 404);
    const status = body.data.decision === "verify" ? "VERIFIED" : "REJECTED";
    const updated = await prisma.certificate.update({
      where: { id }, data: { status, reviewedById: req.user!.id, reviewedAt: new Date(), rejectionReason: status === "REJECTED" ? body.data.reason! : null },
    });
    await audit(req.user!.id, `certificate.${body.data.decision}`, "Certificate", id, { status: cur.status }, { status, reason: body.data.reason ?? null });
    const name = SCHEMES[cur.scheme]?.name ?? { en: cur.scheme, fi: cur.scheme };
    pushToUser(cur.store.ownerId, {
      title: status === "VERIFIED" ? { en: `Certificate verified: ${name.en}`, fi: `Sertifikaatti hyväksytty: ${name.fi}` } : { en: `Certificate not accepted: ${name.en}`, fi: `Sertifikaattia ei hyväksytty: ${name.fi}` },
      body: status === "VERIFIED" ? { en: "Shoppers now see it on the products you attached it to.", fi: "Ostajat näkevät sen nyt tuotteissa, joihin liitit sen." } : { en: body.data.reason!, fi: body.data.reason! },
      data: { type: "certificate", certificateId: String(id) },
    }).catch(() => {});
    res.json({ ok: true, certificate: presentCertificate(updated, { owner: true }) });
  } catch (e) { sendError(res, e); }
});

// ─── Product reports queue ───────────────────────────────────────────────────

catalogAdminRoutes.get("/product-reports", async (req: AuthRequest, res: Response) => {
  const status = ["OPEN", "ACTIONED", "DISMISSED"].includes(String(req.query.status)) ? String(req.query.status) as any : "OPEN";
  try {
    const rows = await prisma.productReport.findMany({
      where: { status }, orderBy: { createdAt: "asc" }, take: 200,
      include: { product: { select: { id: true, name: true, description: true, isAvailable: true, lockedReason: true, store: { select: { id: true, name: true } } } } },
    });
    res.json({
      ok: true,
      reports: rows.map((r) => ({
        id: r.id, reason: r.reason, details: r.details, status: r.status, createdAt: r.createdAt,
        // Copyright / trademark notices (2.16.0): {name, email, work, location, onBehalfOf?, goodFaith, at}
        ipNotice: r.ipNotice,
        // Product-safety notices are processed within three working days (GPSR Art. 22(8))
        dueBy: workingDaysAfter(r.createdAt, 3), overdue: r.status === "OPEN" && workingDaysAfter(r.createdAt, 3) < new Date(),
        reporter: { signedIn: r.reporterId !== null, userId: r.reporterId, email: r.reporterEmail },
        resolution: r.resolution, resolutionNote: r.resolutionNote, resolvedAt: r.resolvedAt,
        product: { ...r.product, claims: checkClaims({ name: r.product.name, description: r.product.description }) },
      })),
    });
  } catch (e) { sendError(res, e); }
});

const resolveSchema = z.object({ action: z.enum(["dismiss", "remove_listing"]), note: z.string().trim().min(5).max(1000) });

/** Dismiss, or remove the listing (locked; the store gets a statement of reasons). The reporter hears the outcome. */
catalogAdminRoutes.post("/product-reports/:id(\\d+)/resolve", async (req: AuthRequest, res: Response) => {
  const body = resolveSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Give an action and a note (the reason)" });
  try {
    const id = positiveId(req.params.id)!;
    const r = await prisma.productReport.findUnique({ where: { id }, include: { product: { select: { id: true, name: true, store: { select: { ownerId: true } } } } } });
    if (!r) throw new ApiError("Report not found", 404);
    if (r.status !== "OPEN") throw new ApiError("This report has already been decided", 409);
    const remove = body.data.action === "remove_listing";
    await prisma.$transaction([
      prisma.productReport.update({
        where: { id }, data: { status: remove ? "ACTIONED" : "DISMISSED", resolution: remove ? "listing_removed" : "dismissed", resolutionNote: body.data.note, resolvedById: req.user!.id, resolvedAt: new Date() },
      }),
      ...(remove ? [
        prisma.product.update({ where: { id: r.productId }, data: { isAvailable: false, importDraft: false, lockedAt: new Date(), lockedReason: "ADMIN" } }),
        // Other open notices about the same listing are covered by this decision
        prisma.productReport.updateMany({ where: { productId: r.productId, status: "OPEN", id: { not: id } }, data: { status: "ACTIONED", resolution: "listing_removed", resolutionNote: body.data.note, resolvedById: req.user!.id, resolvedAt: new Date() } }),
      ] : []),
    ]);
    await audit(req.user!.id, `product_report.${body.data.action}`, "ProductReport", id, { status: "OPEN" }, { action: body.data.action, productId: r.productId, note: body.data.note });
    if (remove) {
      const owner = await prisma.user.findUnique({ where: { id: r.product.store.ownerId }, select: { email: true, locale: true } });
      const fi = asLocale(owner?.locale) === "fi";
      const text = fi
        ? `Malvoya poisti tuotteesi "${r.product.name}" myynnistä ilmoituksen perusteella. Syy: ${body.data.note}. Voit pyytää päätöksen uudelleenarviointia vastaamalla Malvoyan tukeen.`
        : `Malvoya removed your listing "${r.product.name}" after a notice. Reason: ${body.data.note}. You can ask for the decision to be reviewed by contacting Malvoya support.`;
      pushToUser(r.product.store.ownerId, { title: { en: "Listing removed", fi: "Tuote poistettu myynnistä" }, body: { en: text, fi: text }, data: { type: "product", productId: String(r.productId) } }).catch(() => {});
      if (owner?.email) sendEmail(owner.email, fi ? "Malvoya – tuote poistettu myynnistä" : "Malvoya – listing removed", `<p>${escapeHtml(text)}</p>`, text, { kind: "seller", locale: fi ? "fi" : "en" }).catch(() => {});
    }
    const reporterEmail = r.reporterEmail ?? (r.reporterId ? (await prisma.user.findUnique({ where: { id: r.reporterId }, select: { email: true } }))?.email : null);
    if (reporterEmail) {
      const text = remove
        ? `Thank you for your report about "${r.product.name}". We removed the listing. / Kiitos ilmoituksestasi tuotteesta "${r.product.name}". Poistimme tuotteen myynnistä.`
        : `Thank you for your report about "${r.product.name}". We checked it and kept the listing: ${body.data.note} / Kiitos ilmoituksestasi tuotteesta "${r.product.name}". Tarkistimme sen, ja tuote jäi myyntiin: ${body.data.note}`;
      sendEmail(reporterEmail, "Malvoya – your report / ilmoituksesi", `<p>${escapeHtml(text)}</p>`, text, { kind: "report" }).catch(() => {});
    }
    res.json({ ok: true, status: remove ? "ACTIONED" : "DISMISSED" });
  } catch (e) { sendError(res, e); }
});

// ─── A product's compliance view ─────────────────────────────────────────────

catalogAdminRoutes.get("/products/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  try {
    const p = await prisma.product.findUnique({
      where: { id: positiveId(req.params.id)! },
      include: { ...productInclude, store: { select: { id: true, name: true, sellerType: true, safetyPledgeAt: true } }, reports: { orderBy: { createdAt: "desc" }, take: 20 } },
    });
    if (!p) throw new ApiError("Product not found", 404);
    const info = await priceInfoFor([p]);
    const { store, reports, ...row } = p;
    res.json({
      ok: true,
      product: {
        ...presentProduct(row as any, info.get(p.id), { owner: true }),
        store,
        claims: checkClaims({ name: p.name, description: p.description, tags: p.tags }),
        publishCheck: ownerPublishCheck(p, store),
        reports: reports.map((r) => ({ id: r.id, reason: r.reason, status: r.status, createdAt: r.createdAt })),
      },
    });
  } catch (e) { sendError(res, e); }
});

// ─── Under-18 flag (no profiling-based recommendations, DSA Art. 28) ─────────

catalogAdminRoutes.patch("/users/:id(\\d+)/minor", async (req: AuthRequest, res: Response) => {
  if (typeof req.body?.isMinor !== "boolean") return res.status(400).json({ ok: false, error: "isMinor must be true or false" });
  try {
    const id = positiveId(req.params.id)!;
    const cur = await prisma.user.findUnique({ where: { id }, select: { isMinor: true } });
    if (!cur) throw new ApiError("User not found", 404);
    await prisma.user.update({ where: { id }, data: { isMinor: req.body.isMinor } });
    await audit(req.user!.id, "user.minor", "User", id, { isMinor: cur.isMinor }, { isMinor: req.body.isMinor });
    res.json({ ok: true, isMinor: req.body.isMinor });
  } catch (e) { sendError(res, e); }
});
