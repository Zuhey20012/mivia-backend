import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { deliveryImageUrl, videoHlsUrl, videoMp4Url, videoPosterUrl } from "../../lib/cloudinary";
import { presentCatalog, presentOption } from "../catalog/present";

/**
 * What every product query loads for presentProduct: options and videos (oldest first), and since 2.12.0 the category,
 * the manufacturer / responsible person records, certificates and an active recall.
 */
export const productInclude = {
  variants: { orderBy: { id: "asc" as const } },
  videos: { orderBy: [{ position: "asc" as const }, { id: "asc" as const }] },
  categoryRef: { select: { id: true, slug: true, nameEn: true, nameFi: true, template: true, parentId: true } },
  manufacturer: true,
  responsiblePerson: true,
  certificates: { include: { certificate: true } },
  recalls: { where: { recall: { status: "ACTIVE" as const } }, select: { recall: { select: { id: true, title: true, createdAt: true } } } },
} satisfies Prisma.ProductInclude;

type VideoRow = { id: number; publicId: string; status: string; durationSec: number | null; width: number | null; height: number | null };

/** Playable URLs for a product video. Shoppers only ever get READY videos. */
export function presentVideo(v: VideoRow, opts: { owner?: boolean } = {}) {
  return {
    id: v.id,
    hls: videoHlsUrl(v.publicId),
    mp4: videoMp4Url(v.publicId),
    poster: videoPosterUrl(v.publicId),
    durationSec: v.durationSec,
    width: v.width,
    height: v.height,
    ...(opts.owner ? { status: v.status } : {}),
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

export type PriceInfo = {
  priceCents: number | null;
  /** Lowest price of the 30 days before the latest reduction; null when there is no real reduction. */
  previousPriceCents: number | null;
  discountPct: number | null;
};

type Change = { priceCents: number; changedAt: Date };

/**
 * Omnibus rule (Hintamerkintäasetus 7 a § / Directive 98/6/EC Art. 6a): a price reduction may only be
 * announced against the lowest price applied during the 30 days before the reduction. When the
 * product has no 30-day price history, no reduction is shown at all.
 */
export function computePriceInfo(current: number | null, changes: Change[]): PriceInfo {
  const none = { priceCents: current, previousPriceCents: null, discountPct: null };
  if (current === null || changes.length < 2) return none;

  const sorted = [...changes].sort((a, b) => a.changedAt.getTime() - b.changedAt.getTime());
  const latest = sorted[sorted.length - 1];
  if (latest.priceCents !== current) return none; // history out of sync: never guess

  const reducedAt = latest.changedAt.getTime();
  const windowStart = reducedAt - 30 * DAY_MS;
  let priceAtWindowStart: number | null = null;
  let lowestInside = Infinity;
  for (const c of sorted.slice(0, -1)) {
    const t = c.changedAt.getTime();
    if (t <= windowStart) priceAtWindowStart = c.priceCents;
    else lowestInside = Math.min(lowestInside, c.priceCents);
  }
  if (priceAtWindowStart === null) return none; // on sale for less than 30 days before the change

  const reference = Math.min(priceAtWindowStart, lowestInside);
  if (reference <= current) return none;
  const discountPct = Math.round(((reference - current) / reference) * 100);
  if (discountPct < 1) return none;
  return { priceCents: current, previousPriceCents: reference, discountPct };
}

export async function priceInfoFor(products: { id: number; salePriceCents: number | null }[]) {
  const ids = products.map((p) => p.id);
  const changes = ids.length
    ? await prisma.priceChange.findMany({
        where: { productId: { in: ids } },
        select: { productId: true, priceCents: true, changedAt: true },
        orderBy: { changedAt: "asc" },
      })
    : [];
  const byProduct = new Map<number, Change[]>();
  for (const c of changes) {
    const list = byProduct.get(c.productId) ?? [];
    list.push(c);
    byProduct.set(c.productId, list);
  }
  return new Map(products.map((p) => [p.id, computePriceInfo(p.salePriceCents, byProduct.get(p.id) ?? [])]));
}

/** Record a new sale price. Call inside the same transaction that changes the product. */
export async function recordPrice(tx: Prisma.TransactionClient, productId: number, priceCents: number | null | undefined) {
  if (priceCents === null || priceCents === undefined) return;
  await tx.priceChange.create({ data: { productId, priceCents } });
}

type ProductWithVariants = {
  id: number;
  salePriceCents: number | null;
  stockQuantity: number;
  isAvailable: boolean;
  variants?: any[];
  videos?: VideoRow[];
};

/**
 * What shoppers see of a product: real prices only, and per-option availability without exact stock
 * counts (no artificial "only 2 left" pressure). Since 2.12.0 also the category, attributes, unit prices, the product
 * safety block, verified certificates, the hygiene-seal notice and an active recall (catalog/present.ts).
 */
export function presentProduct<T extends ProductWithVariants>(product: T, info: PriceInfo | undefined, opts: { owner?: boolean } = {}) {
  const p = product as any;
  const variants = (product.variants ?? []).map((v: any) => {
    const priceCents = product.salePriceCents === null ? null : product.salePriceCents + v.priceAdjustCents;
    return {
      id: v.id,
      size: v.size,
      color: v.color,
      priceCents,
      inStock: v.stock > 0,
      ...presentOption(v, priceCents, p),
      ...(opts.owner ? { stock: v.stock, sku: v.sku ?? null, priceAdjustCents: v.priceAdjustCents } : {}),
    };
  });
  const inStock = product.isAvailable && (variants.length ? variants.some((v) => v.inStock) : product.stockQuantity > 0);
  const pricing = info ?? { priceCents: product.salePriceCents, previousPriceCents: null, discountPct: null };
  // Import bookkeeping is only for the store itself; the raw safety, category and lock columns become structured fields
  const {
    stockQuantity, videos: videoRows, importJobId, externalSource, externalId,
    categoryRef, manufacturer, responsiblePerson, certificates, recalls,
    warningsFi, warningsSv, warningsEn, noWarnings, safetyImages, productModel, batchOrSerial,
    lockedAt, lockedReason, importHold, contentAmount, contentUnit,
    ...rest
  } = p;
  const videos = (videoRows ?? []).filter((v: VideoRow) => opts.owner || v.status === "READY").map((v: VideoRow) => presentVideo(v, opts));
  return {
    ...rest,
    // Shoppers get optimised delivery URLs; owners get the stored URLs back unchanged (they send them back on edit)
    ...(!opts.owner && Array.isArray(rest.images) ? { images: (rest.images as string[]).map(deliveryImageUrl) } : {}),
    ...(opts.owner ? { stockQuantity, importJobId, externalSource, externalId, lockedAt, lockedReason, importHold } : {}),
    ...presentCatalog(p, pricing.priceCents, opts),
    variants,
    videos,
    inStock,
    pricing,
  };
}
