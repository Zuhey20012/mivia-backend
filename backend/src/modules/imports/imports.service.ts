import crypto from "crypto";
import pino from "pino";
import { ImportJob, ImportSource, Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { imageUrl, mediaConfigured, uploadRemoteImage } from "../../lib/cloudinary";
import { createProductSchema } from "../products/products.schema";
import { applyProductUpdate, assertOwnImages, createProductRecord } from "../products/products.service";
import { ImportIssue, ImportItem } from "./mapping";
import { assertPublicHost, parseShopUrl } from "./safeFetch";
import { fetchShopifyProducts, mapShopifyProduct } from "./shopify";
import { csvToItems } from "./csv";

/**
 * Catalogue import (Shopify public feed or CSV). Runs in-process after the request has returned 202;
 * products arrive HIDDEN (drafts) until the store publishes the job. Photos are re-hosted into the store's
 * own Cloudinary folder, so products only ever reference the store's own uploads. Re-importing updates
 * the same products (storeId + source + external id), never duplicates them.
 */

const logger = pino({ name: "imports" });
const MAX_ISSUES = 200;
export const IMPORT_STALE_MS = 15 * 60_000;

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
  const store = await prisma.store.findUnique({ where: { ownerId }, select: { id: true } });
  if (!store) throw new ApiError("Create your store first", 404);
  return store;
}

function requireMedia() {
  if (!mediaConfigured()) throw new ApiError("Photo and video uploads are not switched on yet", 503);
}

async function assertNoActiveJob(storeId: number) {
  const active = await prisma.importJob.findFirst({
    where: { storeId, status: { in: ["QUEUED", "RUNNING"] }, updatedAt: { gt: new Date(Date.now() - IMPORT_STALE_MS) } },
    select: { id: true },
  });
  if (active) throw new ApiError("An import is already running for your store. Wait for it to finish.", 409);
}

export async function startShopifyImport(ownerId: number, shopUrl: string) {
  requireMedia();
  const store = await storeForOwner(ownerId);
  const origin = parseShopUrl(shopUrl);
  await assertPublicHost(origin);
  await assertNoActiveJob(store.id);
  const job = await prisma.importJob.create({
    data: { storeId: store.id, source: "SHOPIFY", sourceRef: origin.host, rightsConfirmedAt: new Date() },
  });
  launch(job.id, store.id, "SHOPIFY", async () => {
    let products, issues: ImportIssue[];
    try {
      ({ products, issues } = await fetchShopifyProducts(origin));
    } catch (e: any) {
      throw new ApiError(e?.message === "NOT_A_SHOPIFY_FEED" ? "This is not a Shopify product feed" : e instanceof ApiError ? e.message : "The shop could not be reached", 502);
    }
    const items = products.map((p) => mapShopifyProduct(p, issues)).filter((x): x is ImportItem => !!x);
    return { items, issues, skipped: products.length - items.length, total: products.length };
  });
  return presentJob(job);
}

export async function startCsvImport(ownerId: number, csv: string) {
  requireMedia();
  const store = await storeForOwner(ownerId);
  const parsed = csvToItems(csv); // header problems → 400 now; row problems are reported on the job
  await assertNoActiveJob(store.id);
  const job = await prisma.importJob.create({
    data: { storeId: store.id, source: "CSV", rightsConfirmedAt: new Date(), total: parsed.groups },
  });
  launch(job.id, store.id, "CSV", async () => ({ ...parsed, total: parsed.groups }));
  return presentJob(job);
}

type Loaded = { items: ImportItem[]; issues: ImportIssue[]; skipped: number; total: number };

/** Runs the job after the response has been sent. A crash marks it FAILED; a restart leaves it to the watchdog. */
function launch(jobId: number, storeId: number, source: ImportSource, load: () => Promise<Loaded>) {
  setImmediate(() => {
    runJob(jobId, storeId, source, load).catch(async (e) => {
      logger.error({ jobId, err: e?.message }, "Import failed");
      await prisma.importJob.updateMany({
        where: { id: jobId, status: { in: ["QUEUED", "RUNNING"] } },
        data: {
          status: "FAILED", finishedAt: new Date(),
          errors: [{ item: "import", message: e instanceof ApiError ? e.message : "The import stopped unexpectedly", level: "error" }],
        },
      }).catch(() => {});
    });
  });
}

async function runJob(jobId: number, storeId: number, source: ImportSource, load: () => Promise<Loaded>) {
  const claimed = await prisma.importJob.updateMany({ where: { id: jobId, status: "QUEUED" }, data: { status: "RUNNING" } });
  if (claimed.count === 0) return;

  const { items, issues, skipped: preSkipped, total } = await load();
  const counts = { created: 0, updated: 0, skipped: preSkipped };
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
  for (const item of items) {
    try {
      const result = await importItem(jobId, storeId, source, item, uploaded, note);
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

/** Copies a photo into the store's own folder. The same photo always gets the same name (re-imports reuse it). */
async function rehost(storeId: number, remote: string, cache: Map<string, string>, known: Set<string>) {
  const hit = cache.get(remote);
  if (hit) return hit;
  const publicId = `malvoya/products/s${storeId}/imp-${crypto.createHash("sha1").update(`${storeId}:${remote}`).digest("hex").slice(0, 24)}`;
  if (known.has(imageUrl(publicId))) return imageUrl(publicId); // already copied for this product
  const up = await uploadRemoteImage(remote, publicId);
  const url = imageUrl(up.publicId);
  cache.set(remote, url);
  return url;
}

async function importItem(
  jobId: number, storeId: number, source: ImportSource, item: ImportItem,
  cache: Map<string, string>, note: (i: ImportIssue) => void,
): Promise<"created" | "updated"> {
  const existing = await prisma.product.findFirst({
    where: { storeId, externalSource: source, externalId: item.externalId },
    include: { variants: true },
  });
  const images: string[] = [];
  const known = new Set(existing?.images ?? []);
  const settled = await Promise.allSettled(item.imageUrls.map((u) => rehost(storeId, u, cache, known)));
  settled.forEach((s, i) => {
    if (s.status === "fulfilled") images.push(s.value);
    else note({ item: item.label, message: `Photo ${i + 1} could not be copied (${String(s.reason?.message ?? "error").slice(0, 120)})`, level: "warning" });
  });
  assertOwnImages(images, storeId); // never a remote URL on a product

  const parsed = createProductSchema.safeParse({
    name: item.name,
    description: item.description,
    category: item.category,
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
    await createProductRecord(storeId, { ...data, isAvailable: false }, { ...bookkeeping, externalSource: source, externalId: item.externalId });
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

/** Makes the job's drafts visible: only those with at least one photo and a price. */
export async function publishJob(ownerId: number, id: number) {
  const job = await jobForOwner(ownerId, id);
  if (job.status === "QUEUED" || job.status === "RUNNING") throw new ApiError("This import is still running", 409);
  const res = await prisma.product.updateMany({
    where: {
      storeId: job.storeId, importJobId: job.id, isAvailable: false, canBeSold: true,
      salePriceCents: { not: null }, images: { isEmpty: false },
    },
    data: { isAvailable: true },
  });
  await prisma.importJob.update({ where: { id: job.id }, data: { publishedAt: new Date() } });
  return res.count;
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
