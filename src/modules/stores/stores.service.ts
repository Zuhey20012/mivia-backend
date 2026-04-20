import { prisma } from "../../lib/prisma";
import { StoreCategory } from "@prisma/client";

export async function getStores(query: {
  category?: string; isHomeBased?: string; search?: string; page: string; limit: string;
}) {
  const page  = Math.max(1, Number(query.page));
  const limit = Math.min(50, Math.max(1, Number(query.limit)));
  const skip  = (page - 1) * limit;

  const where: any = {};
  if (query.category)    where.category    = query.category as StoreCategory;
  if (query.isHomeBased) where.isHomeBased = query.isHomeBased === "true";
  if (query.search)      where.name        = { contains: query.search, mode: "insensitive" };

  const [stores, total] = await Promise.all([
    prisma.store.findMany({
      where, skip, take: limit,
      select: {
        id: true, name: true, description: true, category: true,
        logoUrl: true, bannerUrl: true, isHomeBased: true, isEcoFriendly: true,
        isVerified: true, address: true, latitude: true, longitude: true,
        rating: true, totalReviews: true,
      },
      orderBy: [{ rating: "desc" }],
    }),
    prisma.store.count({ where }),
  ]);

  return { stores, total, page, limit, pages: Math.ceil(total / limit) };
}

export async function getStoreById(id: number) {
  return prisma.store.findUniqueOrThrow({
    where: { id },
    include: {
      products: {
        where: { isAvailable: true },
        take: 20,
        orderBy: { isFeatured: "desc" },
      },
    },
  });
}

export async function createStore(ownerId: number, data: any) {
  const existing = await prisma.store.findUnique({ where: { ownerId } });
  if (existing) throw new Error("You already have a store");
  return prisma.store.create({ data: { ...data, ownerId } });
}

export async function updateStore(id: number, ownerId: number, data: any) {
  const store = await prisma.store.findUniqueOrThrow({ where: { id } });
  if (store.ownerId !== ownerId) throw new Error("Forbidden");
  return prisma.store.update({ where: { id }, data });
}

export async function updateStoreLogo(id: number, ownerId: number, logoUrl: string) {
  const store = await prisma.store.findUniqueOrThrow({ where: { id } });
  if (store.ownerId !== ownerId) throw new Error("Forbidden");
  return prisma.store.update({ where: { id }, data: { logoUrl } });
}

