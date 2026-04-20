import { prisma } from "../../lib/prisma";

export async function getProductsByStore(storeId: number, query: Record<string, string>) {
  const page  = Math.max(1, Number(query.page || 1));
  const limit = Math.min(50, Math.max(1, Number(query.limit || 20)));
  const where: any = { storeId, isAvailable: true };

  if (query.canBeSold)     where.canBeSold     = query.canBeSold === "true";
  if (query.canBeRented)   where.canBeRented   = query.canBeRented === "true";
  if (query.isEcoFriendly) where.isEcoFriendly = query.isEcoFriendly === "true";
  if (query.isSecondHand)  where.isSecondHand  = query.isSecondHand === "true";
  if (query.condition)     where.condition     = query.condition;
  if (query.search)        where.name          = { contains: query.search, mode: "insensitive" };
  if (query.minPrice || query.maxPrice) {
    where.salePriceCents = {};
    if (query.minPrice) where.salePriceCents.gte = Number(query.minPrice);
    if (query.maxPrice) where.salePriceCents.lte = Number(query.maxPrice);
  }

  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where, skip: (page - 1) * limit, take: limit,
      include: { variants: true },
      orderBy: [{ isFeatured: "desc" }, { createdAt: "desc" }],
    }),
    prisma.product.count({ where }),
  ]);
  return { products, total, page, limit };
}

export async function getProductById(id: number) {
  return prisma.product.findUniqueOrThrow({
    where: { id },
    include: { variants: true, store: { select: { id: true, name: true, logoUrl: true, rating: true } } },
  });
}

export async function createProduct(storeId: number, data: any) {
  const { variants, ...productData } = data;
  return prisma.product.create({
    data: {
      ...productData, storeId,
      variants: variants?.length ? { createMany: { data: variants } } : undefined,
    },
    include: { variants: true },
  });
}

export async function updateProduct(id: number, vendorId: number, data: any) {
  const product = await prisma.product.findUniqueOrThrow({ where: { id }, include: { store: true } });
  if (product.store.ownerId !== vendorId) throw new Error("Forbidden");
  const { variants, ...productData } = data;
  return prisma.product.update({ where: { id }, data: productData, include: { variants: true } });
}

export async function deleteProduct(id: number, vendorId: number) {
  const product = await prisma.product.findUniqueOrThrow({ where: { id }, include: { store: true } });
  if (product.store.ownerId !== vendorId) throw new Error("Forbidden");
  await prisma.product.update({ where: { id }, data: { isAvailable: false } });
}

export async function addProductImages(id: number, vendorId: number, imageUrls: string[]) {
  const product = await prisma.product.findUniqueOrThrow({ where: { id }, include: { store: true } });
  if (product.store.ownerId !== vendorId) throw new Error("Forbidden");
  const images = [...product.images, ...imageUrls];
  return prisma.product.update({ where: { id }, data: { images } });
}
