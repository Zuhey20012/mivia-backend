import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { isOwnImageUrl, mediaConfigured } from "../../lib/cloudinary";
import { priceInfoFor, presentProduct, productInclude, recordPrice } from "./pricing";

type VariantInput = { id?: number; size?: string; color?: string; sku?: string; stock: number; priceAdjustCents: number };

const publicStoreSelect = {
  id: true, name: true, logoUrl: true, rating: true, totalReviews: true, sellerType: true,
  businessId: true, address: true, isVerified: true,
} as const;

async function present<T extends Parameters<typeof presentProduct>[0]>(products: T[], opts: { owner?: boolean } = {}) {
  const info = await priceInfoFor(products);
  return products.map((p) => presentProduct(p, info.get(p.id), opts));
}

/** Photos must be uploads into this store's own folder (when uploads are switched on). */
function assertOwnImages(images: string[] | undefined, storeId: number) {
  if (!images?.length || !mediaConfigured()) return;
  const bad = images.find((url) => !isOwnImageUrl(url, `malvoya/products/s${storeId}/`));
  if (bad) throw new ApiError("Add photos with the app's photo picker", 400);
}

export async function getProductsByStore(storeId: number, query: Record<string, string>, viewerId?: number) {
  const page  = Math.max(1, Number(query.page || 1));
  const limit = Math.min(50, Math.max(1, Number(query.limit || 20)));
  const store = await prisma.store.findUnique({ where: { id: storeId }, select: { isVerified: true, ownerId: true } });
  const isOwner = !!store && store.ownerId === viewerId;
  if (!store || (!store.isVerified && !isOwner)) return { products: [], total: 0, page, limit };
  // Owners also see their hidden products so they can re-enable them
  const where: Prisma.ProductWhereInput = isOwner ? { storeId } : { storeId, isAvailable: true };

  if (query.canBeSold)     where.canBeSold     = query.canBeSold === "true";
  if (query.canBeRented)   where.canBeRented   = query.canBeRented === "true";
  if (query.isEcoFriendly) where.isEcoFriendly = query.isEcoFriendly === "true";
  if (query.isSecondHand)  where.isSecondHand  = query.isSecondHand === "true";
  if (query.condition)     where.condition     = query.condition as any;
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
  return { products: await present(products, { owner: isOwner }), total, page, limit };
}

export async function getProductById(id: number, viewerId?: number) {
  const product = await prisma.product.findFirst({
    where: { id },
    include: { ...productInclude, store: { select: { ...publicStoreSelect, ownerId: true } } },
  });
  const isOwner = !!product && product.store.ownerId === viewerId;
  if (!product || (!product.store.isVerified && !isOwner)) throw new ApiError("Product not found", 404);
  const { ownerId, ...store } = product.store;
  const [presented] = await present([{ ...product, store }], { owner: isOwner });
  const favorite = viewerId
    ? !!(await prisma.favorite.findUnique({ where: { userId_productId: { userId: viewerId, productId: id } } }))
    : false;
  return { ...presented, isFavorite: favorite };
}

/** Catalogue search across all verified stores, with size/colour/price filters. */
export async function searchProducts(q: {
  q?: string; category?: string; size?: string; color?: string; condition?: string; secondHand?: string;
  eco?: string; handmade?: string; storeId?: number;
  minPrice?: number; maxPrice?: number; sort: string; page: number; limit: number;
}) {
  const and: Prisma.ProductWhereInput[] = [{ isAvailable: true, canBeSold: true, store: { isVerified: true } }];
  if (q.q) {
    const term = q.q;
    and.push({
      OR: [
        { name: { contains: term, mode: "insensitive" } },
        { description: { contains: term, mode: "insensitive" } },
        { category: { contains: term, mode: "insensitive" } },
        { tags: { has: term.toLowerCase() } },
        { store: { name: { contains: term, mode: "insensitive" } } },
      ],
    });
  }
  if (q.category) and.push({ category: { equals: q.category, mode: "insensitive" } });
  if (q.condition) and.push({ condition: q.condition as any });
  if (q.secondHand) and.push({ isSecondHand: q.secondHand === "true" });
  if (q.eco) and.push({ isEcoFriendly: true });
  if (q.handmade) and.push({ isHandmade: true });
  if (q.storeId) and.push({ storeId: q.storeId });
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
  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where, orderBy, skip: (q.page - 1) * q.limit, take: q.limit,
      include: { ...productInclude, store: { select: publicStoreSelect } },
    }),
    prisma.product.count({ where }),
  ]);
  return { products: await present(products), total, page: q.page, limit: q.limit };
}

async function storeForOwner(ownerId: number) {
  const store = await prisma.store.findUnique({ where: { ownerId } });
  if (!store) throw new ApiError("Create your store first", 404);
  return store;
}

export async function createProduct(ownerId: number, data: any) {
  const store = await storeForOwner(ownerId);
  assertOwnImages(data.images, store.id);
  const { variants, ...productData } = data as { variants: VariantInput[] } & Record<string, any>;
  const clean = variants.map(({ id, ...v }) => v);
  // With options, the product's stock is the sum of its options' stock
  const stockQuantity = clean.length ? clean.reduce((s, v) => s + v.stock, 0) : productData.stockQuantity;

  const created = await prisma.$transaction(async (tx) => {
    const product = await tx.product.create({
      data: {
        ...productData, stockQuantity, storeId: store.id,
        tags: (productData.tags ?? []).map((t: string) => t.toLowerCase()),
        variants: clean.length ? { createMany: { data: clean } } : undefined,
      } as Prisma.ProductUncheckedCreateInput,
      include: productInclude,
    });
    await recordPrice(tx, product.id, product.salePriceCents);
    return product;
  });
  const [presented] = await present([created], { owner: true });
  return presented;
}

export async function updateProduct(id: number, ownerId: number, data: any) {
  const product = await prisma.product.findUnique({ where: { id }, include: { store: true, variants: true } });
  if (!product) throw new ApiError("Product not found", 404);
  if (product.store.ownerId !== ownerId) throw new ApiError("Forbidden", 403);
  assertOwnImages(data.images, product.storeId);

  const { variants, ...productData } = data as { variants?: VariantInput[] } & Record<string, any>;
  if (productData.tags) productData.tags = productData.tags.map((t: string) => t.toLowerCase());

  const updated = await prisma.$transaction(async (tx) => {
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

    const next = await tx.product.update({ where: { id }, data: productData, include: productInclude });
    if (productData.salePriceCents !== undefined && productData.salePriceCents !== product.salePriceCents) {
      await recordPrice(tx, id, productData.salePriceCents);
    }
    return next;
  });
  const [presented] = await present([updated], { owner: true });
  return presented;
}

export async function deleteProduct(id: number, ownerId: number) {
  const product = await prisma.product.findUnique({ where: { id }, include: { store: true } });
  if (!product) throw new ApiError("Product not found", 404);
  if (product.store.ownerId !== ownerId) throw new ApiError("Forbidden", 403);
  // Hidden, not deleted: past orders still point at it
  await prisma.product.update({ where: { id }, data: { isAvailable: false } });
}
