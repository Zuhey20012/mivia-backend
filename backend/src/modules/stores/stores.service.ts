import { prisma } from "../../lib/prisma";
import { StoreCategory } from "@prisma/client";
import { haversineKm, calcEtaMinutes } from "../../utils/distance";
import { deliveryFeeForDistance } from "../../utils/pricing";

export async function getStores(query: {
  category?: string; isHomeBased?: string; search?: string; page: string; limit: string;
  lat?: string; lng?: string;
}) {
  const page  = Math.max(1, Number(query.page));
  const limit = Math.min(50, Math.max(1, Number(query.limit)));
  const skip  = (page - 1) * limit;

  // Only admin-verified stores are visible to shoppers
  const where: any = { isVerified: true };
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
    let km: number | null = null;
    if (userLat !== null && userLng !== null && !isNaN(userLat) && !isNaN(userLng) && s.latitude !== null && s.longitude !== null) {
      km = haversineKm(userLat, userLng, s.latitude, s.longitude);
    }

    return {
      ...s,
      distanceKm: km === null ? null : Number(km.toFixed(1)),
      etaMinutes: km === null ? null : calcEtaMinutes(km),
      // Same formula as checkout, so the advertised fee is what gets charged
      deliveryFeeCents: deliveryFeeForDistance(km),
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

export async function getStoreById(id: number, viewerId?: number) {
  const store = await prisma.store.findUniqueOrThrow({
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
  // Unverified stores are only visible to their owner
  if (!store.isVerified && store.ownerId !== viewerId) throw new Error("Not found");
  const { ownerId, ...publicStore } = store;
  return publicStore;
}

export async function getMyStore(ownerId: number) {
  return prisma.store.findUnique({
    where: { ownerId },
    include: { products: { include: { variants: true }, orderBy: { createdAt: "desc" } } },
  });
}

export async function createStore(ownerId: number, data: any) {
  const existing = await prisma.store.findUnique({ where: { ownerId } });
  if (existing) {
    return prisma.store.update({ where: { ownerId }, data });
  }
  // New stores start unverified and are reviewed by an admin before going live.
  return prisma.store.create({ data: { ...data, ownerId, isVerified: false } });
}

export async function updateStore(id: number, ownerId: number, data: any) {
  const store = await prisma.store.findUniqueOrThrow({ where: { id } });
  if (store.ownerId !== ownerId) throw new Error("Forbidden");
  return prisma.store.update({ where: { id }, data });
}


