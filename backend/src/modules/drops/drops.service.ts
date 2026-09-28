import crypto from "crypto";
import pino from "pino";
import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { env } from "../../config/env";
import { destroyResource, getResource, imageUrl, videoHlsUrl, videoMp4Url, videoPosterUrl } from "../../lib/cloudinary";
import { pushToUser } from "../../lib/push";
import { sendEmail, escapeHtml } from "../../services/notificationDeliveryService";
import { priceInfoFor, presentProduct } from "../products/pricing";
import { deliveryInfo } from "../stores/stores.service";
import { describe, UploadProof, verifyOwnedUpload } from "../media/media.service";

const logger = pino({ name: "drops" });

type Viewer = { id: number; role: string } | undefined;

const MAX_VIDEO_SECONDS = 90;
const MAX_DROPS_PER_DAY = 20;
const FEED_WINDOW_DAYS = 60;
const AUTO_HIDE_REPORTS = 3;

export const REPORT_REASONS = [
  "ILLEGAL_PRODUCT", "COUNTERFEIT", "SCAM", "NUDITY", "VIOLENCE", "HATE", "HARASSMENT", "IP_INFRINGEMENT", "MINOR_SAFETY", "OTHER",
] as const;

// ─── Presentation ───────────────────────────────────────────────────────────

const dropInclude = {
  store: { select: { id: true, name: true, logoUrl: true, rating: true, totalReviews: true, sellerType: true, latitude: true, longitude: true, prepMinutes: true, ownerId: true } },
  product: { include: { variants: { orderBy: { id: "asc" as const } } } },
} satisfies Prisma.DropInclude;

type DropRow = Prisma.DropGetPayload<{ include: typeof dropInclude }>;

function media(drop: { mediaKind: string; mediaPublicId: string }) {
  if (drop.mediaKind === "VIDEO") {
    return { hls: videoHlsUrl(drop.mediaPublicId), mp4: videoMp4Url(drop.mediaPublicId), poster: videoPosterUrl(drop.mediaPublicId), image: null };
  }
  const url = imageUrl(drop.mediaPublicId, "c_limit,w_1080,q_auto,f_auto");
  return { hls: null, mp4: null, poster: url, image: url };
}

async function presentDrops(rows: DropRow[], viewer: Viewer, loc: { lat: number | null; lng: number | null }, reasons?: Map<number, string>) {
  const [liked, info] = await Promise.all([
    viewer && rows.length
      ? prisma.dropLike.findMany({ where: { userId: viewer.id, dropId: { in: rows.map((r) => r.id) } }, select: { dropId: true } })
      : Promise.resolve([]),
    priceInfoFor(rows.map((r) => r.product)),
  ]);
  const likedSet = new Set(liked.map((l) => l.dropId));
  return rows.map((d) => {
    const { ownerId, latitude, longitude, prepMinutes, ...store } = d.store;
    return {
      id: d.id,
      kind: d.mediaKind,
      caption: d.caption,
      media: media(d),
      durationSec: d.durationSec,
      width: d.width,
      height: d.height,
      status: d.status,
      likeCount: d.likeCount,
      viewCount: d.viewCount,
      shareCount: d.shareCount,
      likedByMe: likedSet.has(d.id),
      publishedAt: d.publishedAt,
      shareUrl: `${env.publicApiUrl}/d/${d.id}`,
      reason: reasons?.get(d.id) ?? null,
      store: { ...store, ...deliveryInfo({ latitude, longitude, prepMinutes }, loc.lat, loc.lng) },
      product: presentProduct(d.product, info.get(d.product.id)),
    };
  });
}

// ─── Feed ranking ───────────────────────────────────────────────────────────

/**
 * Main parameters of the recommender (published in the Terms, DSA Art. 27):
 * freshness, how much people engage with the drop, distance of the store and the store's rating.
 * Nothing is inferred from personal profiling; "Latest" mode is purely chronological.
 */
export const RANKING_EXPLANATION = {
  forYou: [
    "How new the drop is (newer ranks higher, halving every 2 days)",
    "How people respond to it: likes, shares and views watched to the end, relative to all views",
    "How close the store is to your delivery location, when you share it (up to 10 km)",
    "The store's customer rating",
  ],
  latest: ["Newest drops first, nothing else"],
  personalProfiling: false,
};

type Candidate = {
  id: number; publishedAt: Date | null; likeCount: number; viewCount: number; shareCount: number; completeCount: number;
  store: { rating: number; totalReviews: number; latitude: number | null; longitude: number | null };
};

function scoreDrop(c: Candidate, now: number, loc: { lat: number | null; lng: number | null }) {
  const ageHours = Math.max(0, (now - (c.publishedAt?.getTime() ?? now)) / 3_600_000);
  const fresh = Math.pow(0.5, ageHours / 48);
  const engagement = Math.min(1, (c.likeCount + 2 * c.completeCount + 3 * c.shareCount) / (c.viewCount + 10));
  let proximity = 0.5; // unknown location: neutral
  let km: number | null = null;
  if (loc.lat !== null && loc.lng !== null && c.store.latitude !== null && c.store.longitude !== null) {
    km = deliveryInfo(c.store, loc.lat, loc.lng).distanceKm;
    proximity = km === null ? 0.5 : Math.max(0, 1 - km / 10);
  }
  const quality = c.store.totalReviews > 0 ? c.store.rating / 5 : 0.6;
  const parts = { fresh: 0.45 * fresh, engagement: 0.3 * engagement, proximity: 0.15 * proximity, quality: 0.1 * quality };
  const score = parts.fresh + parts.engagement + parts.proximity + parts.quality;

  // The strongest factor becomes the "why am I seeing this" label
  let reason = "New from a store on Malvoya";
  if (km !== null && km <= 3 && parts.proximity >= parts.engagement) reason = `Near you · ${km.toFixed(1)} km`;
  else if (parts.engagement > parts.fresh && c.viewCount >= 20) reason = "Popular right now";
  else if (ageHours < 24) reason = "Just dropped";
  return { score, reason };
}

type Cursor = { t: number; o: number };
const encodeCursor = (c: Cursor) => Buffer.from(JSON.stringify(c)).toString("base64url");
function decodeCursor(raw?: string): Cursor | null {
  if (!raw) return null;
  try {
    const c = JSON.parse(Buffer.from(raw, "base64url").toString("utf8"));
    return Number.isFinite(c.t) && Number.isInteger(c.o) && c.o >= 0 && c.o < 5000 ? c : null;
  } catch {
    return null;
  }
}

/**
 * The ranking is computed against a snapshot time kept in the cursor, so paging through the
 * feed is stable: nothing jumps or repeats while you scroll.
 */
export async function getFeed(opts: { mode: "foryou" | "latest"; cursor?: string; limit: number; lat: number | null; lng: number | null; storeId?: number }, viewer: Viewer) {
  const snap = decodeCursor(opts.cursor) ?? { t: Date.now(), o: 0 };
  const where: Prisma.DropWhereInput = {
    status: "READY",
    publishedAt: { lte: new Date(snap.t), gte: new Date(snap.t - FEED_WINDOW_DAYS * 86_400_000) },
    store: { isVerified: true },
    product: { isAvailable: true },
    ...(opts.storeId ? { storeId: opts.storeId } : {}),
  };
  const candidates = await prisma.drop.findMany({
    where,
    select: {
      id: true, publishedAt: true, likeCount: true, viewCount: true, shareCount: true, completeCount: true,
      store: { select: { rating: true, totalReviews: true, latitude: true, longitude: true } },
    },
    orderBy: [{ publishedAt: "desc" }, { id: "desc" }],
    take: 1000,
  });

  const reasons = new Map<number, string>();
  let ordered: number[];
  if (opts.mode === "latest" || opts.storeId) {
    ordered = candidates.map((c) => c.id);
  } else {
    const scored = candidates.map((c) => {
      const s = scoreDrop(c, snap.t, opts);
      reasons.set(c.id, s.reason);
      return { id: c.id, score: s.score };
    });
    scored.sort((a, b) => b.score - a.score || b.id - a.id);
    ordered = scored.map((s) => s.id);
  }

  const pageIds = ordered.slice(snap.o, snap.o + opts.limit);
  const rows = pageIds.length ? await prisma.drop.findMany({ where: { id: { in: pageIds } }, include: dropInclude }) : [];
  const byId = new Map(rows.map((r) => [r.id, r]));
  const page = pageIds.map((id) => byId.get(id)).filter((r): r is DropRow => !!r);
  const nextOffset = snap.o + opts.limit;

  return {
    drops: await presentDrops(page, viewer, opts, reasons),
    nextCursor: nextOffset < ordered.length ? encodeCursor({ t: snap.t, o: nextOffset }) : null,
  };
}

export async function getDrop(id: number, viewer: Viewer, loc: { lat: number | null; lng: number | null }) {
  const drop = await prisma.drop.findUnique({ where: { id }, include: dropInclude });
  const isOwner = !!drop && viewer?.id === drop.store.ownerId;
  if (!drop || ((drop.status !== "READY" || !drop.product.isAvailable) && !isOwner && viewer?.role !== "ADMIN")) {
    throw new ApiError("This drop is not available", 404);
  }
  const [presented] = await presentDrops([drop], viewer, loc);
  return presented;
}

// ─── Engagement ─────────────────────────────────────────────────────────────

async function readyDrop(id: number) {
  const drop = await prisma.drop.findUnique({ where: { id }, select: { id: true, status: true, durationSec: true } });
  if (!drop || drop.status !== "READY") throw new ApiError("This drop is not available", 404);
  return drop;
}

export async function like(dropId: number, userId: number) {
  await readyDrop(dropId);
  try {
    await prisma.$transaction([
      prisma.dropLike.create({ data: { dropId, userId } }),
      prisma.drop.update({ where: { id: dropId }, data: { likeCount: { increment: 1 } } }),
    ]);
  } catch (e: any) {
    if (e?.code !== "P2002") throw e; // already liked
  }
  return likeState(dropId, true);
}

export async function unlike(dropId: number, userId: number) {
  const removed = await prisma.dropLike.deleteMany({ where: { dropId, userId } });
  if (removed.count) await prisma.drop.updateMany({ where: { id: dropId, likeCount: { gt: 0 } }, data: { likeCount: { decrement: 1 } } });
  return likeState(dropId, false);
}

async function likeState(dropId: number, liked: boolean) {
  const d = await prisma.drop.findUnique({ where: { id: dropId }, select: { likeCount: true } });
  return { liked, likeCount: d?.likeCount ?? 0 };
}

/**
 * A view counts once per viewer per day; watch time and completion are recorded for ranking.
 * Anonymous viewers are identified by a hash of an install id the app generates (never an ad id).
 */
export async function recordView(dropId: number, viewer: Viewer, input: { installId?: string; watchedSec: number; completed: boolean; ip?: string }) {
  const drop = await readyDrop(dropId);
  const viewerKey = viewer
    ? `u:${viewer.id}`
    : input.installId
      ? `d:${crypto.createHash("sha256").update(input.installId).digest("hex").slice(0, 32)}`
      : `i:${crypto.createHash("sha256").update(`${input.ip ?? ""}:${new Date().toISOString().slice(0, 10)}`).digest("hex").slice(0, 32)}`;
  const day = new Date(new Date().toISOString().slice(0, 10));
  const watched = Math.max(0, Math.min(input.watchedSec, drop.durationSec ?? 60, 180));
  const key = { dropId_viewerKey_day: { dropId, viewerKey, day } };

  const existing = await prisma.dropView.findUnique({ where: key });
  if (!existing) {
    try {
      await prisma.$transaction([
        prisma.dropView.create({ data: { dropId, viewerKey, day, completed: input.completed } }),
        prisma.drop.update({
          where: { id: dropId },
          data: { viewCount: { increment: 1 }, watchSeconds: { increment: watched }, ...(input.completed ? { completeCount: { increment: 1 } } : {}) },
        }),
      ]);
      return { counted: true };
    } catch (e: any) {
      if (e?.code !== "P2002") throw e;
    }
  }
  if (input.completed) {
    const upgraded = await prisma.dropView.updateMany({ where: { dropId, viewerKey, day, completed: false }, data: { completed: true } });
    if (upgraded.count) await prisma.drop.update({ where: { id: dropId }, data: { completeCount: { increment: 1 } } });
  }
  return { counted: false };
}

export async function share(dropId: number) {
  await readyDrop(dropId);
  const d = await prisma.drop.update({ where: { id: dropId }, data: { shareCount: { increment: 1 } }, select: { shareCount: true } });
  return { shareCount: d.shareCount, shareUrl: `${env.publicApiUrl}/d/${dropId}` };
}

/** Notice-and-action (DSA Art. 16). Three independent reports hide the drop until a person reviews it. */
export async function report(dropId: number, reporterId: number | null, reason: string, details?: string) {
  const drop = await prisma.drop.findUnique({ where: { id: dropId }, select: { id: true, status: true } });
  if (!drop) throw new ApiError("Drop not found", 404);
  if (reporterId) {
    const dup = await prisma.dropReport.findFirst({ where: { dropId, reporterId, status: "OPEN" } });
    if (dup) return { received: true };
  }
  await prisma.dropReport.create({ data: { dropId, reporterId, reason, details: details?.slice(0, 1000) } });

  const distinct = await prisma.dropReport.groupBy({ by: ["reporterId"], where: { dropId, status: "OPEN", reporterId: { not: null } } });
  if (drop.status === "READY" && distinct.length >= AUTO_HIDE_REPORTS) {
    await prisma.drop.update({ where: { id: dropId }, data: { status: "REMOVED", removedReason: "AUTO: hidden while reports are reviewed" } });
    logger.warn({ dropId, reports: distinct.length }, "Drop auto-hidden pending review");
  }
  return { received: true };
}

// ─── Store side ─────────────────────────────────────────────────────────────

async function ownedStore(ownerId: number) {
  const store = await prisma.store.findUnique({ where: { ownerId }, select: { id: true, name: true } });
  if (!store) throw new ApiError("Create your store first", 409);
  return store;
}

export async function createDrop(actor: { id: number; role: string }, input: {
  productId: number; caption?: string; kind: "VIDEO" | "IMAGE"; upload: UploadProof;
}) {
  const store = await ownedStore(actor.id);
  const product = await prisma.product.findUnique({ where: { id: input.productId }, select: { storeId: true, isAvailable: true, canBeSold: true } });
  if (!product || product.storeId !== store.id) throw new ApiError("Choose one of your own products", 400);
  if (!product.isAvailable || !product.canBeSold) throw new ApiError("That product is not for sale right now", 400);

  const recent = await prisma.drop.count({ where: { storeId: store.id, createdAt: { gte: new Date(Date.now() - 86_400_000) } } });
  if (recent >= MAX_DROPS_PER_DAY) throw new ApiError(`You can post up to ${MAX_DROPS_PER_DAY} drops a day`, 429);

  const kind = input.kind === "VIDEO" ? "drop_video" : "drop_image";
  await verifyOwnedUpload(kind, actor, input.upload);
  const resource = await getResource(input.upload.publicId, input.kind === "VIDEO" ? "video" : "image");
  if (!resource) throw new ApiError("The upload was not found. Please try again.", 400);
  if (input.kind === "VIDEO" && (resource.duration ?? 0) > MAX_VIDEO_SECONDS) {
    destroyResource(input.upload.publicId, "video").catch(() => {});
    throw new ApiError(`Videos can be up to ${MAX_VIDEO_SECONDS} seconds`, 400);
  }

  const ready = input.kind === "IMAGE" || hlsReady(resource.derived);
  try {
    const drop = await prisma.drop.create({
      data: {
        storeId: store.id,
        productId: input.productId,
        caption: input.caption?.trim().slice(0, 300) || null,
        mediaKind: input.kind,
        mediaPublicId: input.upload.publicId,
        durationSec: resource.duration ?? null,
        width: resource.width ?? null,
        height: resource.height ?? null,
        status: ready ? "READY" : "PROCESSING",
        publishedAt: ready ? new Date() : null,
      },
      include: dropInclude,
    });
    const [presented] = await presentDrops([drop], actor, { lat: null, lng: null });
    return presented;
  } catch (e: any) {
    if (e?.code === "P2002") throw new ApiError("That video is already posted", 409);
    throw e;
  }
}

function hlsReady(derived?: { transformation: string }[]) {
  return !!derived?.some((d) => d.transformation.startsWith("sp_auto"));
}

export async function listMine(ownerId: number) {
  const store = await ownedStore(ownerId);
  const rows = await prisma.drop.findMany({
    where: { storeId: store.id, NOT: { status: "REMOVED", removedReason: "Deleted by store" } },
    include: dropInclude,
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  const presented = await presentDrops(rows, { id: ownerId, role: "VENDOR" }, { lat: null, lng: null });
  return presented.map((p, i) => ({
    ...p,
    completeCount: rows[i].completeCount,
    avgWatchSec: rows[i].viewCount ? Math.round((rows[i].watchSeconds / rows[i].viewCount) * 10) / 10 : 0,
    removedReason: rows[i].removedReason,
  }));
}

export async function deleteMine(ownerId: number, dropId: number) {
  const store = await ownedStore(ownerId);
  const drop = await prisma.drop.findUnique({ where: { id: dropId } });
  if (!drop || drop.storeId !== store.id) throw new ApiError("Drop not found", 404);
  await prisma.drop.update({ where: { id: dropId }, data: { status: "REMOVED", removedReason: "Deleted by store" } });
  destroyResource(drop.mediaPublicId, drop.mediaKind === "VIDEO" ? "video" : "image").catch(() => {});
}

// ─── Processing ─────────────────────────────────────────────────────────────

async function publish(dropId: number) {
  const updated = await prisma.drop.updateMany({ where: { id: dropId, status: "PROCESSING" }, data: { status: "READY", publishedAt: new Date() } });
  if (!updated.count) return;
  const drop = await prisma.drop.findUnique({ where: { id: dropId }, select: { store: { select: { ownerId: true } } } });
  if (drop) pushToUser(drop.store.ownerId, { title: "Your drop is live", body: "Shoppers can now see it in the Drops feed.", data: { type: "drop", dropId: String(dropId) } }).catch(() => {});
}

/** Called by the Cloudinary webhook when the streaming versions are ready (or failed). */
export async function onVideoProcessed(publicId: string, failed: boolean) {
  const drop = await prisma.drop.findUnique({ where: { mediaPublicId: publicId }, select: { id: true, status: true } });
  if (!drop || drop.status !== "PROCESSING") return;
  if (failed) {
    await prisma.drop.update({ where: { id: drop.id }, data: { status: "FAILED" } });
    return;
  }
  await publish(drop.id);
}

/** Safety net when a webhook is missed: ask Cloudinary directly. */
export async function checkProcessingDrops() {
  const pending = await prisma.drop.findMany({
    where: { status: "PROCESSING", createdAt: { lte: new Date(Date.now() - 60_000) } },
    select: { id: true, mediaPublicId: true, createdAt: true },
    take: 20,
  });
  for (const d of pending) {
    try {
      const resource = await getResource(d.mediaPublicId, "video");
      if (resource && hlsReady(resource.derived)) await publish(d.id);
      else if (Date.now() - d.createdAt.getTime() > 2 * 3_600_000) {
        await prisma.drop.update({ where: { id: d.id }, data: { status: "FAILED" } });
      }
    } catch (err: any) {
      logger.warn({ dropId: d.id, err: err?.message }, "Could not check video processing");
    }
  }
}

// ─── Moderation (admin) ─────────────────────────────────────────────────────

export async function adminList(status?: string) {
  const rows = await prisma.drop.findMany({
    where: status ? { status: status as any } : {},
    include: { ...dropInclude, _count: { select: { reports: { where: { status: "OPEN" } } } } },
    orderBy: { createdAt: "desc" },
    take: 200,
  });
  const presented = await presentDrops(rows, { id: 0, role: "ADMIN" }, { lat: null, lng: null });
  return presented.map((p, i) => ({ ...p, openReports: rows[i]._count.reports, removedReason: rows[i].removedReason }));
}

export async function adminReports(status = "OPEN") {
  return prisma.dropReport.findMany({
    where: { status: status as any },
    include: { drop: { select: { id: true, status: true, caption: true, mediaKind: true, mediaPublicId: true, store: { select: { id: true, name: true } } } } },
    orderBy: { createdAt: "asc" },
    take: 200,
  });
}

/**
 * Remove or restore a drop. Removal sends the store a statement of reasons (DSA Art. 17):
 * what was decided, why, and how to object.
 */
export async function moderate(dropId: number, adminId: number, action: "remove" | "restore", reason?: string) {
  const drop = await prisma.drop.findUnique({ where: { id: dropId }, include: { store: { include: { owner: { select: { id: true, email: true, name: true } } } } } });
  if (!drop) throw new ApiError("Drop not found", 404);

  if (action === "restore") {
    await prisma.$transaction([
      prisma.drop.update({ where: { id: dropId }, data: { status: "READY", removedReason: null, publishedAt: drop.publishedAt ?? new Date() } }),
      prisma.dropReport.updateMany({ where: { dropId, status: "OPEN" }, data: { status: "DISMISSED", resolvedById: adminId, resolvedAt: new Date() } }),
    ]);
    return { status: "READY" };
  }

  if (!reason || reason.trim().length < 10) throw new ApiError("Give the store a clear reason (at least 10 characters)");
  await prisma.$transaction([
    prisma.drop.update({ where: { id: dropId }, data: { status: "REMOVED", removedReason: reason.trim().slice(0, 500) } }),
    prisma.dropReport.updateMany({ where: { dropId, status: "OPEN" }, data: { status: "ACTIONED", resolvedById: adminId, resolvedAt: new Date() } }),
  ]);

  const owner = drop.store.owner;
  const text =
    `Your drop #${dropId} was removed from Malvoya.\n\nReason: ${reason.trim()}\n\n` +
    `This decision was made by a person on the Malvoya team after review. ` +
    `If you think it is wrong, reply to this email or write to sellers@malvoya.com within 6 months and we will look at it again.`;
  sendEmail(owner.email, "Malvoya – a drop was removed", `<p>${escapeHtml(text).replace(/\n/g, "<br>")}</p>`, text).catch(() => {});
  pushToUser(owner.id, { title: "A drop was removed", body: reason.trim().slice(0, 120), data: { type: "drop", dropId: String(dropId) } }).catch(() => {});
  return { status: "REMOVED" };
}

export async function resolveReport(reportId: number, adminId: number, status: "ACTIONED" | "DISMISSED") {
  const r = await prisma.dropReport.findUnique({ where: { id: reportId } });
  if (!r) throw new ApiError("Report not found", 404);
  return prisma.dropReport.update({ where: { id: reportId }, data: { status, resolvedById: adminId, resolvedAt: new Date() } });
}
