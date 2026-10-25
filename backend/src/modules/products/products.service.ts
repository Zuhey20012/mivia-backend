import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { destroyResource, isOwnImageUrl, mediaConfigured } from "../../lib/cloudinary";
import { priceInfoFor, presentProduct, productInclude, recordPrice } from "./pricing";
import { NAMED_FILTERS } from "./products.schema";
import { assertPublishable, ownerPublishCheck, prepareCatalogWrite } from "../catalog/productWrite";
import { audienceWhere, categoryFilter, categoryIndex, invalidateCategoryCounts, presentMatchedCategories, storesInReach, syncFacets, templatesOf } from "../catalog/categories";
import { ALL_FACET_KEYS, facetKeysFor, facetLabel } from "../catalog/attributes";
import { categoriesForQuery } from "../catalog/matcher";
import { liveCertificateWhere } from "../catalog/certificates";
import { PublishStore } from "../catalog/publish";
import { collectionFilter } from "../catalog/collections";

type VariantInput = { id?: number; size?: string; color?: string; sku?: string; stock: number; priceAdjustCents: number } & Record<string, unknown>;

const publicStoreSelect = {
  id: true, name: true, logoUrl: true, rating: true, totalReviews: true, sellerType: true,
  businessId: true, address: true, isVerified: true,
} as const;

async function present<T extends Parameters<typeof presentProduct>[0]>(products: T[], opts: { owner?: boolean; store?: PublishStore } = {}) {
  const info = await priceInfoFor(products);
  // Owners also get the completeness meter: { ready, missing: [field issues], warnings }
  return products.map((p) => ({
    ...presentProduct(p, info.get(p.id), opts),
    ...(opts.owner && opts.store ? { publishCheck: ownerPublishCheck(p, opts.store) } : {}),
  }));
}

/** Photos must be uploads into this store's own folder (when uploads are switched on). */
export function assertOwnImages(images: string[] | undefined, storeId: number) {
  if (!images?.length || !mediaConfigured()) return;
  const bad = images.find((url) => !isOwnImageUrl(url, `malvoya/products/s${storeId}/`));
  if (bad) throw new ApiError("Add photos with the app's photo picker", 400);
}

export async function getProductsByStore(storeId: number, query: Record<string, string>, viewerId?: number) {
  const page  = Math.max(1, Number(query.page || 1));
  const limit = Math.min(50, Math.max(1, Number(query.limit || 20)));
  const store = await prisma.store.findUnique({ where: { id: storeId }, select: { isVerified: true, ownerId: true, sellerType: true, safetyPledgeAt: true } });
  const isOwner = !!store && store.ownerId === viewerId;
  if (!store || (!store.isVerified && !isOwner)) return { products: [], total: 0, page, limit };
  // Owners also see their hidden products so they can re-enable them; deleted products are gone for everyone
  const where: Prisma.ProductWhereInput = isOwner ? { storeId, deletedAt: null } : { storeId, isAvailable: true, deletedAt: null };

  if (query.canBeSold)     where.canBeSold     = query.canBeSold === "true";
  if (query.canBeRented)   where.canBeRented   = query.canBeRented === "true";
  if (query.isSecondHand)  where.isSecondHand  = query.isSecondHand === "true";
  if (query.condition)     where.condition     = query.condition as any;
  if (query.category) {
    const f = await categoryFilter(query.category);
    if (f) where.AND = [f];
  }
  if (query.search)        where.name          = { contains: query.search, mode: "insensitive" };
  if (query.minPrice || query.maxPrice) {
    where.salePriceCents = {
      ...(query.minPrice ? { gte: Number(query.minPrice) } : {}),
      ...(query.maxPrice ? { lte: Number(query.maxPrice) } : {}),
    };
  }

  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where, skip: (page - 1) * limit, take: limit,
      include: productInclude,
      orderBy: [{ isFeatured: "desc" }, { createdAt: "desc" }],
    }),
    prisma.product.count({ where }),
  ]);
  return { products: await present(products, { owner: isOwner, store }), total, page, limit };
}

export async function getProductById(id: number, viewerId?: number) {
  const product = await prisma.product.findFirst({
    where: { id, deletedAt: null },
    include: { ...productInclude, store: { select: { ...publicStoreSelect, ownerId: true } } },
  });
  const isOwner = !!product && product.store.ownerId === viewerId;
  // Hidden products (drafts, deleted) are for the owner only; a recalled one stays readable so buyers who open it from an
  // order see the recall banner (GPSR Art. 22(12), 35(4)), but it cannot be bought
  const recalled = !!product && product.recalls.length > 0;
  if (!product || ((!product.store.isVerified || !product.isAvailable) && !isOwner && !recalled)) throw new ApiError("Product not found", 404);
  const { ownerId, ...store } = product.store;
  const [presented] = await present([{ ...product, store }], { owner: isOwner });
  const favorite = viewerId
    ? !!(await prisma.favorite.findUnique({ where: { userId_productId: { userId: viewerId, productId: id } } }))
    : false;
  return { ...presented, isFavorite: favorite };
}

type SearchQuery = {
  q?: string; category?: string; audience?: string; ageGroup?: string; collection?: string; size?: string; color?: string; condition?: string; secondHand?: string;
  handmade?: string; storeId?: number; lat?: number; lng?: number; minPrice?: number; maxPrice?: number; sort: string; page: number; limit: number;
  certificate?: string; attr?: Record<string, string>;
} & Partial<Record<(typeof NAMED_FILTERS)[number], string>>;

const splitValues = (v: string) => v.split(",").map((x) => x.trim()).filter(Boolean).slice(0, 10);

/**
 * Catalogue search across all verified stores: text, category (descendants included), audience, size/colour, price and
 * the attribute filters of the category's template (2.12). `eco` is ignored since 2.12.0. Also returns the categories a
 * query names ("huulipuna" → Makeup › Lips).
 */
export async function searchProducts(q: SearchQuery) {
  const and: Prisma.ProductWhereInput[] = [{ isAvailable: true, deletedAt: null, canBeSold: true, store: { isVerified: true } }];
  const matched = q.q ? categoriesForQuery(q.q) : [];
  const idx = await categoryIndex();
  if (q.q) {
    const term = q.q;
    // Stores whose name matches are looked up first, so every branch of the OR is on Product itself and Postgres can
    // combine indexes (trigram indexes, docs/scaling/indexes.md) instead of scanning every product joined to its store
    const storeIds = (await prisma.store.findMany({
      where: { isVerified: true, name: { contains: term, mode: "insensitive" } }, select: { id: true }, take: 1000,
    })).map((s) => s.id);
    // A query that names a subcategory ("huulipuna") also finds the products filed there
    const catIds = matched.map((slug) => idx.bySlug.get(slug)).filter((n) => !!n?.template).map((n) => n!.id).slice(0, 1);
    and.push({
      OR: [
        { name: { contains: term, mode: "insensitive" } },
        { description: { contains: term, mode: "insensitive" } },
        { category: { contains: term, mode: "insensitive" } },
        { tags: { has: term.toLowerCase() } },
        ...(storeIds.length ? [{ storeId: { in: storeIds } }] : []),
        ...(catIds.length ? [{ categoryId: { in: catIds } }] : []),
      ],
    });
  }
  let allowedKeys: Set<string> | null = null;
  if (q.category) {
    const f = await categoryFilter(q.category);
    if (f) {
      and.push(f);
      allowedKeys = new Set((await templatesOf(q.category)).flatMap((t) => facetKeysFor(t)));
    } else {
      and.push({ category: { equals: q.category, mode: "insensitive" } }); // legacy free text (older app builds)
    }
  }
  if (q.audience || q.ageGroup) and.push(audienceWhere(q.audience, q.ageGroup));
  if (q.collection) {
    const f = await collectionFilter(q.collection);
    if (!f) throw Object.assign(new ApiError("Unknown collection", 400), { extra: { code: "UNKNOWN_COLLECTION" } });
    and.push(f);
  }
  if (q.condition) and.push({ condition: q.condition as any });
  if (q.secondHand) and.push({ isSecondHand: q.secondHand === "true" });
  if (q.handmade) and.push({ isHandmade: true });
  if (q.storeId) and.push({ storeId: q.storeId });
  if (q.lat !== undefined && q.lng !== undefined) and.push({ storeId: { in: (await storesInReach(q.lat, q.lng)) ?? [] } });
  if (q.size || q.color) {
    and.push({
      variants: {
        some: {
          stock: { gt: 0 },
          ...(q.size ? { size: { equals: q.size, mode: "insensitive" } } : {}),
          ...(q.color ? { color: { contains: q.color, mode: "insensitive" } } : {}),
        },
      },
    });
  }
  // Attribute filters: named params and attr[key]=value; only the keys of the category's template
  const filters: [string, string][] = [];
  for (const k of NAMED_FILTERS) if (q[k]) filters.push([k, q[k]!]);
  for (const [k, v] of Object.entries(q.attr ?? {})) if (typeof v === "string" && v) filters.push([k, v]);
  for (const [key, raw] of filters) {
    if (!ALL_FACET_KEYS.includes(key)) throw Object.assign(new ApiError(`Unknown filter "${key}"`, 400), { extra: { code: "UNKNOWN_FILTER" } });
    if (allowedKeys && !allowedKeys.has(key)) {
      throw Object.assign(new ApiError(`The filter "${facetLabel(key).en}" is not available in this category`, 400), { extra: { code: "FILTER_NOT_AVAILABLE" } });
    }
    const values = splitValues(raw).map((v) => (key === "brand" || key === "size" ? v.toLowerCase() : v));
    and.push({ facets: { some: { key, value: { in: values } } } });
  }
  if (q.certificate) and.push({ certificates: { some: { certificate: { ...liveCertificateWhere(), scheme: { in: splitValues(q.certificate) } } } } });
  if (q.minPrice !== undefined || q.maxPrice !== undefined) {
    and.push({ salePriceCents: { ...(q.minPrice !== undefined ? { gte: q.minPrice } : {}), ...(q.maxPrice !== undefined ? { lte: q.maxPrice } : {}) } });
  }

  const orderBy: Prisma.ProductOrderByWithRelationInput[] =
    q.sort === "price_asc" ? [{ salePriceCents: "asc" }] :
    q.sort === "price_desc" ? [{ salePriceCents: "desc" }] :
    q.sort === "rating" ? [{ store: { rating: "desc" } }, { createdAt: "desc" }] :
    q.sort === "newest" ? [{ createdAt: "desc" }] :
    [{ isFeatured: "desc" }, { createdAt: "desc" }];

  const where = { AND: and };
  const [products, total, categories] = await Promise.all([
    prisma.product.findMany({
      where, orderBy, skip: (q.page - 1) * q.limit, take: q.limit,
      include: { ...productInclude, store: { select: publicStoreSelect } },
    }),
    prisma.product.count({ where }),
    presentMatchedCategories(matched),
  ]);
  return { products: await present(products), total, page: q.page, limit: q.limit, categories };
}

async function storeForOwner(ownerId: number) {
  const store = await prisma.store.findUnique({ where: { ownerId } });
  if (!store) throw new ApiError("Create your store first", 404);
  return store;
}

/**
 * Creates a product from the app. The catalogue part is validated per template (422 INVALID_PRODUCT_DATA) and a
 * visible product must meet its publishing rules (422 PUBLISH_REQUIREMENTS); drafts (isAvailable: false) may be
 * incomplete. `warnings` = claims-checker hits on the name and description.
 */
export async function createProduct(ownerId: number, data: any) {
  const store = await storeForOwner(ownerId);
  assertOwnImages(data.images, store.id);
  assertOwnImages(data.safetyImages, store.id);
  const prepared = await prepareCatalogWrite(store, null, data);
  if (data.isAvailable !== false) await assertPublishable(prepared, store);
  const created = await createProductRecord(store.id, prepared.data, {}, prepared.certificateIds);
  const [presented] = await present([created], { owner: true, store });
  return { product: presented, warnings: prepared.warnings };
}

/**
 * The one way a product is created (the app and the catalogue import): options, stock = sum of option
 * stock, and the first sale price recorded in PriceChange (Omnibus history). `data` is createProductSchema
 * output; `extra` carries import bookkeeping (externalSource, externalId, gtin, importJobId).
 * The caller checks the images first.
 */
export async function createProductRecord(storeId: number, data: any, extra: Partial<Prisma.ProductUncheckedCreateInput> = {}, certificateIds?: number[]) {
  const { variants, ...productData } = data as { variants: VariantInput[] } & Record<string, any>;
  const clean = (variants ?? []).map(({ id, ...v }) => v);
  // With options, the product's stock is the sum of its options' stock
  const stockQuantity = clean.length ? clean.reduce((s, v) => s + v.stock, 0) : productData.stockQuantity;

  return prisma.$transaction(async (tx) => {
    const product = await tx.product.create({
      data: {
        ...productData, ...extra, stockQuantity, storeId,
        tags: (productData.tags ?? []).map((t: string) => t.toLowerCase()),
        variants: clean.length ? { createMany: { data: clean } } : undefined,
      } as Prisma.ProductUncheckedCreateInput,
      include: productInclude,
    });
    await recordPrice(tx, product.id, product.salePriceCents);
    if (certificateIds?.length) await tx.productCertificate.createMany({ data: certificateIds.map((certificateId) => ({ productId: product.id, certificateId })) });
    await syncFacets(tx, product.id);
    return tx.product.findUniqueOrThrow({ where: { id: product.id }, include: productInclude });
  }).finally(invalidateCategoryCounts);
}

export async function updateProduct(id: number, ownerId: number, data: any) {
  const product = await prisma.product.findUnique({ where: { id }, include: { ...productInclude, store: true } });
  if (!product || product.deletedAt) throw new ApiError("Product not found", 404);
  if (product.store.ownerId !== ownerId) throw new ApiError("Forbidden", 403);
  // A recall (or an admin decision on a notice) locks the listing: the store cannot show it again
  if (product.lockedAt && data.isAvailable === true) {
    throw Object.assign(new ApiError(product.lockedReason === "RECALL"
      ? "This product is part of a product safety recall and cannot be shown again"
      : "Malvoya removed this listing; it cannot be shown again", 409), { extra: { code: "PRODUCT_LOCKED" } });
  }
  assertOwnImages(data.images, product.storeId);
  assertOwnImages(data.safetyImages, product.storeId);
  const prepared = await prepareCatalogWrite(product.store, product, data);
  const visible = data.isAvailable ?? product.isAvailable;
  if (visible && !product.lockedAt) await assertPublishable(prepared, product.store, product.id);
  // Once the store shows or hides a product itself, publishing an import never changes it again
  const updated = await applyProductUpdate(product, prepared.data, data.isAvailable !== undefined ? { importDraft: false } : {}, prepared.certificateIds);
  const [presented] = await present([updated], { owner: true, store: product.store });
  return { product: presented, warnings: prepared.warnings };
}

/**
 * The one way a product is changed (the app and re-imports): options are matched by id (unknown ids are
 * refused), removed options are deleted, or kept with no stock when they were ordered, and a new sale
 * price is recorded in PriceChange (Omnibus history). The caller checks ownership and images first.
 */
export async function applyProductUpdate(
  product: { id: number; salePriceCents: number | null; variants: { id: number }[] },
  data: any,
  extra: Prisma.ProductUncheckedUpdateInput = {},
  certificateIds?: number[],
) {
  const id = product.id;
  const { variants, ...productData } = data as { variants?: VariantInput[] } & Record<string, any>;
  if (productData.tags) productData.tags = productData.tags.map((t: string) => t.toLowerCase());

  return prisma.$transaction(async (tx) => {
    if (variants) {
      const keep = new Set<number>();
      for (const v of variants) {
        const { id: variantId, ...fields } = v;
        if (variantId) {
          const owned = product.variants.find((x) => x.id === variantId);
          if (!owned) throw new ApiError("Unknown option", 400);
          await tx.productVariant.update({ where: { id: variantId }, data: fields });
          keep.add(variantId);
        } else {
          const createdVariant = await tx.productVariant.create({ data: { ...fields, productId: id } });
          keep.add(createdVariant.id);
        }
      }
      // Removed options: delete when never ordered, otherwise keep for order history with no stock
      for (const old of product.variants.filter((x) => !keep.has(x.id))) {
        const used = await tx.orderItem.count({ where: { variantId: old.id } }) + await tx.rentalItem.count({ where: { variantId: old.id } });
        if (used) await tx.productVariant.update({ where: { id: old.id }, data: { stock: 0 } });
        else await tx.productVariant.delete({ where: { id: old.id } });
      }
      const all = await tx.productVariant.findMany({ where: { productId: id } });
      if (all.length) productData.stockQuantity = all.reduce((s, v) => s + v.stock, 0);
    }

    await tx.product.update({ where: { id }, data: { ...productData, ...extra } });
    if (productData.salePriceCents !== undefined && productData.salePriceCents !== product.salePriceCents) {
      await recordPrice(tx, id, productData.salePriceCents);
    }
    if (certificateIds) {
      await tx.productCertificate.deleteMany({ where: { productId: id, certificateId: { notIn: certificateIds } } });
      if (certificateIds.length) await tx.productCertificate.createMany({ data: certificateIds.map((certificateId) => ({ productId: id, certificateId })), skipDuplicates: true });
    }
    await syncFacets(tx, id);
    return tx.product.findUniqueOrThrow({ where: { id }, include: productInclude });
  }).finally(invalidateCategoryCounts);
}

/**
 * Deletes a product. A product nobody ever ordered or rented, with no drops and not from a catalogue import, is
 * deleted for good (with its options, price history and videos). Anything else is kept for the records but
 * marked deleted (deletedAt): it disappears everywhere, also from the store's own lists, and its drops are taken
 * down. Imported products are kept that way so a re-import never brings back what the store deleted.
 */
export async function deleteProduct(id: number, ownerId: number): Promise<"hard" | "soft"> {
  const product = await prisma.product.findUnique({
    where: { id },
    include: { store: true, videos: { select: { publicId: true } }, _count: { select: { orderItems: true, rentalItems: true, drops: true, reports: true, recalls: true } } },
  });
  if (!product || product.deletedAt) throw new ApiError("Product not found", 404);
  if (product.store.ownerId !== ownerId) throw new ApiError("Forbidden", 403);
  // Reported or recalled products are kept too: the notice and recall records must keep pointing at them
  const keep = product._count.orderItems + product._count.rentalItems + product._count.drops + product._count.reports + product._count.recalls > 0 || !!product.externalSource;
  if (!keep) {
    try {
      await prisma.product.delete({ where: { id } });
      for (const v of product.videos) destroyResource(v.publicId, "video").catch(() => {});
      return "hard";
    } catch (e: any) {
      // Something started pointing at it in the meantime (e.g. an order): keep it instead
      if (e?.code !== "P2003") throw e;
    }
  }
  await prisma.$transaction([
    prisma.product.update({ where: { id }, data: { isAvailable: false, importDraft: false, deletedAt: new Date() } }),
    prisma.drop.updateMany({ where: { productId: id, status: { in: ["READY", "PROCESSING"] } }, data: { status: "REMOVED", removedReason: "Product deleted by the store" } }),
    prisma.favorite.deleteMany({ where: { productId: id } }),
  ]);
  return "soft";
}

export type MyProductsFilter = "all" | "visible" | "drafts" | "soldout";

/** The store's own catalogue, paginated and searchable (deleted products are never listed). */
export async function listMyProducts(ownerId: number, q: { page: number; limit: number; q?: string; filter: MyProductsFilter }) {
  const store = await storeForOwner(ownerId);
  const where: Prisma.ProductWhereInput = {
    storeId: store.id,
    deletedAt: null,
    ...(q.q ? { name: { contains: q.q, mode: "insensitive" } } : {}),
    ...(q.filter === "visible" ? { isAvailable: true } : q.filter === "drafts" ? { isAvailable: false } : q.filter === "soldout" ? { stockQuantity: { lte: 0 } } : {}),
  };
  const [products, total] = await Promise.all([
    prisma.product.findMany({ where, include: productInclude, orderBy: [{ createdAt: "desc" }, { id: "desc" }], skip: (q.page - 1) * q.limit, take: q.limit }),
    prisma.product.count({ where }),
  ]);
  return { products: await present(products, { owner: true, store }), total, page: q.page, pageSize: q.limit };
}
