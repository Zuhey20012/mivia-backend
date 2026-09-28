import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";

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
  variants?: { id: number; size: string | null; color: string | null; stock: number; priceAdjustCents: number; sku?: string | null }[];
};

/**
 * What shoppers see of a product: real prices only, and per-option availability without exact stock
 * counts (no artificial "only 2 left" pressure).
 */
export function presentProduct<T extends ProductWithVariants>(product: T, info: PriceInfo | undefined, opts: { owner?: boolean } = {}) {
  const variants = (product.variants ?? []).map((v) => ({
    id: v.id,
    size: v.size,
    color: v.color,
    priceCents: product.salePriceCents === null ? null : product.salePriceCents + v.priceAdjustCents,
    inStock: v.stock > 0,
    ...(opts.owner ? { stock: v.stock, sku: v.sku ?? null, priceAdjustCents: v.priceAdjustCents } : {}),
  }));
  const inStock = product.isAvailable && (variants.length ? variants.some((v) => v.inStock) : product.stockQuantity > 0);
  const { stockQuantity, ...rest } = product;
  return {
    ...rest,
    ...(opts.owner ? { stockQuantity } : {}),
    variants,
    inStock,
    pricing: info ?? { priceCents: product.salePriceCents, previousPriceCents: null, discountPct: null },
  };
}
