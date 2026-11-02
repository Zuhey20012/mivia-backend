import { Router, Request, Response } from "express";
import pino from "pino";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { auth, AuthRequest } from "../../middleware/auth";
import { pushConfigured, pushToUser } from "../../lib/push";
import { defineJob, enqueue } from "../../lib/queue";
import { Locale, asLocale, localeFromHeader } from "../../lib/i18n";
import { escapeHtml, sendEmail } from "../../services/notificationDeliveryService";
import { deliveryImageUrl } from "../../lib/cloudinary";
import { env } from "../../config/env";
import { legalPageHtml } from "../legal/legal.routes";
import { FieldsError } from "./productWrite";
import { invalidateCategoryCounts } from "./categories";

const logger = pino({ name: "recalls" });

/**
 * Product safety recalls (GPSR Art. 22(12), 35-37). An admin creates a recall for one or more products; every
 * identical listing (same GTIN, or same brand + model, in any shop) is locked, the shops are told why, and every buyer
 * of those products is notified directly by push and email in their language with the notice in the legal format
 * (headline "Product safety recall", hazard without softening words, "stop using it now", remedies, contact). Recalls
 * are public at /recalls and GET /api/v1/recalls. Everything is written to the admin audit log.
 */

const l = (en: string, fi: string) => ({ en, fi });
export const RECALL_HEADLINE = l("Product safety recall", "Tuotteen turvallisuuteen liittyvä takaisinveto");
const REMEDY_LABELS: Record<string, { en: string; fi: string }> = {
  repair: l("Repair", "Korjaus"), replacement: l("Replacement", "Vaihto uuteen"), refund: l("Refund", "Rahojen palautus"),
};

/** Words that play a hazard down; Art. 36 notices must not use them. */
const SOFTENING = [
  /\bvoluntar/i, /\bprecaution/i, /\bin rare cases\b/i, /\bno (?:accidents|injuries|incidents)\b/i, /\bunlikely\b/i, /\bout of an abundance\b/i,
  /vapaaehtoi/i, /varotoim/i, /varmuuden vuoksi/i, /harvinaisissa tapauksissa/i, /ei ole (?:raportoitu|ilmoitettu)/i, /epätodennäköi/i,
];

const createSchema = z.object({
  productIds: z.array(z.number().int().positive()).min(1).max(50),
  title: z.string().trim().min(3).max(160).optional(),
  reasonFi: z.string().trim().min(10).max(2000),
  reasonEn: z.string().trim().min(10).max(2000),
  reasonSv: z.string().trim().max(2000).optional(),
  remedyFi: z.string().trim().min(5).max(2000),
  remedyEn: z.string().trim().min(5).max(2000),
  remedySv: z.string().trim().max(2000).optional(),
  remedies: z.array(z.enum(["repair", "replacement", "refund"])).min(1).max(3),
  contact: z.string().trim().min(5).max(200),
});

type ProductInfo = {
  id: number; name: string; images: string[]; gtin: string | null; productModel: string | null; batchOrSerial: string | null;
  attributes: unknown; createdAt: Date; store: { id: number; name: string; ownerId: number };
};
const productSelect = {
  id: true, name: true, images: true, gtin: true, productModel: true, batchOrSerial: true, attributes: true, createdAt: true,
  store: { select: { id: true, name: true, ownerId: true } },
} as const;

const brandOf = (p: { attributes: unknown }) => {
  const b = (p.attributes as any)?.brand;
  return typeof b === "string" && b.trim() ? b.trim() : null;
};

/** Creates the recall: locks every identical listing, tells the shops, queues the buyer notices. */
export async function createRecall(adminId: number, input: z.infer<typeof createSchema>) {
  const soft = (["reasonFi", "reasonEn", "reasonSv"] as const).filter((k) => input[k] && SOFTENING.some((re) => re.test(input[k]!)));
  if (soft.length) {
    throw new FieldsError("INVALID_RECALL", soft.map((field) => ({ field, code: "softening_words", message: l(
      "Describe the hazard plainly: no words like \"voluntary\", \"precautionary\", \"in rare cases\" or \"no accidents reported\" (GPSR Art. 36).",
      "Kuvaa vaara suoraan: ei sanoja kuten \"vapaaehtoinen\", \"varotoimenpide\", \"harvinaisissa tapauksissa\" tai \"onnettomuuksia ei ole raportoitu\" (GPSR 36 art.).",
    ) })));
  }
  const selected = await prisma.product.findMany({ where: { id: { in: input.productIds } }, select: productSelect });
  if (selected.length !== new Set(input.productIds).size) throw new ApiError("Unknown product in the recall", 400);

  // Identical listings: same GTIN, or same brand + model (case-insensitive), in any shop
  const gtins = [...new Set(selected.map((p) => p.gtin).filter((g): g is string => !!g))];
  const pairs = selected.map((p) => ({ brand: brandOf(p), model: p.productModel?.trim() || null })).filter((x) => x.brand && x.model) as { brand: string; model: string }[];
  const or: any[] = [];
  if (gtins.length) or.push({ gtin: { in: gtins } });
  for (const pr of pairs) or.push({ productModel: { equals: pr.model, mode: "insensitive" }, facets: { some: { key: "brand", value: pr.brand.toLowerCase() } } });
  const identical = or.length
    ? await prisma.product.findMany({ where: { id: { notIn: selected.map((p) => p.id) }, OR: or }, select: productSelect, take: 2000 })
    : [];
  const matchedBy = (p: ProductInfo) => (p.gtin && gtins.includes(p.gtin) ? "gtin" : "brand_model");
  const all: (ProductInfo & { matchedBy: string })[] = [
    ...selected.map((p) => ({ ...p, matchedBy: "selected" })),
    ...identical.map((p) => ({ ...p, matchedBy: matchedBy(p) })),
  ];
  const title = input.title ?? [brandOf(selected[0]), selected[0].name, selected[0].productModel].filter(Boolean).join(" ").slice(0, 160);

  const now = new Date();
  const recall = await prisma.$transaction(async (tx) => {
    const r = await tx.recall.create({
      data: {
        title, reasonFi: input.reasonFi, reasonEn: input.reasonEn, reasonSv: input.reasonSv ?? null,
        remedyFi: input.remedyFi, remedyEn: input.remedyEn, remedySv: input.remedySv ?? null,
        remedies: input.remedies, contact: input.contact, createdById: adminId,
        products: { createMany: { data: all.map((p) => ({ productId: p.id, matchedBy: p.matchedBy })) } },
      },
    });
    const ids = all.map((p) => p.id);
    await tx.product.updateMany({ where: { id: { in: ids } }, data: { isAvailable: false, importDraft: false, lockedAt: now, lockedReason: "RECALL" } });
    await tx.drop.updateMany({ where: { productId: { in: ids }, status: { in: ["READY", "PROCESSING"] } }, data: { status: "REMOVED", removedReason: "Product safety recall" } });
    await tx.adminAuditLog.create({
      data: { adminId, action: "recall.create", entity: "Recall", entityId: r.id, newValue: { title, productIds: ids, matchedBy: Object.fromEntries(all.map((p) => [p.id, p.matchedBy])), remedies: input.remedies } },
    });
    return r;
  });
  invalidateCategoryCounts();

  // Statement of reasons to each shop whose listing was locked (DSA Art. 17)
  const shops = new Map<number, { ownerId: number; name: string; products: string[] }>();
  for (const p of all) shops.set(p.store.id, { ownerId: p.store.ownerId, name: p.store.name, products: [...(shops.get(p.store.id)?.products ?? []), p.name] });
  for (const s of shops.values()) notifyShop(recall.id, s).catch((e) => logger.warn({ err: e?.message }, "Shop recall notice failed"));

  await enqueue<{ recallId: number }>("recall-notify-buyers", { recallId: recall.id });
  return { recall: await presentRecall(recall.id, { admin: true }), locked: all.length, identical: identical.length };
}

async function notifyShop(recallId: number, s: { ownerId: number; name: string; products: string[] }) {
  const owner = await prisma.user.findUnique({ where: { id: s.ownerId }, select: { email: true, locale: true } });
  const L = asLocale(owner?.locale);
  const fi = L === "fi";
  const list = s.products.slice(0, 20).join(", ");
  await pushToUser(s.ownerId, {
    title: l(`Product safety recall: ${s.products[0]}`, `Takaisinveto: ${s.products[0]}`),
    body: l("Malvoya locked the listing because of a product safety recall. Open the notice for the reason.", "Malvoya lukitsi tuotteen tuoteturvallisuuteen liittyvän takaisinvedon vuoksi. Avaa ilmoitus nähdäksesi syyn."),
    data: { type: "recall", recallId: String(recallId) },
  }).catch(() => {});
  if (owner?.email) {
    const url = `${env.publicApiUrl}/recalls/${recallId}`;
    const text = fi
      ? `Lukitsimme seuraavat tuotteesi tuoteturvallisuuteen liittyvän takaisinvedon vuoksi: ${list}. Syy ja ohjeet: ${url}. Tuotteita ei voi enää julkaista. Ota yhteyttä Malvoyan tukeen, jos tämä on mielestäsi virhe.`
      : `We locked these listings because of a product safety recall: ${list}. Reason and instructions: ${url}. They can no longer be published. Contact Malvoya support if you think this is a mistake.`;
    await sendEmail(owner.email, `Malvoya – ${fi ? RECALL_HEADLINE.fi : RECALL_HEADLINE.en}`, `<p>${escapeHtml(text)}</p>`, text, { kind: "recall", locale: fi ? "fi" : "en" });
  }
}

// ─── The notice (Art. 36 format) ─────────────────────────────────────────────

type Purchase = { orderedAt: Date; storeName: string };

async function recallWithProducts(id: number) {
  return prisma.recall.findUnique({
    where: { id },
    include: { products: { include: { product: { select: productSelect } } } },
  });
}
type RecallFull = NonNullable<Awaited<ReturnType<typeof recallWithProducts>>>;

const date = (d: Date, L: Locale) => new Intl.DateTimeFormat(L === "fi" ? "fi-FI" : "en-GB", { timeZone: "Europe/Helsinki", day: "numeric", month: "numeric", year: "numeric" }).format(d);

/** The written notice in the reader's language: headline, product, identifiers, sale, hazard, what to do, remedies, contact. */
export function recallNotice(r: RecallFull, L: Locale, purchase?: Purchase) {
  const fi = L === "fi";
  const p = (en: string, f: string) => (fi ? f : en);
  const products = r.products.map((rp) => rp.product);
  const first = products[0];
  const lines: string[] = [];
  const html: string[] = [];
  const add = (heading: string | null, text: string) => {
    lines.push(heading ? `${heading}: ${text}` : text);
    html.push(heading ? `<h2>${escapeHtml(heading)}</h2><p>${escapeHtml(text)}</p>` : `<p>${escapeHtml(text)}</p>`);
  };
  const headline = fi ? RECALL_HEADLINE.fi : RECALL_HEADLINE.en;
  html.push(`<h1>${escapeHtml(headline)}</h1>`);
  lines.push(headline.toUpperCase(), "");
  if (first?.images?.[0]) html.push(`<p><img src="${escapeHtml(deliveryImageUrl(first.images[0]))}" alt="" style="max-width:240px;border-radius:12px"></p>`);
  add(p("Product", "Tuote"), [brandOf(first), first?.name].filter(Boolean).join(" – "));
  const ids = [...new Set(products.flatMap((x) => [
    x.productModel ? `${p("model", "malli")} ${x.productModel}` : null,
    x.gtin ? `EAN ${x.gtin}` : null,
    x.batchOrSerial ? `${p("batch", "erä")} ${x.batchOrSerial}` : null,
  ].filter(Boolean) as string[]))];
  if (ids.length) add(p("Identification", "Tunnistetiedot"), `${ids.join(", ")}. ${p("You find these on the label or the packaging.", "Löydät ne tuotteen merkinnöistä tai pakkauksesta.")}`);
  const stores = [...new Set(products.map((x) => x.store.name))].join(", ");
  const soldFrom = products.reduce((m, x) => (x.createdAt < m ? x.createdAt : m), products[0]?.createdAt ?? r.createdAt);
  add(p("Sold", "Myynti"), purchase
    ? p(`You bought it on ${date(purchase.orderedAt, L)} from ${purchase.storeName} on Malvoya.`, `Ostit tuotteen ${date(purchase.orderedAt, L)} myyjältä ${purchase.storeName} Malvoyassa.`)
    : p(`Sold on Malvoya by ${stores} from ${date(soldFrom, L)} to ${date(r.createdAt, L)}.`, `Myyty Malvoyassa (${stores}) ${date(soldFrom, L)}–${date(r.createdAt, L)}.`));
  add(p("Hazard", "Vaara"), fi ? r.reasonFi : r.reasonEn);
  if (r.reasonSv) add("Fara (svenska)", r.reasonSv);
  add(p("What to do", "Mitä tehdä"), `${p("Stop using this product now.", "Lopeta tuotteen käyttö heti.")} ${fi ? r.remedyFi : r.remedyEn}`);
  add(p("Remedies offered free of charge", "Maksuttomat korjaavat toimenpiteet"), r.remedies.map((x) => (REMEDY_LABELS[x] ?? l(x, x))[L]).join(", "));
  add(p("Contact", "Yhteystiedot"), r.contact);
  add(null, p("Please share this notice with anyone you gave or lent the product to.", "Kerro tästä ilmoituksesta myös niille, joille olet antanut tai lainannut tuotteen."));
  if (r.status === "CLOSED") add(null, p("This recall is closed.", "Tämä takaisinveto on päättynyt."));
  return { subject: `Malvoya – ${headline}: ${first?.name ?? r.title}`, html: html.join("\n"), text: lines.join("\n") };
}

// ─── Buyer notifications ─────────────────────────────────────────────────────

/**
 * Every buyer of a recalled product (any paid order, for as long as Malvoya keeps order records), once per channel.
 * A legal obligation, so it is sent even when the customer switched marketing off. Deleted (anonymised) accounts
 * cannot be reached: the public recall page covers them.
 */
export async function notifyRecallBuyers(recallId: number) {
  const r = await recallWithProducts(recallId);
  if (!r) return 0;
  const productIds = r.products.map((p) => p.productId);
  const items = await prisma.orderItem.findMany({
    where: { productId: { in: productIds }, order: { paidAt: { not: null } } },
    select: { order: { select: { userId: true, paidAt: true, store: { select: { name: true } } } } },
    orderBy: { id: "asc" },
    take: 50_000,
  });
  const firstPurchase = new Map<number, Purchase>();
  for (const i of items) if (!firstPurchase.has(i.order.userId)) firstPurchase.set(i.order.userId, { orderedAt: i.order.paidAt!, storeName: i.order.store.name });
  const users = await prisma.user.findMany({
    where: { id: { in: [...firstPurchase.keys()] }, isActive: true, deletedAt: null },
    select: { id: true, email: true, locale: true, _count: { select: { devices: true } } },
  });
  let notified = 0;
  for (const u of users) {
    const L = asLocale(u.locale);
    const already = await prisma.recallNotification.findMany({ where: { recallId, userId: u.id }, select: { channel: true } });
    const sent = new Set(already.map((a) => a.channel));
    const notice = recallNotice(r, L, firstPurchase.get(u.id));
    if (!sent.has("push")) {
      await pushToUser(u.id, {
        title: RECALL_HEADLINE,
        body: l(`Stop using ${r.products[0]?.product.name ?? r.title} now. Open the notice for what to do.`, `Lopeta tuotteen ${r.products[0]?.product.name ?? r.title} käyttö heti. Avaa ilmoitus nähdäksesi, mitä tehdä.`),
        data: { type: "recall", recallId: String(recallId) },
      }).catch(() => {});
      await prisma.recallNotification.create({ data: { recallId, userId: u.id, channel: "push", delivered: pushConfigured() && u._count.devices > 0, locale: L } }).catch(() => {});
    }
    if (!sent.has("email")) {
      const res = await sendEmail(u.email, notice.subject, `<div style="font-family:-apple-system,system-ui,'Segoe UI',sans-serif;max-width:640px;margin:0 auto;color:#17131C;line-height:1.55">${notice.html}</div>`, notice.text, { kind: "recall", locale: L as "fi" | "en" });
      await prisma.recallNotification.create({ data: { recallId, userId: u.id, channel: "email", delivered: res.delivered, locale: L } }).catch(() => {});
    }
    notified++;
  }
  await prisma.recall.update({ where: { id: recallId }, data: { buyersNotifiedAt: new Date(), notifiedUsers: await prisma.recallNotification.groupBy({ by: ["userId"], where: { recallId } }).then((g) => g.length) } });
  logger.info({ recallId, notified }, "Recall notices sent");
  return notified;
}

defineJob<{ recallId: number }>("recall-notify-buyers", async ({ recallId }) => { await notifyRecallBuyers(recallId); }, { attempts: 3, backoffMs: 10_000 });

// ─── Presentation and routes ─────────────────────────────────────────────────

export async function presentRecall(id: number, opts: { admin?: boolean } = {}) {
  const r = await recallWithProducts(id);
  if (!r) return null;
  return presentRecallRow(r, opts);
}

function presentRecallRow(r: RecallFull, opts: { admin?: boolean } = {}) {
  return {
    id: r.id,
    title: r.title,
    status: r.status,
    publishedAt: r.createdAt,
    closedAt: r.closedAt,
    headline: RECALL_HEADLINE,
    hazard: { fi: r.reasonFi, en: r.reasonEn, sv: r.reasonSv },
    remedy: { fi: r.remedyFi, en: r.remedyEn, sv: r.remedySv },
    remedies: r.remedies,
    contact: r.contact,
    url: `${env.publicApiUrl}/recalls/${r.id}`,
    products: r.products.map((rp) => ({
      id: rp.product.id, name: rp.product.name, brand: brandOf(rp.product), productModel: rp.product.productModel,
      gtin: rp.product.gtin, batchOrSerial: rp.product.batchOrSerial, image: rp.product.images[0] ? deliveryImageUrl(rp.product.images[0]) : null,
      storeName: rp.product.store.name, ...(opts.admin ? { matchedBy: rp.matchedBy, storeId: rp.product.store.id } : {}),
    })),
    ...(opts.admin ? { buyersNotifiedAt: r.buyersNotifiedAt, notifiedUsers: r.notifiedUsers } : {}),
  };
}

export const recallApiRoutes = Router();

recallApiRoutes.get("/recalls", async (_req: Request, res: Response) => {
  try {
    const rows = await prisma.recall.findMany({ orderBy: { createdAt: "desc" }, take: 100, include: { products: { include: { product: { select: productSelect } } } } });
    res.set("Cache-Control", "public, max-age=60");
    res.json({ ok: true, recalls: rows.map((r) => presentRecallRow(r)) });
  } catch (e) { sendError(res, e); }
});

recallApiRoutes.get("/recalls/:id(\\d+)", async (req: Request, res: Response) => {
  try {
    const r = await presentRecall(positiveId(req.params.id)!);
    if (!r) throw new ApiError("Recall not found", 404);
    res.json({ ok: true, recall: r });
  } catch (e) { sendError(res, e); }
});

/** In-app notices: recalls of products this customer bought, with whether they were notified. */
recallApiRoutes.get("/me/recalls", auth, async (req: AuthRequest, res: Response) => {
  try {
    const bought = await prisma.orderItem.findMany({
      where: { order: { userId: req.user!.id, paidAt: { not: null } }, product: { recalls: { some: {} } } },
      select: { productId: true }, take: 500,
    });
    const rows = bought.length ? await prisma.recall.findMany({
      where: { products: { some: { productId: { in: bought.map((b) => b.productId) } } } },
      orderBy: { createdAt: "desc" }, take: 50, include: { products: { include: { product: { select: productSelect } } } },
    }) : [];
    res.json({ ok: true, recalls: rows.map((r) => presentRecallRow(r)) });
  } catch (e) { sendError(res, e); }
});

/** Public pages: /recalls and /recalls/:id (escaped, no scripts, Cloudinary images only). */
export const recallPageRoutes = Router();
const RECALL_CSP = "default-src 'none'; img-src https://res.cloudinary.com; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const pageLocale = (req: Request): Locale => (req.query.lang === "fi" || req.query.lang === "en" ? req.query.lang : localeFromHeader(req.headers["accept-language"]) ?? "fi");

recallPageRoutes.get("/recalls", async (req: Request, res: Response) => {
  const L = pageLocale(req);
  try {
    const rows = await prisma.recall.findMany({ orderBy: { createdAt: "desc" }, take: 100, include: { products: { include: { product: { select: productSelect } } } } });
    const title = L === "fi" ? "Takaisinvedot" : "Recalls";
    const body = `<h1>${escapeHtml(title)}</h1>` + (rows.length
      ? `<ul>${rows.map((r) => `<li><a href="/recalls/${r.id}?lang=${L}">${escapeHtml(r.title)}</a> – ${escapeHtml(date(r.createdAt, L))}${r.status === "CLOSED" ? escapeHtml(L === "fi" ? " (päättynyt)" : " (closed)") : ""}</li>`).join("")}</ul>`
      : `<p>${escapeHtml(L === "fi" ? "Malvoyassa myytyihin tuotteisiin ei ole takaisinvetoja." : "There are no recalls of products sold on Malvoya.")}</p>`);
    res.set("Cache-Control", "public, max-age=60").set("Content-Security-Policy", RECALL_CSP).type("html").send(legalPageHtml(title, body));
  } catch (e) { sendError(res, e); }
});

recallPageRoutes.get("/recalls/:id(\\d+)", async (req: Request, res: Response) => {
  const L = pageLocale(req);
  try {
    const r = await recallWithProducts(positiveId(req.params.id)!);
    if (!r) return res.status(404).type("text").send("Not found");
    const n = recallNotice(r, L);
    res.set("Cache-Control", "public, max-age=60").set("Content-Security-Policy", RECALL_CSP).type("html").send(legalPageHtml(n.subject, n.html));
  } catch (e) { sendError(res, e); }
});

// ─── Admin ───────────────────────────────────────────────────────────────────

export const recallAdminRoutes = Router(); // mounted under /admin (ADMIN session required there)

recallAdminRoutes.get("/recalls", async (_req: AuthRequest, res: Response) => {
  try {
    const rows = await prisma.recall.findMany({ orderBy: { createdAt: "desc" }, take: 200, include: { products: { include: { product: { select: productSelect } } } } });
    res.json({ ok: true, recalls: rows.map((r) => presentRecallRow(r, { admin: true })) });
  } catch (e) { sendError(res, e); }
});

recallAdminRoutes.post("/recalls", async (req: AuthRequest, res: Response) => {
  const body = createSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid recall", errors: body.error.flatten() });
  try {
    res.status(201).json({ ok: true, ...(await createRecall(req.user!.id, body.data)) });
  } catch (e) { sendError(res, e); }
});

/** Status: ACTIVE ↔ CLOSED (audited). Locked listings stay locked: a recalled product is never re-listed. */
recallAdminRoutes.patch("/recalls/:id(\\d+)", async (req: AuthRequest, res: Response) => {
  const status = req.body?.status;
  if (status !== "ACTIVE" && status !== "CLOSED") return res.status(400).json({ ok: false, error: "status must be ACTIVE or CLOSED" });
  try {
    const id = positiveId(req.params.id)!;
    const cur = await prisma.recall.findUnique({ where: { id } });
    if (!cur) throw new ApiError("Recall not found", 404);
    await prisma.$transaction([
      prisma.recall.update({ where: { id }, data: { status, closedAt: status === "CLOSED" ? new Date() : null } }),
      prisma.adminAuditLog.create({ data: { adminId: req.user!.id, action: "recall.status", entity: "Recall", entityId: id, oldValue: { status: cur.status }, newValue: { status } } }),
    ]);
    res.json({ ok: true, recall: await presentRecall(id, { admin: true }) });
  } catch (e) { sendError(res, e); }
});

recallAdminRoutes.post("/recalls/:id(\\d+)/notify", async (req: AuthRequest, res: Response) => {
  try {
    const id = positiveId(req.params.id)!;
    if (!(await prisma.recall.findUnique({ where: { id }, select: { id: true } }))) throw new ApiError("Recall not found", 404);
    res.json({ ok: true, notified: await notifyRecallBuyers(id) });
  } catch (e) { sendError(res, e); }
});
