import { prisma } from "../../lib/prisma";
import { StoreCategory } from "@prisma/client";
import { haversineKm, calcEtaMinutes } from "../../utils/distance";

export async function getStores(query: {
  category?: string; isHomeBased?: string; search?: string; page: string; limit: string;
  lat?: string; lng?: string;
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

  const userLat = query.lat ? Number(query.lat) : null;
  const userLng = query.lng ? Number(query.lng) : null;

  const enrichedStores = stores.map((s) => {
    let distanceKm: number | null = null;
    let etaMinutes: number = 30;
    let deliveryFeeCents: number = 299;

    if (userLat !== null && userLng !== null && !isNaN(userLat) && !isNaN(userLng) && s.latitude && s.longitude) {
      const km = haversineKm(userLat, userLng, s.latitude, s.longitude);
      distanceKm = Number(km.toFixed(1));
      etaMinutes = calcEtaMinutes(km);
      if (km <= 1.5) {
        deliveryFeeCents = 190; // €1.90 base
      } else {
        deliveryFeeCents = Math.min(690, 190 + Math.round((km - 1.5) * 50));
      }
    }

    return {
      ...s,
      distanceKm,
      etaMinutes,
      deliveryFeeCents,
      isOpen: true,
    };
  });

  if (userLat !== null && userLng !== null) {
    enrichedStores.sort((a, b) => {
      if (a.distanceKm === null) return 1;
      if (b.distanceKm === null) return -1;
      return a.distanceKm - b.distanceKm;
    });
  }

  return { stores: enrichedStores, total, page, limit, pages: Math.ceil(total / limit) };
}

export async function getStoreById(id: number) {
  return prisma.store.findUniqueOrThrow({
    where: { id },
    include: {
      products: {
        where: { isAvailable: true },
        take: 50,
        include: {
          variants: true,
        },
        orderBy: { isFeatured: "desc" },
      },
    },
  });
}

export async function createStore(ownerId: number, data: any) {
  const existing = await prisma.store.findUnique({ where: { ownerId } });
  if (existing) {
    return prisma.store.update({ where: { ownerId }, data });
  }
  await prisma.user.update({ where: { id: ownerId }, data: { role: "VENDOR" } });
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

