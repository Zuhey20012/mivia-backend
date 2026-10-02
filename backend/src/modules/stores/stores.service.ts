import { prisma } from "../../lib/prisma";
import { StoreCategory } from "@prisma/client";
import { ApiError } from "../../lib/errors";
import { isOwnImageUrl, mediaConfigured } from "../../lib/cloudinary";
import { haversineKm, estimateDelivery } from "../../utils/distance";
import { deliveryFeeForDistance } from "../../utils/pricing";
import { priceInfoFor, presentProduct, productInclude } from "../products/pricing";
import { followInfo } from "../drops/social";

/** Trader information shoppers are entitled to see (DSA Art. 30, Omnibus Art. 6a CRD). */
const publicStoreFields = {
  id: true, name: true, description: true, category: true,
  logoUrl: true, bannerUrl: true, isHomeBased: true, isEcoFriendly: true,
  isVerified: true, address: true, latitude: true, longitude: true,
  rating: true, totalReviews: true, sellerType: true, businessId: true, prepMinutes: true,
} as const;

export function deliveryInfo(store: { latitude: number | null; longitude: number | null; prepMinutes?: number }, lat: number | null, lng: number | null) {
  let km: number | null = null;
  if (lat !== null && lng !== null && Number.isFinite(lat) && Number.isFinite(lng) && store.latitude !== null && store.longitude !== null) {
    km = haversineKm(lat, lng, store.latitude, store.longitude);
  }
  const eta = km === null ? null : estimateDelivery(km, store.prepMinutes ?? 10);
  return {
    distanceKm: km === null ? null : Number(km.toFixed(1)),
    etaMinutes: eta?.etaMinutes ?? null,
    etaMaxMinutes: eta?.etaMaxMinutes ?? null,
    // Same formula as checkout, so the advertised fee is what gets charged
    deliveryFeeCents: deliveryFeeForDistance(km),
  };
}

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
    prisma.store.findMany({ where, skip, take: limit, select: publicStoreFields, orderBy: [{ rating: "desc" }] }),
    prisma.store.count({ where }),
  ]);

  const userLat = query.lat ? Number(query.lat) : null;
  const userLng = query.lng ? Number(query.lng) : null;
  const enriched = stores.map((s) => ({ ...s, ...deliveryInfo(s, userLat, userLng) }));

  if (userLat !== null && userLng !== null) {
    enriched.sort((a, b) => {
      if (a.distanceKm === null) return 1;
      if (b.distanceKm === null) return -1;
      return a.distanceKm - b.distanceKm;
    });
  }

  return { stores: enriched, total, page, limit, pages: Math.ceil(total / limit) };
}

export async function getStoreById(id: number, viewerId?: number, lat: number | null = null, lng: number | null = null) {
  const store = await prisma.store.findUnique({
    where: { id },
    select: {
      ...publicStoreFields,
      ownerId: true,
      products: { where: { isAvailable: true }, take: 60, include: productInclude, orderBy: [{ isFeatured: "desc" }, { createdAt: "desc" }] },
    },
  });
  // Unverified stores are only visible to their owner
  if (!store || (!store.isVerified && store.ownerId !== viewerId)) throw new ApiError("Store not found", 404);
  const { ownerId, products, ...publicStore } = store;
  const [info, follow] = await Promise.all([priceInfoFor(products), followInfo(id, viewerId)]);
  return {
    ...publicStore,
    ...follow,
    ...deliveryInfo(publicStore, lat, lng),
    products: products.map((p) => presentProduct(p, info.get(p.id))),
  };
}

export async function getMyStore(ownerId: number) {
  const store = await prisma.store.findUnique({
    where: { ownerId },
    include: { products: { include: productInclude, orderBy: { createdAt: "desc" } } },
  });
  if (!store) return null;
  const info = await priceInfoFor(store.products);
  return { ...store, products: store.products.map((p) => presentProduct(p, info.get(p.id), { owner: true })) };
}

function assertOwnStoreImages(data: { logoUrl?: string; bannerUrl?: string }, storeId: number | null) {
  if (!mediaConfigured()) return;
  for (const url of [data.logoUrl, data.bannerUrl]) {
    if (url && (storeId === null || !isOwnImageUrl(url, `malvoya/stores/s${storeId}/`))) {
      throw new ApiError("Add store pictures with the app's photo picker", 400);
    }
  }
}

export async function createStore(ownerId: number, data: any) {
  const existing = await prisma.store.findUnique({ where: { ownerId } });
  if (existing) {
    // A reviewed store cannot relabel itself (e.g. business → private) without a new review
    const { sellerType, businessId, ...rest } = data;
    assertOwnStoreImages(rest, existing.id);
    return prisma.store.update({
      where: { ownerId },
      data: existing.isVerified ? rest : { ...rest, ...(sellerType ? { sellerType } : {}), ...(businessId ? { businessId } : {}) },
    });
  }
  const { logoUrl, bannerUrl, ...fields } = data; // pictures can only be added once the store exists
  // New stores start unverified and are reviewed by an admin before going live.
  return prisma.store.create({ data: { ...fields, ownerId, isVerified: false } });
}

export async function updateStore(id: number, ownerId: number, data: any) {
  const store = await prisma.store.findUnique({ where: { id } });
  if (!store) throw new ApiError("Store not found", 404);
  if (store.ownerId !== ownerId) throw new ApiError("Forbidden", 403);
  assertOwnStoreImages(data, id);
  return prisma.store.update({ where: { id }, data });
}
