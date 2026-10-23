import crypto from "crypto";
import { Router, Response } from "express";
import rateLimit, { ipKeyGenerator } from "express-rate-limit";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { auth, optionalAuth, requireRole, AuthRequest } from "../../middleware/auth";
import { rateLimitStore } from "../../middleware/rateLimiter";
import { isOwnImageUrl, mediaConfigured } from "../../lib/cloudinary";
import { SCHEME_KEYS, presentCertificate, todayDate } from "./certificates";
import { presentOperator } from "./present";

/**
 * Store-side product safety (GPSR) and certificates, and "Report this product":
 *  - the one-time product-safety pledge (self-certification, GPSR Art. 22(10)(b)),
 *  - reusable manufacturer / responsible-person records (Art. 19(a)-(b)),
 *  - certificates the store submits for admin verification (replace the old eco flag),
 *  - POST /products/:id/report (DSA Art. 16 notice; GPSR Art. 22(8) three working days).
 */

const l = (en: string, fi: string) => ({ en, fi });

// ─── Safety pledge ───────────────────────────────────────────────────────────

export const SAFETY_PLEDGE = l(
  "I confirm that I only offer products on Malvoya that comply with EU and Finnish law, including product safety (Regulation (EU) 2023/988), textile and footwear labelling and the cosmetics rules; that the product information I give is correct and complete; and that I act on recalls, safety warnings and Malvoya's requests without delay.",
  "Vahvistan, että tarjoan Malvoyassa vain EU:n ja Suomen lainsäädännön mukaisia tuotteita, mukaan lukien tuoteturvallisuus (asetus (EU) 2023/988), tekstiilien ja jalkineiden merkinnät sekä kosmetiikkasäännöt; että antamani tuotetiedot ovat oikeat ja täydelliset; ja että toimin takaisinvetojen, turvallisuusvaroitusten ja Malvoyan pyyntöjen mukaan viipymättä.",
);
export const SAFETY_PLEDGE_VERSION = `safety-pledge@${crypto.createHash("sha256").update(SAFETY_PLEDGE.en + "\n" + SAFETY_PLEDGE.fi).digest("hex").slice(0, 12)}`;

export function safetyPledgeOf(store: { safetyPledgeAt: Date | null; safetyPledgeVersion: string | null }) {
  return {
    accepted: !!store.safetyPledgeAt,
    acceptedAt: store.safetyPledgeAt,
    version: store.safetyPledgeVersion,
    currentVersion: SAFETY_PLEDGE_VERSION,
    text: SAFETY_PLEDGE,
  };
}

async function ownStore(req: AuthRequest) {
  const store = await prisma.store.findUnique({ where: { ownerId: req.user!.id } });
  if (!store) throw new ApiError("Create your store first", 404);
  return store;
}

export const safetyRoutes = Router();
const vendor = [auth, requireRole("VENDOR")];

safetyRoutes.get("/stores/my/safety-pledge", ...vendor, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, pledge: safetyPledgeOf(await ownStore(req)) });
  } catch (e) { sendError(res, e); }
});

/** Recorded once (with the version of the text), like an agreement acceptance; required before the first publish. */
safetyRoutes.post("/stores/my/safety-pledge", ...vendor, async (req: AuthRequest, res: Response) => {
  if (req.body?.accept !== true) return res.status(400).json({ ok: false, error: "Send accept: true to give the pledge" });
  try {
    const store = await ownStore(req);
    if (store.safetyPledgeAt) return res.json({ ok: true, alreadyAccepted: true, pledge: safetyPledgeOf(store) });
    const updated = await prisma.store.update({ where: { id: store.id }, data: { safetyPledgeAt: new Date(), safetyPledgeVersion: SAFETY_PLEDGE_VERSION } });
    res.status(201).json({ ok: true, alreadyAccepted: false, pledge: safetyPledgeOf(updated) });
  } catch (e) { sendError(res, e); }
});

// ─── Manufacturer / responsible person records ───────────────────────────────

const operatorSchema = z.object({
  name: z.string().trim().min(2).max(120),
  addressLine: z.string().trim().min(2).max(200),
  postalCode: z.string().trim().min(2).max(20),
  city: z.string().trim().min(1).max(80),
  countryCode: z.string().trim().regex(/^[A-Za-z]{2}$/, "Use the two-letter country code, e.g. FI").transform((v) => v.toUpperCase()),
  email: z.string().trim().email().max(200).nullable().optional(),
  url: z.string().trim().url().startsWith("https://").max(300).nullable().optional(),
  phone: z.string().trim().max(30).nullable().optional(),
});
const operatorCreate = operatorSchema.refine((d) => !!(d.email || d.url), { message: "Give an email address or a web address (GPSR: an electronic address)", path: ["email"] });

safetyRoutes.get("/stores/my/operators", ...vendor, async (req: AuthRequest, res: Response) => {
  try {
    const store = await ownStore(req);
    const rows = await prisma.economicOperator.findMany({ where: { storeId: store.id }, orderBy: { name: "asc" }, take: 200 });
    res.json({ ok: true, operators: rows.map(presentOperator) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.post("/stores/my/operators", ...vendor, async (req: AuthRequest, res: Response) => {
  const body = operatorCreate.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid record", errors: body.error.flatten() });
  try {
    const store = await ownStore(req);
    if (await prisma.economicOperator.count({ where: { storeId: store.id } }) >= 200) throw new ApiError("At most 200 records per store", 409);
    const row = await prisma.economicOperator.create({ data: { ...body.data, storeId: store.id } });
    res.status(201).json({ ok: true, operator: presentOperator(row) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.patch("/stores/my/operators/:id(\\d+)", ...vendor, async (req: AuthRequest, res: Response) => {
  const body = operatorSchema.partial().safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid record" });
  try {
    const store = await ownStore(req);
    const row = await prisma.economicOperator.findFirst({ where: { id: positiveId(req.params.id)!, storeId: store.id } });
    if (!row) throw new ApiError("Record not found", 404);
    const next = { ...row, ...body.data };
    if (!next.email && !next.url) throw new ApiError("Give an email address or a web address", 400);
    const updated = await prisma.economicOperator.update({ where: { id: row.id }, data: body.data });
    res.json({ ok: true, operator: presentOperator(updated) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.delete("/stores/my/operators/:id(\\d+)", ...vendor, async (req: AuthRequest, res: Response) => {
  try {
    const store = await ownStore(req);
    const row = await prisma.economicOperator.findFirst({
      where: { id: positiveId(req.params.id)!, storeId: store.id },
      include: { _count: { select: { manufacturedProducts: true, responsibleProducts: true } } },
    });
    if (!row) throw new ApiError("Record not found", 404);
    if (row._count.manufacturedProducts + row._count.responsibleProducts > 0) throw new ApiError("Products still use this record: change them first", 409);
    await prisma.economicOperator.delete({ where: { id: row.id } });
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

// ─── Certificates (store side) ───────────────────────────────────────────────

const certSchema = z.object({
  scheme: z.enum(SCHEME_KEYS),
  licenceNumber: z.string().trim().min(2).max(60),
  holderName: z.string().trim().min(2).max(120),
  scope: z.enum(["whole_product", "component"]),
  componentDescription: z.string().trim().max(120).optional(),
  validUntil: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Use YYYY-MM-DD"),
  evidenceUrl: z.string().trim().url().startsWith("https://").max(500),
  publicVerifyUrl: z.string().trim().url().startsWith("https://").max(500).optional(),
}).refine((d) => d.scope !== "component" || !!d.componentDescription, { message: "Say which part the certificate covers", path: ["componentDescription"] });

safetyRoutes.get("/stores/my/certificates", ...vendor, async (req: AuthRequest, res: Response) => {
  try {
    const store = await ownStore(req);
    const rows = await prisma.certificate.findMany({ where: { storeId: store.id }, orderBy: { createdAt: "desc" }, take: 100, include: { _count: { select: { products: true } } } });
    res.json({ ok: true, certificates: rows.map((c) => ({ ...presentCertificate(c, { owner: true }), productCount: c._count.products })) });
  } catch (e) { sendError(res, e); }
});

/** Submitted certificates wait for an admin (Admin → Certificates); only verified, valid ones are ever shown to shoppers. */
safetyRoutes.post("/stores/my/certificates", ...vendor, async (req: AuthRequest, res: Response) => {
  const body = certSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid certificate", errors: body.error.flatten() });
  try {
    const store = await ownStore(req);
    const validUntil = new Date(`${body.data.validUntil}T00:00:00.000Z`);
    if (Number.isNaN(validUntil.getTime()) || validUntil < todayDate()) throw new ApiError("This certificate has already expired", 400);
    // The certificate file must be the store's own upload (media kind certificate_evidence)
    if (mediaConfigured() && !isOwnImageUrl(body.data.evidenceUrl, `malvoya/certificates/s${store.id}/`)) {
      throw new ApiError("Upload the certificate file with the app's file picker", 400);
    }
    if (await prisma.certificate.count({ where: { storeId: store.id } }) >= 100) throw new ApiError("At most 100 certificates per store", 409);
    const row = await prisma.certificate.create({
      data: { ...body.data, componentDescription: body.data.scope === "component" ? body.data.componentDescription : null, validUntil, storeId: store.id },
    });
    res.status(201).json({ ok: true, certificate: presentCertificate(row, { owner: true }) });
  } catch (e) { sendError(res, e); }
});

safetyRoutes.delete("/stores/my/certificates/:id(\\d+)", ...vendor, async (req: AuthRequest, res: Response) => {
  try {
    const store = await ownStore(req);
    const row = await prisma.certificate.findFirst({ where: { id: positiveId(req.params.id)!, storeId: store.id } });
    if (!row) throw new ApiError("Certificate not found", 404);
    await prisma.certificate.delete({ where: { id: row.id } }); // detaches it from products too
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

// ─── Report this product ─────────────────────────────────────────────────────

export const REPORT_REASONS = ["unsafe", "counterfeit", "illegal", "misleading", "other"] as const;

/** Due date of a notice: product-safety notices within three working days (GPSR Art. 22(8)); Mon–Fri, holidays ignored. */
export function workingDaysAfter(from: Date, days: number) {
  const d = new Date(from);
  let left = days;
  while (left > 0) {
    d.setUTCDate(d.getUTCDate() + 1);
    const wd = d.getUTCDay();
    if (wd !== 0 && wd !== 6) left--;
  }
  return d;
}

const reportSchema = z.object({
  reason: z.enum(REPORT_REASONS),
  details: z.string().trim().max(2000).optional(),
  // Signed-out reporters may leave an address to hear the outcome (DSA Art. 16(5)); optional
  email: z.string().trim().email().max(200).optional(),
}).refine((d) => d.reason !== "other" || (d.details?.length ?? 0) >= 5, { message: "Tell us what is wrong", path: ["details"] });

/** 5 reports per hour per account, or per network address when signed out. */
const reportLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => ((req as AuthRequest).user ? `u:${(req as AuthRequest).user!.id}` : `ip:${ipKeyGenerator(req.ip ?? "")}`),
  message: { ok: false, error: "Too many reports, please try again later." },
  ...rateLimitStore("product-report"),
});

safetyRoutes.post("/products/:id(\\d+)/report", optionalAuth, reportLimiter, async (req: AuthRequest, res: Response) => {
  const body = reportSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Give a reason: unsafe, counterfeit, illegal, misleading or other" });
  try {
    const product = await prisma.product.findFirst({ where: { id: positiveId(req.params.id)!, deletedAt: null }, select: { id: true } });
    if (!product) throw new ApiError("Product not found", 404);
    const reporterId = req.user?.id ?? null;
    if (reporterId) {
      const open = await prisma.productReport.findFirst({ where: { productId: product.id, reporterId, status: "OPEN" } });
      if (open) return res.json({ ok: true, alreadyReported: true, report: { id: open.id, status: open.status, reason: open.reason, dueBy: workingDaysAfter(open.createdAt, 3) } });
    }
    const row = await prisma.productReport.create({
      data: { productId: product.id, reporterId, reporterEmail: reporterId ? null : body.data.email ?? null, reason: body.data.reason, details: body.data.details ?? null },
    });
    res.status(201).json({ ok: true, alreadyReported: false, report: { id: row.id, status: row.status, reason: row.reason, dueBy: workingDaysAfter(row.createdAt, 3) } });
  } catch (e) { sendError(res, e); }
});
