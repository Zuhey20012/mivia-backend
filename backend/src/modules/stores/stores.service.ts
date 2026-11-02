import { env } from "../../config/env";
import { t } from "../../lib/i18n";
import { cityOf, sellerInfo } from "./sellerInfo";
import { prisma } from "../../lib/prisma";
import { Prisma, StoreCategory } from "@prisma/client";
import { ApiError } from "../../lib/errors";
import { isOwnImageUrl, mediaConfigured } from "../../lib/cloudinary";
import { haversineKm, estimateDelivery } from "../../utils/distance";
import { deliveryFeeForDistance } from "../../utils/pricing";
import { priceInfoFor, presentProduct, productInclude } from "../products/pricing";
import { followInfo } from "../drops/social";
import { storeAvailability } from "../../utils/openingHours";
import { taxInfoComplete, taxRowSelect } from "../sellers/taxInfo";
import { businessCheckOf, runBusinessCheck } from "./businessCheck";
import { ownerPublishCheck } from "../catalog/productWrite";
import { safetyPledgeOf } from "../catalog/safety";

/** Trader information shoppers are entitled to see (DSA Art. 30, Omnibus Art. 6a CRD). */
const publicStoreFields = {
  id: true, name: true, description: true, category: true,
  logoUrl: true, bannerUrl: true, isHomeBased: true,
  isVerified: true, address: true, latitude: true, longitude: true,
  rating: true, totalReviews: true, sellerType: true, businessId: true, prepMinutes: true,
  acceptingOrders: true, openingHours: true,
} as const;

/**
 * An approved store changing its name, address or map position (2.17): shown in System → attention until an admin
 * approves it again; the store stays live meanwhile. Returns the changeReview payload for the app, or null.
 */
const REVIEWED_FIELDS = ["name", "address", "latitude", "longitude"] as const;
async function flagApprovedChange(existing: { id: number; isVerified: boolean; changedFields: string[] } & Record<string, unknown>, data: Record<string, unknown>) {
  if (!existing.isVerified) return null;
  const changed = REVIEWED_FIELDS.filter((f) => data[f] !== undefined && data[f] !== existing[f]);
  if (!changed.length) return null;
  const fields = [...new Set([...existing.changedFields, ...changed])];
  await prisma.store.update({ where: { id: existing.id }, data: { changedFields: fields, changedAfterApprovalAt: new Date() } });
  return {
    fields: changed,
    message: t("Thanks. Malvoya checks changes to a store's name and address; your store stays open meanwhile.",
      "Kiitos. Malvoya tarkistaa kaupan nimen ja osoitteen muutokset; kauppasi pysyy auki sillä välin."),
  };
}

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
    prisma.store.findMany({ where, skip, take: limit, select: publicStoreFields, orderBy: [{ rating: "desc" }, { id: "asc" }] }), // id: stable pages when ratings tie
    prisma.store.count({ where }),
  ]);

  const userLat = query.lat ? Number(query.lat) : null;
  const userLng = query.lng ? Number(query.lng) : null;
  // A private seller's address is never public (2.17): city only
  const enriched = stores.map((s) => ({
    ...s, ...(s.sellerType === "PRIVATE" ? { address: null } : {}), city: cityOf(s.address),
    ...deliveryInfo(s, userLat, userLng), ...storeAvailability(s),
  }));

  if (userLat !== null && userLng !== null) {
    enriched.sort((a, b) => {
      // Open stores first, then nearest
      if (a.openNow !== b.openNow) return a.openNow ? -1 : 1;
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
      ownerId: true, phone: true, email: true,
      // Newest first (isFeatured no longer orders anything: nothing sets it, 2.17)
      products: { where: { isAvailable: true, deletedAt: null }, take: 60, include: productInclude, orderBy: [{ createdAt: "desc" }, { id: "desc" }] },
    },
  });
  // Unverified stores are only visible to their owner
  if (!store || (!store.isVerified && store.ownerId !== viewerId)) throw new ApiError("Store not found", 404);
  const { ownerId, products, phone, email, ...publicStore } = store;
  const [info, follow, seller, mine] = await Promise.all([
    priceInfoFor(products), followInfo(id, viewerId), sellerInfo(store),
    viewerId ? prisma.storeFollow.findUnique({ where: { userId_storeId: { userId: viewerId, storeId: id } }, select: { muted: true } }) : null,
  ]);
  return {
    ...publicStore,
    ...follow,
    followMuted: !!mine?.muted,
    // Trader information (2.17): business sellers' legal name, address, phone and email; private sellers their city only
    ...seller,
    ...deliveryInfo(publicStore, lat, lng),
    ...storeAvailability(publicStore),
    products: products.map((p) => presentProduct(p, info.get(p.id))),
  };
}

export async function getMyStore(ownerId: number) {
  const store = await prisma.store.findUnique({
    where: { ownerId },
    // Large catalogues are paged with GET /stores/my/products; this keeps the newest 100
    include: { products: { where: { deletedAt: null }, include: productInclude, orderBy: { createdAt: "desc" }, take: 100 }, taxInfo: { select: taxRowSelect } },
  });
  if (!store) return null;
  const info = await priceInfoFor(store.products);
  const { taxInfo, ...rest } = store;
  return {
    ...rest,
    ...storeAvailability(store),
    // DAC7: whether the seller has given the identity and tax data Malvoya must report (GET/PUT /stores/my/tax-info)
    taxInfoComplete: taxInfoComplete(store, taxInfo),
    // PRH/YTJ check of the Y-tunnus (2.11): { required, businessId, verificationStatus, registeredName, registeredAt, checkedAt }
    businessCheck: businessCheckOf(store),
    // Product-safety pledge (GPSR Art. 22(10)(b), 2.12): { accepted, acceptedAt, version, currentVersion }
    safetyPledge: safetyPledgeOf(store),
    products: store.products.map((p) => ({ ...presentProduct(p, info.get(p.id), { owner: true }), publishCheck: ownerPublishCheck(p, store) })),
  };
}

function assertOwnStoreImages(data: { logoUrl?: string; bannerUrl?: string }, storeId: number | null) {
  if (!mediaConfigured()) return;
  for (const url of [data.logoUrl, data.bannerUrl]) {
    if (url && (storeId === null || !isOwnImageUrl(url, `malvoya/stores/s${storeId}/`))) {
      throw new ApiError("Add store pictures with the app's photo picker", 400);
    }
  }
}

/** null from the app means "no opening hours" (always open); Prisma needs DbNull for that. */
function withJsonNulls(data: any) {
  return data.openingHours === null ? { ...data, openingHours: Prisma.DbNull } : data;
}

export async function createStore(ownerId: number, input: any) {
  const data = withJsonNulls(input);
  const existing = await prisma.store.findUnique({ where: { ownerId } });
  if (existing) {
    // A reviewed store cannot relabel itself (e.g. business → private) without a new review
    const { sellerType, businessId, ...rest } = data;
    assertOwnStoreImages(rest, existing.id);
    const updated = await prisma.store.update({
      where: { ownerId },
      data: existing.isVerified ? rest : { ...rest, ...(sellerType ? { sellerType } : {}), ...(businessId ? { businessId } : {}) },
    });
    const changeReview = await flagApprovedChange(existing, rest);
    // A new or changed Y-tunnus is looked up in the PRH register in the background (it never approves anything)
    if (!existing.isVerified && businessId && (businessId !== existing.businessId || !existing.businessCheckedAt || existing.businessCheckStatus === "unavailable")) {
      runBusinessCheck(updated.id).catch(() => {});
    }
    return { ...updated, ...(changeReview ? { changeReview } : {}) };
  }
  const { logoUrl, bannerUrl, ...fields } = data; // pictures can only be added once the store exists
  // New stores start unverified and are reviewed by an admin before going live.
  // New stores get the default commission (DEFAULT_COMMISSION_RATE, 2.17); admins set per-store rates on Vendors
  const created = await prisma.store.create({ data: { ...fields, ownerId, isVerified: false, commissionRate: env.defaultCommissionRate } });
  if (created.businessId) runBusinessCheck(created.id).catch(() => {});
  return created;
}

export async function updateStore(id: number, ownerId: number, input: any) {
  const data = withJsonNulls(input);
  const store = await prisma.store.findUnique({ where: { id } });
  if (!store) throw new ApiError("Store not found", 404);
  if (store.ownerId !== ownerId) throw new ApiError("Forbidden", 403);
  assertOwnStoreImages(data, id);
  const updated = await prisma.store.update({ where: { id }, data });
  const changeReview = await flagApprovedChange(store, data);
  return { ...updated, ...(changeReview ? { changeReview } : {}) };
}
