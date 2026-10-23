import crypto from "crypto";
import pino from "pino";
import { ImportJob, ImportSource, Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { imageUrl, mediaConfigured, uploadRemoteImage } from "../../lib/cloudinary";
import { createProductSchema } from "../products/products.schema";
import { applyProductUpdate, assertOwnImages, createProductRecord } from "../products/products.service";
import { productInclude } from "../products/pricing";
import { FieldsError, ownerPublishCheck, prepareCatalogWrite } from "../catalog/productWrite";
import { PublishStore } from "../catalog/publish";
import { HOLD_REASONS, TOPS } from "../catalog/taxonomy";
import { attrDef } from "../catalog/attributes";
import { ImportIssue, ImportItem } from "./mapping";
import { assertPublicHost, parseShopUrl } from "./safeFetch";
import { assertEuroShop, fetchShopifyProducts, mapShopifyProduct } from "./shopify";
import { csvToItems } from "./csv";
import { defineJob, enqueue } from "../../lib/queue";
import { WooKeys, fetchWooProducts, fetchWooVariations, mapWooProduct, wooShopChecks } from "./woocommerce";

/**
 * Catalogue import (Shopify public feed, WooCommerce REST API with read-only keys, or CSV). Runs in-process after the request has returned 202;
 * products arrive HIDDEN (drafts) until the store publishes the job. Photos are re-hosted into the store's
 * own Cloudinary folder, so products only ever reference the store's own uploads. Re-importing updates
 * the same products (storeId + source + external id), never duplicates them.
 */

const logger = pino({ name: "imports" });
const MAX_ISSUES = 200;
export const IMPORT_STALE_MS = 15 * 60_000;
/** Imports a store may start per 24 hours, and photos it may have copied to Cloudinary per 24 hours. */
export const DAILY_IMPORT_LIMIT = 10;
export const DAILY_UPLOAD_CAP = 2000;
const DAY_MS = 86_400_000;
/** Namespace of the per-store advisory lock that makes "one import at a time" race-free. */
const IMPORT_LOCK_NS = 7341;

export function presentJob(j: ImportJob) {
  return {
    id: j.id,
    source: j.source,
    status: j.status,
    shopDomain: j.sourceRef,
    total: j.total,
    created: j.created,
    updated: j.updated,
    skipped: j.skipped,
    errors: Array.isArray(j.errors) ? (j.errors as ImportIssue[]) : [],
    rightsConfirmedAt: j.rightsConfirmedAt,
    publishedAt: j.publishedAt,
    createdAt: j.createdAt,
    finishedAt: j.finishedAt,
  };
}

async function storeForOwner(ownerId: number) {
  const store = await prisma.store.findUnique({ where: { ownerId }, select: { id: true, isVerified: true } });
  if (!store) throw new ApiError("Create your store first", 404);
  return store;
}

/** Imports copy photos into Malvoya's storage, so only approved stores may start one. */
async function importingStore(ownerId: number) {
  const store = await storeForOwner(ownerId);
  if (!store.isVerified) throw new ApiError("You can import your catalogue once Malvoya has approved your store", 403);
  return store;
}

function requireMedia() {
  if (!mediaConfigured()) throw new ApiError("Photo and video uploads are not switched on yet", 503);
}

type Db = Prisma.TransactionClient | typeof prisma;

/** One running import per store, and at most DAILY_IMPORT_LIMIT per 24 hours. Cheap: runs before any DNS or parsing. */
async function assertCanStart(storeId: number, db: Db = prisma) {
  const active = await db.importJob.findFirst({
    where: { storeId, status: { in: ["QUEUED", "RUNNING"] }, updatedAt: { gt: new Date(Date.now() - IMPORT_STALE_MS) } },
    select: { id: true },
  });
  if (active) throw new ApiError("An import is already running for your store. Wait for it to finish.", 409);
  const today = await db.importJob.count({ where: { storeId, createdAt: { gt: new Date(Date.now() - DAY_MS) } } });
  if (today >= DAILY_IMPORT_LIMIT) throw new ApiError(`At most ${DAILY_IMPORT_LIMIT} imports per day. Try again tomorrow.`, 429);
}

/** Creates the job under a per-store advisory lock, so two requests at once cannot both start one. */
function createJob(storeId: number, data: Omit<Prisma.ImportJobUncheckedCreateInput, "storeId">) {
  return prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT 1 AS locked FROM (SELECT pg_advisory_xact_lock(${IMPORT_LOCK_NS}::int, ${storeId}::int)) AS l`;
    await assertCanStart(storeId, tx);
    return tx.importJob.create({ data: { ...data, storeId } });
  });
}

export async function startShopifyImport(ownerId: number, shopUrl: string) {
  requireMedia();
  const store = await importingStore(ownerId);
  const origin = parseShopUrl(shopUrl);
  await assertCanStart(store.id); // before any DNS lookup
  await assertPublicHost(origin);
  const job = await createJob(store.id, { source: "SHOPIFY", sourceRef: origin.host, rightsConfirmedAt: new Date() });
  // Background job (lib/queue.ts): in this process without Redis, else on the queue (worker)
  await enqueue<ImportJobData>("catalogue-import", { jobId: job.id, storeId: store.id, source: "SHOPIFY", shopUrl });
  return presentJob(job);
}

function shopifyLoader(shopUrl: string) {
  const origin = parseShopUrl(shopUrl);
  return async (): Promise<Loaded> => {
    const currencyIssues = await assertEuroShop(origin); // a shop pricing in another currency is refused
    let products, issues: ImportIssue[];
    try {
      ({ products, issues } = await fetchShopifyProducts(origin));
    } catch (e: any) {
      throw new ApiError(e?.message === "NOT_A_SHOPIFY_FEED" ? "This is not a Shopify product feed" : e instanceof ApiError ? e.message : "The shop could not be reached", 502);
    }
    issues.unshift(...currencyIssues);
    const items = products.map((p) => mapShopifyProduct(p, issues)).filter((x): x is ImportItem => !!x);
    return { items, issues, skipped: products.length - items.length, total: products.length };
  };
}

/** Shopify and CSV imports carry nothing secret, so they can wait on the queue. WooCommerce keys never leave memory. */
type ImportJobData = { jobId: number; storeId: number; source: "SHOPIFY" | "CSV"; shopUrl?: string; csv?: string };
defineJob<ImportJobData>("catalogue-import", async (d) => {
  const load = d.source === "SHOPIFY"
    ? shopifyLoader(d.shopUrl!)
    : async () => { const parsed = csvToItems(d.csv!); return { ...parsed, total: parsed.groups }; };
  await runLaunched(d.jobId, d.storeId, d.source, load);
}, { attempts: 1 }); // never re-run: a failed import is marked FAILED and the store can start it again

/**
 * WooCommerce: the store's own read-only REST API keys. They are kept only in this job's closure while it runs
 * (never written to the database or logs) and sent only to the shop's own origin.
 */
export async function startWooImport(ownerId: number, siteUrl: string, keys: WooKeys) {
  requireMedia();
  const store = await importingStore(ownerId);
  const origin = parseShopUrl(siteUrl);
  await assertCanStart(store.id); // before any DNS lookup
  await assertPublicHost(origin);
  const job = await createJob(store.id, { source: "WOOCOMMERCE", sourceRef: origin.host, rightsConfirmedAt: new Date() });
  launch(job.id, store.id, "WOOCOMMERCE", async () => {
    const shopIssues = await wooShopChecks(origin, keys); // wrong keys or another currency stop the job here
    const { products, issues } = await fetchWooProducts(origin, keys);
    issues.unshift(...shopIssues);
    const items: ImportItem[] = [];
    for (const p of products) {
      let variations: Awaited<ReturnType<typeof fetchWooVariations>> = [];
      if (p.type === "variable" && typeof p.id === "number") {
        try {
          variations = await fetchWooVariations(origin, keys, p.id);
        } catch (e: any) {
          issues.push({ item: String(p.name ?? p.id), message: `Options could not be read (${e instanceof ApiError ? e.message : "error"})`, level: "error" });
          continue;
        }
      }
      const item = mapWooProduct(p, variations, issues);
      if (item) items.push(item);
    }
    return { items, issues, skipped: products.length - items.length, total: products.length };
  });
  return presentJob(job);
}

export async function startCsvImport(ownerId: number, csv: string) {
  requireMedia();
  const store = await importingStore(ownerId);
  await assertCanStart(store.id); // before parsing up to 1 MB
  const parsed = csvToItems(csv); // header problems → 400 now; row problems are reported on the job
  const job = await createJob(store.id, { source: "CSV", rightsConfirmedAt: new Date(), total: parsed.groups });
  await enqueue<ImportJobData>("catalogue-import", { jobId: job.id, storeId: store.id, source: "CSV", csv });
  return presentJob(job);
}

type Loaded = { items: ImportItem[]; issues: ImportIssue[]; skipped: number; total: number };

/** Runs the job after the response has been sent. A crash marks it FAILED; a restart leaves it to the watchdog. */
function launch(jobId: number, storeId: number, source: ImportSource, load: () => Promise<Loaded>) {
  setImmediate(() => { runLaunched(jobId, storeId, source, load); });
}

async function runLaunched(jobId: number, storeId: number, source: ImportSource, load: () => Promise<Loaded>) {
  await runJob(jobId, storeId, source, load).catch(async (e) => {
    logger.error({ jobId, err: e?.message }, "Import failed");
    await prisma.importJob.updateMany({
      where: { id: jobId, status: { in: ["QUEUED", "RUNNING"] } },
      data: {
        status: "FAILED", finishedAt: new Date(),
        errors: [{ item: "import", message: e instanceof ApiError ? e.message : "The import stopped unexpectedly", level: "error" }],
      },
    }).catch(() => {});
  });
}

async function runJob(jobId: number, storeId: number, source: ImportSource, load: () => Promise<Loaded>) {
  const claimed = await prisma.importJob.updateMany({ where: { id: jobId, status: "QUEUED" }, data: { status: "RUNNING" } });
  if (claimed.count === 0) return;

  const { items, issues, skipped: preSkipped, total } = await load();
  const counts = { created: 0, updated: 0, skipped: preSkipped, uploads: 0 };
  // Photos this store already had copied in the last 24 hours (other jobs): the daily cap is shared
  const earlier = await prisma.importJob.aggregate({
    where: { storeId, id: { not: jobId }, createdAt: { gt: new Date(Date.now() - DAY_MS) } },
    _sum: { uploads: true },
  });
  const budget = { left: Math.max(0, DAILY_UPLOAD_CAP - (earlier._sum.uploads ?? 0)), used: () => counts.uploads++ };
  const errors: ImportIssue[] = [];
  const note = (i: ImportIssue) => { if (errors.length < MAX_ISSUES) errors.push(i); };
  issues.forEach(note);
  const progress = (extra: Prisma.ImportJobUpdateManyMutationInput = {}) =>
    prisma.importJob.updateMany({
      where: { id: jobId, status: "RUNNING" },
      data: { total, ...counts, errors: errors as unknown as Prisma.InputJsonValue, ...extra },
    });
  await progress();

  const uploaded = new Map<string, string>(); // remote url → our URL, within this job
  const store = await prisma.store.findUniqueOrThrow({ where: { id: storeId }, select: { id: true, sellerType: true, safetyPledgeAt: true } });
  for (const item of items) {
    try {
      const result = await importItem(jobId, store, source, item, uploaded, note, budget);
      counts[result]++;
    } catch (e: any) {
      counts.skipped++;
      if (!(e instanceof ApiError)) logger.warn({ jobId, err: e?.message }, "Import item failed");
      note({ item: item.label, message: e instanceof ApiError ? e.message : "Could not be saved", level: "error" });
    }
    const res = await progress(); // heartbeat: the watchdog fails jobs without progress for 15 minutes
    if (res.count === 0) return; // marked FAILED meanwhile
  }
  await progress({ status: "DONE", finishedAt: new Date() });
}

type UploadBudget = { left: number; used: () => void };

/**
 * Copies a photo into the store's own folder. The same photo always gets the same name (re-imports reuse it).
 * At most DAILY_UPLOAD_CAP copies per store per 24 hours (protects the Cloudinary quota).
 */
async function rehost(storeId: number, remote: string, cache: Map<string, string>, known: Set<string>, budget: UploadBudget) {
  const hit = cache.get(remote);
  if (hit) return hit;
  const publicId = `malvoya/products/s${storeId}/imp-${crypto.createHash("sha1").update(`${storeId}:${remote}`).digest("hex").slice(0, 24)}`;
  if (known.has(imageUrl(publicId))) return imageUrl(publicId); // already copied for this product
  if (budget.left <= 0) throw new Error(`daily limit of ${DAILY_UPLOAD_CAP} photos reached, try again tomorrow`);
  budget.left--;
  budget.used();
  const up = await uploadRemoteImage(remote, publicId);
  const url = imageUrl(up.publicId);
  cache.set(remote, url);
  return url;
}

/** "Material, Manufacturer, …": the missing fields of an imported draft, for the import report. */
function missingText(fields: { field: string }[]) {
  const names = [...new Set(fields.map((f) => {
    const key = f.field.replace(/^attributes\./, "").split(".")[0];
    return attrDef(key)?.label.en ?? ({ categorySlug: "category", manufacturerId: "manufacturer", responsiblePersonId: "responsible person", productModel: "model / type", warnings: "warnings (FI + SV)", safetyPledge: "safety pledge", contentAmount: "content (ml / g)", name: "name (generic green claim)", description: "description (generic green claim)" } as Record<string, string>)[key] ?? key;
  }))];
  return names.slice(0, 8).join(", ") + (names.length > 8 ? ", …" : "");
}

async function importItem(
  jobId: number, store: PublishStore & { id: number }, source: ImportSource, item: ImportItem,
  cache: Map<string, string>, note: (i: ImportIssue) => void, budget: UploadBudget,
): Promise<"created" | "updated"> {
  const storeId = store.id;
  const existing = await prisma.product.findFirst({
    where: { storeId, externalSource: source, externalId: item.externalId },
    include: { variants: true },
  });
  // The store deleted it: a re-import never brings it back
  if (existing?.deletedAt) throw new ApiError("Deleted from your store earlier, so it was not imported again", 400);
  const images: string[] = [];
  const known = new Set(existing?.images ?? []);
  const settled = await Promise.allSettled(item.imageUrls.map((u) => rehost(storeId, u, cache, known, budget)));
  settled.forEach((s, i) => {
    if (s.status === "fulfilled") images.push(s.value);
    else note({ item: item.label, message: `Photo ${i + 1} could not be copied (${String(s.reason?.message ?? "error").slice(0, 120)})`, level: "warning" });
  });
  assertOwnImages(images, storeId); // never a remote URL on a product

  const m = item.match;
  const parsed = createProductSchema.safeParse({
    name: item.name,
    description: item.description,
    category: item.category,
    // Mapped with the spec's keyword rules; unmatched items stay drafts without a category (never "Other")
    ...(m.slug && !m.hold ? { categorySlug: m.slug } : {}),
    ...(m.audience ? { audience: m.audience } : {}),
    ...(item.brand || m.vintage ? { attributes: { ...(item.brand ? { brand: item.brand } : {}), ...(m.vintage && m.slug ? { vintage: true } : {}) } } : {}),
    ...(item.content ? { contentAmount: item.content.amount, contentUnit: item.content.unit } : {}),
    condition: item.condition,
    tags: item.tags,
    images,
    salePriceCents: item.priceCents,
    stockQuantity: item.stockQuantity,
    isSecondHand: item.isSecondHand ?? false,
    isAvailable: false,
    variants: item.variants,
  });
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    throw new ApiError(`Invalid ${first?.path.join(".") || "product"}: ${first?.message ?? "check the data"}`, 400);
  }
  const data = parsed.data;
  const bookkeeping = { gtin: item.gtin ?? null, importJobId: jobId };

  if (!existing) {
    let prepared;
    try {
      prepared = await prepareCatalogWrite(store, null, { ...data, isAvailable: false }, { mapLegacy: false });
    } catch (e) {
      // Attribute values the shop's data got wrong: keep the draft without them rather than losing the product
      if (!(e instanceof FieldsError)) throw e;
      prepared = await prepareCatalogWrite(store, null, { ...data, attributes: undefined, isAvailable: false }, { mapLegacy: false });
    }
    if (m.hold) {
      prepared.data.importHold = m.holdKey;
      note({ item: item.label, message: `On hold: ${(HOLD_REASONS[m.holdKey!] ?? m.hold).en}`, level: "warning" });
    } else if (!m.slug) {
      note({ item: item.label, message: m.topOnly
        ? `Looks like ${TOPS.get(m.topOnly)?.en ?? m.topOnly}: pick the exact category before publishing`
        : "No category matched: pick one before publishing", level: "warning" });
    } else if (m.slug.endsWith("-other")) {
      note({ item: item.label, message: "Filed under Other clothing: check the category", level: "warning" });
    }
    for (const w of prepared.warnings) note({ item: item.label, message: w.message.en, level: "warning" });
    const created = await createProductRecord(storeId, prepared.data, { ...bookkeeping, importDraft: true, externalSource: source, externalId: item.externalId });
    const check = ownerPublishCheck(created, store);
    if (!check.ready) note({ item: item.label, message: `Missing before publishing: ${missingText(check.missing)}`, level: "warning" });
    return "created";
  }

  // Re-import: price, stock, description, photos and options follow the source; name, category and
  // visibility stay as the store left them.
  const byKey = new Map(existing.variants.map((v) => [`${(v.size ?? "").toLowerCase()}|${(v.color ?? "").toLowerCase()}`, v.id]));
  await applyProductUpdate(existing, {
    salePriceCents: data.salePriceCents,
    stockQuantity: data.stockQuantity,
    ...(data.description ? { description: data.description } : {}),
    ...(images.length ? { images } : {}),
    variants: data.variants.map((v) => {
      const id = byKey.get(`${(v.size ?? "").toLowerCase()}|${(v.color ?? "").toLowerCase()}`);
      return id ? { ...v, id } : v;
    }),
  }, bookkeeping);
  return "updated";
}

export async function listJobs(ownerId: number) {
  const store = await storeForOwner(ownerId);
  const jobs = await prisma.importJob.findMany({ where: { storeId: store.id }, orderBy: { createdAt: "desc" }, take: 20 });
  return jobs.map(presentJob);
}

async function jobForOwner(ownerId: number, id: number) {
  const store = await storeForOwner(ownerId);
  const job = await prisma.importJob.findFirst({ where: { id, storeId: store.id } });
  if (!job) throw new ApiError("Import not found", 404);
  return job;
}

export async function getJob(ownerId: number, id: number) {
  return presentJob(await jobForOwner(ownerId, id));
}

/**
 * Makes the job's drafts visible: only imported products that were never published or hidden by the store
 * (importDraft), with at least one photo and a price, and (since 2.12.0) that meet their template's publishing rules.
 * The others stay drafts and are listed in `incomplete` with what is missing. A product the store hid or deleted
 * stays hidden.
 */
export async function publishJob(ownerId: number, id: number) {
  const job = await jobForOwner(ownerId, id);
  if (job.status === "QUEUED" || job.status === "RUNNING") throw new ApiError("This import is still running", 409);
  const store = await prisma.store.findUniqueOrThrow({ where: { id: job.storeId }, select: { sellerType: true, safetyPledgeAt: true } });
  const drafts = await prisma.product.findMany({
    where: {
      storeId: job.storeId, importJobId: job.id, importDraft: true, isAvailable: false, canBeSold: true, lockedAt: null, deletedAt: null,
      salePriceCents: { not: null }, images: { isEmpty: false },
    },
    include: productInclude,
    take: 2000,
  });
  const ready: number[] = [];
  const incomplete: { productId: number; name: string; missing: { field: string; code: string; message: { en: string; fi: string } }[] }[] = [];
  for (const p of drafts) {
    const check = ownerPublishCheck(p, store);
    if (check.ready) ready.push(p.id);
    else if (incomplete.length < 200) incomplete.push({ productId: p.id, name: p.name, missing: check.missing });
  }
  const res = ready.length
    ? await prisma.product.updateMany({ where: { id: { in: ready }, importDraft: true, isAvailable: false }, data: { isAvailable: true, importDraft: false } })
    : { count: 0 };
  await prisma.importJob.update({ where: { id: job.id }, data: { publishedAt: new Date() } });
  return { published: res.count, incomplete };
}

/** Jobs that made no progress for 15 minutes (server restart, crash) are marked FAILED. */
export async function failStaleImports() {
  const stale = await prisma.importJob.findMany({
    where: { status: { in: ["QUEUED", "RUNNING"] }, updatedAt: { lt: new Date(Date.now() - IMPORT_STALE_MS) } },
    select: { id: true, errors: true },
    take: 100,
  });
  for (const j of stale) {
    const errors = [...(Array.isArray(j.errors) ? (j.errors as ImportIssue[]) : []).slice(0, MAX_ISSUES - 1),
      { item: "import", message: "The import was interrupted. Start it again; products already imported are updated, not duplicated.", level: "error" }];
    await prisma.importJob.updateMany({
      where: { id: j.id, status: { in: ["QUEUED", "RUNNING"] } },
      data: { status: "FAILED", finishedAt: new Date(), errors: errors as unknown as Prisma.InputJsonValue },
    });
  }
  return stale.length;
}
