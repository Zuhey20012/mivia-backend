import crypto from "crypto";
import pino from "pino";
import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { env } from "../../config/env";
import { audioMp3Url, destroyResource, getResource, hlsReady, imageUrl, videoHlsUrl, videoMp4Url, videoPosterUrl } from "../../lib/cloudinary";
import { pushToUser, pushToUsers } from "../../lib/push";
import { sendDropRemovedEmail } from "../../services/notificationDeliveryService";
import { localeOfUser, t } from "../../lib/i18n";
import { priceInfoFor, presentProduct, productInclude } from "../products/pricing";
import { mayPersonalise } from "../../lib/minors";
import { deliveryInfo } from "../stores/stores.service";
import { describe, UploadProof, verifyOwnedUpload } from "../media/media.service";

const logger = pino({ name: "drops" });

type Viewer = { id: number; role: string } | undefined;

const MAX_VIDEO_SECONDS = 90;
const MAX_PHOTOS = 10; // photos in one photo drop (slideshow)
const MAX_AUDIO_SECONDS = 90; // the store's own sound track or voice-over
const MIN_TRIM_SECONDS = 3; // the shortest part of a video a store may keep
const MAX_DROPS_PER_DAY = 20;
const FEED_WINDOW_DAYS = 60;
const AUTO_HIDE_REPORTS = 3;

export const REPORT_REASONS = [
  "ILLEGAL_PRODUCT", "COUNTERFEIT", "SCAM", "NUDITY", "VIOLENCE", "HATE", "HARASSMENT", "IP_INFRINGEMENT", "MINOR_SAFETY", "OTHER",
] as const;

// ─── Presentation ───────────────────────────────────────────────────────────

const dropInclude = {
  store: { select: { id: true, name: true, logoUrl: true, rating: true, totalReviews: true, sellerType: true, latitude: true, longitude: true, prepMinutes: true, ownerId: true } },
  product: { include: productInclude },
  // A sound from Malvoya's library (2.14); an inactive sound keeps playing on the drops that already use it
  sound: { select: { id: true, title: true, artist: true, publicId: true, durationSec: true } },
} satisfies Prisma.DropInclude;

type DropRow = Prisma.DropGetPayload<{ include: typeof dropInclude }>;

type MediaFields = {
  mediaKind: string; mediaPublicId: string; extraImagePublicIds?: string[]; audioPublicId?: string | null; audioDurationSec?: number | null;
  sound?: { id: number; title: string; artist: string | null; publicId: string; durationSec: number } | null;
  soundMode?: string | null; trimStartSec?: number | null; trimEndSec?: number | null;
};

/**
 * The added sound of a drop: a library sound (clickable to its sound page in the app) or the store's own upload or
 * voice-over. `mode` says how it plays with a video's own sound (MIX = the video's sound quietly under it, REPLACE =
 * only the added sound); photos have no sound of their own, so it is null for them.
 */
function audioOf(drop: MediaFields) {
  const mode = drop.mediaKind === "VIDEO" ? (drop.soundMode === "REPLACE" ? "REPLACE" : "MIX") : null;
  if (drop.sound) {
    return {
      url: audioMp3Url(drop.sound.publicId), durationSec: drop.sound.durationSec,
      sound: { id: drop.sound.id, title: drop.sound.title, artist: drop.sound.artist }, mode,
    };
  }
  if (drop.audioPublicId) return { url: audioMp3Url(drop.audioPublicId), durationSec: drop.audioDurationSec ?? null, sound: null, mode };
  return null;
}

function media(drop: MediaFields) {
  const audio = audioOf(drop);
  if (drop.mediaKind === "VIDEO") {
    // A video plays with its own sound, optionally with an added sound (mixed or replacing it) and trimmed
    const trim = drop.trimStartSec != null && drop.trimEndSec != null ? { startSec: drop.trimStartSec, endSec: drop.trimEndSec } : null;
    return { hls: videoHlsUrl(drop.mediaPublicId), mp4: videoMp4Url(drop.mediaPublicId), poster: videoPosterUrl(drop.mediaPublicId), image: null, images: [], audio, trim };
  }
  // A photo drop: one or more photos (a slideshow, in the store's order) and an optional sound track
  const images = [drop.mediaPublicId, ...(drop.extraImagePublicIds ?? [])].map((id) => imageUrl(id, "c_limit,w_1080,q_auto,f_auto"));
  return { hls: null, mp4: null, poster: images[0], image: images[0], images, audio, trim: null };
}

/** Every Cloudinary file of a drop (taken down when the store deletes it). */
function destroyDropMedia(drop: { mediaKind: string; mediaPublicId: string; extraImagePublicIds: string[]; audioPublicId: string | null }) {
  destroyResource(drop.mediaPublicId, drop.mediaKind === "VIDEO" ? "video" : "image").catch(() => {});
  for (const id of drop.extraImagePublicIds) destroyResource(id, "image").catch(() => {});
  if (drop.audioPublicId) destroyResource(drop.audioPublicId, "video").catch(() => {});
}

async function presentDrops(rows: DropRow[], viewer: Viewer, loc: { lat: number | null; lng: number | null }, reasons?: Map<number, string>) {
  const [liked, info, follows, saved] = await Promise.all([
    viewer && rows.length
      ? prisma.dropLike.findMany({ where: { userId: viewer.id, dropId: { in: rows.map((r) => r.id) } }, select: { dropId: true } })
      : Promise.resolve([]),
    priceInfoFor(rows.map((r) => r.product)),
    viewer && rows.length
      ? prisma.storeFollow.findMany({ where: { userId: viewer.id, storeId: { in: [...new Set(rows.map((r) => r.storeId))] } }, select: { storeId: true } })
      : Promise.resolve([]),
    viewer && rows.length
      ? prisma.dropSave.findMany({ where: { userId: viewer.id, dropId: { in: rows.map((r) => r.id) } }, select: { dropId: true } })
      : Promise.resolve([]),
  ]);
  const likedSet = new Set(liked.map((l) => l.dropId));
  const savedSet = new Set(saved.map((l) => l.dropId));
  const followedSet = new Set(follows.map((f) => f.storeId));
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
      commentCount: d.commentCount,
      likedByMe: likedSet.has(d.id),
      saveCount: d.saveCount,
      savedByMe: savedSet.has(d.id),
      publishedAt: d.publishedAt,
      shareUrl: `${env.publicApiUrl}/d/${d.id}`,
      reason: reasons?.get(d.id) ?? null,
      store: { ...store, followedByMe: followedSet.has(d.storeId), ...deliveryInfo({ latitude, longitude, prepMinutes }, loc.lat, loc.lng) },
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
  following: ["Newest drops from the stores you follow, nothing else"],
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
export async function getFeed(opts: { mode: "foryou" | "latest" | "following"; cursor?: string; limit: number; lat: number | null; lng: number | null; storeId?: number; soundId?: number }, viewer: Viewer) {
  const snap = decodeCursor(opts.cursor) ?? { t: Date.now(), o: 0 };
  let followed: number[] | undefined;
  if (opts.mode === "following") {
    if (!viewer) throw new ApiError("Sign in to see drops from stores you follow", 401);
    followed = (await prisma.storeFollow.findMany({ where: { userId: viewer.id }, select: { storeId: true }, take: 2000 })).map((f) => f.storeId);
    if (!followed.length) return { drops: [], nextCursor: null };
  }
  const where: Prisma.DropWhereInput = {
    status: "READY",
    // A sound page lists every live drop using the sound; the feeds and store lists look back 60 days
    publishedAt: { lte: new Date(snap.t), ...(opts.soundId ? {} : { gte: new Date(snap.t - FEED_WINDOW_DAYS * 86_400_000) }) },
    store: { isVerified: true },
    product: { isAvailable: true },
    ...(opts.storeId ? { storeId: opts.storeId } : {}),
    ...(followed ? { storeId: { in: followed } } : {}),
    ...(opts.soundId ? { soundId: opts.soundId } : {}),
    // "Not interested" (2.14): never shown to that viewer again in any feed, store or sound list
    ...(viewer ? { hides: { none: { userId: viewer.id } } } : {}),
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

  // Under-18 guard (lib/minors.ts): the ranking below is not personal; if a personal signal is ever added to it,
  // it may only be used when this is true
  const personalise = opts.mode === "foryou" && (await mayPersonalise(viewer));
  void personalise;
  const reasons = new Map<number, string>();
  let ordered: number[];
  if (opts.mode !== "foryou" || opts.storeId || opts.soundId) {
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

// ─── Saves and "Not interested" (2.14) ──────────────────────────────────────

export async function save(dropId: number, userId: number) {
  await readyDrop(dropId);
  try {
    await prisma.$transaction([
      prisma.dropSave.create({ data: { dropId, userId } }),
      prisma.drop.update({ where: { id: dropId }, data: { saveCount: { increment: 1 } } }),
    ]);
  } catch (e: any) {
    if (e?.code !== "P2002") throw e; // already saved
  }
  return saveState(dropId, true);
}

export async function unsave(dropId: number, userId: number) {
  const removed = await prisma.dropSave.deleteMany({ where: { dropId, userId } });
  if (removed.count) await prisma.drop.updateMany({ where: { id: dropId, saveCount: { gt: 0 } }, data: { saveCount: { decrement: 1 } } });
  return saveState(dropId, false);
}

async function saveState(dropId: number, saved: boolean) {
  const d = await prisma.drop.findUnique({ where: { id: dropId }, select: { saveCount: true } });
  return { saved, saveCount: d?.saveCount ?? 0 };
}

/** The viewer's saved drops, newest save first; only drops that are still live. The cursor is the last save's id. */
export async function savedDrops(viewer: { id: number; role: string }, opts: { cursor?: string; limit: number }) {
  const before = opts.cursor && /^\d{1,10}$/.test(opts.cursor) ? Number(opts.cursor) : undefined;
  const saves = await prisma.dropSave.findMany({
    where: { userId: viewer.id, ...(before ? { id: { lt: before } } : {}), drop: { status: "READY", product: { isAvailable: true } } },
    select: { id: true, dropId: true },
    orderBy: { id: "desc" },
    take: opts.limit + 1,
  });
  const page = saves.slice(0, opts.limit);
  const rows = page.length ? await prisma.drop.findMany({ where: { id: { in: page.map((p) => p.dropId) } }, include: dropInclude }) : [];
  const byId = new Map(rows.map((r) => [r.id, r]));
  const ordered = page.map((p) => byId.get(p.dropId)).filter((r): r is DropRow => !!r);
  return {
    drops: await presentDrops(ordered, viewer, { lat: null, lng: null }),
    nextCursor: saves.length > opts.limit ? String(page[page.length - 1].id) : null,
  };
}

/** "Not interested": the drop disappears from this viewer's feeds, store pages and sound pages. */
export async function hide(dropId: number, userId: number) {
  const drop = await prisma.drop.findUnique({ where: { id: dropId }, select: { id: true } });
  if (!drop) throw new ApiError("This drop is not available", 404);
  await prisma.dropHide.upsert({ where: { userId_dropId: { userId, dropId } }, create: { userId, dropId }, update: {} });
  return { hidden: true };
}

export async function unhide(dropId: number, userId: number) {
  await prisma.dropHide.deleteMany({ where: { userId, dropId } });
  return { hidden: false };
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
  productId: number; caption?: string; kind: "VIDEO" | "IMAGE"; upload: UploadProof; rightsConfirmed: true;
  /** Photo drops: more photos after the first (in order) */
  images?: UploadProof[];
  /** An added sound (photo or video drops, 2.14): the store's own upload or voice-over, or a library sound */
  audio?: UploadProof; soundId?: number;
  /** Video drops with an added sound: mixed under the video's own sound (default) or replacing it */
  soundMode?: "MIX" | "REPLACE";
  /** Video drops: the part that plays (seconds), at least 3 s */
  trimStartSec?: number; trimEndSec?: number;
}) {
  const store = await ownedStore(actor.id);
  const product = await prisma.product.findUnique({ where: { id: input.productId }, select: { storeId: true, isAvailable: true, canBeSold: true } });
  if (!product || product.storeId !== store.id) throw new ApiError("Choose one of your own products", 400);
  if (!product.isAvailable || !product.canBeSold) throw new ApiError("That product is not for sale right now", 400);

  const recent = await prisma.drop.count({ where: { storeId: store.id, createdAt: { gte: new Date(Date.now() - 86_400_000) } } });
  if (recent >= MAX_DROPS_PER_DAY) throw new ApiError(`You can post up to ${MAX_DROPS_PER_DAY} drops a day`, 429);

  // Cheap checks first, before any upload is looked up
  if (input.soundId !== undefined && input.audio) throw new ApiError("Choose either a sound from the library or your own sound, not both", 400);
  const trimmed = input.trimStartSec !== undefined || input.trimEndSec !== undefined;
  if (trimmed && input.kind !== "VIDEO") throw new ApiError("Only videos can be trimmed", 400);
  if (input.kind === "VIDEO" && input.images?.length) throw new ApiError("Photos are for photo drops; a video drop is one video", 400);
  let soundId: number | null = null;
  if (input.soundId !== undefined) {
    const sound = await prisma.sound.findUnique({ where: { id: input.soundId }, select: { id: true, active: true } });
    if (!sound || !sound.active) throw new ApiError("That sound is no longer in the library. Choose another one.", 400);
    soundId = sound.id;
  }

  const kind = input.kind === "VIDEO" ? "drop_video" : "drop_image";
  await verifyOwnedUpload(kind, actor, input.upload);
  const resource = await getResource(input.upload.publicId, input.kind === "VIDEO" ? "video" : "image");
  if (!resource) throw new ApiError("The upload was not found. Please try again.", 400);
  if (input.kind === "VIDEO" && (resource.duration ?? 0) > MAX_VIDEO_SECONDS) {
    await destroyResource(input.upload.publicId, "video").catch(() => {}); // erased before answering
    throw new ApiError(`Videos can be up to ${MAX_VIDEO_SECONDS} seconds`, 400);
  }

  // The part of the video that plays: 0 ≤ start < end ≤ length, at least 3 s (playback trims; the file is not cut)
  let trimStartSec: number | null = null;
  let trimEndSec: number | null = null;
  if (trimmed) {
    const length = resource.duration ?? MAX_VIDEO_SECONDS;
    const start = Math.round((input.trimStartSec ?? 0) * 100) / 100;
    const end = Math.round((input.trimEndSec ?? length) * 100) / 100;
    if (start < 0 || end > length + 0.05 || start >= end) throw new ApiError("The trim must be within the video", 400);
    if (end - start < MIN_TRIM_SECONDS) throw new ApiError(`Keep at least ${MIN_TRIM_SECONDS} seconds of the video`, 400);
    trimStartSec = start;
    trimEndSec = Math.min(end, length);
  }

  // Photo drops: the extra photos and the sound track must be the store's own verified uploads
  const extra = input.images ?? [];
  if (1 + extra.length > MAX_PHOTOS) throw new ApiError(`A photo drop can have up to ${MAX_PHOTOS} photos`, 400);
  const extraIds = extra.map((u) => u.publicId);
  if (new Set([input.upload.publicId, ...extraIds]).size !== 1 + extraIds.length) throw new ApiError("The same photo is in the drop twice", 400);
  for (const u of extra) {
    await verifyOwnedUpload("drop_image", actor, u);
    if (!(await getResource(u.publicId, "image"))) throw new ApiError("A photo upload was not found. Please try again.", 400);
  }
  let audioDurationSec: number | null = null;
  if (input.audio) {
    await verifyOwnedUpload("drop_audio", actor, input.audio);
    const sound = await getResource(input.audio.publicId, "video");
    if (!sound) throw new ApiError("The sound upload was not found. Please try again.", 400);
    if ((sound.duration ?? 0) > MAX_AUDIO_SECONDS) {
      await destroyResource(input.audio.publicId, "video").catch(() => {}); // erased before answering
      throw new ApiError(`A sound track can be up to ${MAX_AUDIO_SECONDS} seconds`, 400);
    }
    audioDurationSec = sound.duration ?? null;
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
        rightsConfirmedAt: new Date(),
        extraImagePublicIds: extraIds,
        audioPublicId: input.audio?.publicId ?? null,
        audioDurationSec,
        soundId,
        // How the added sound plays with the video's own sound; photos have none
        soundMode: input.kind === "VIDEO" && (soundId || input.audio) ? (input.soundMode ?? "MIX") : null,
        trimStartSec,
        trimEndSec,
      },
      include: dropInclude,
    });
    if (ready) notifyFollowers(drop.id).catch(() => {});
    const [presented] = await presentDrops([drop], actor, { lat: null, lng: null });
    return presented;
  } catch (e: any) {
    if (e?.code === "P2002") throw new ApiError("That video is already posted", 409);
    throw e;
  }
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
  destroyDropMedia(drop);
}

// ─── Processing ─────────────────────────────────────────────────────────────

async function publish(dropId: number) {
  const updated = await prisma.drop.updateMany({ where: { id: dropId, status: "PROCESSING" }, data: { status: "READY", publishedAt: new Date() } });
  if (!updated.count) return;
  const drop = await prisma.drop.findUnique({ where: { id: dropId }, select: { store: { select: { ownerId: true } } } });
  if (drop) {
    pushToUser(drop.store.ownerId, {
      title: t("Your drop is live", "Droppisi on julkaistu"),
      body: t("Shoppers can now see it in the Drops feed.", "Ostajat näkevät sen nyt Drops-syötteessä."),
      data: { type: "drop", dropId: String(dropId) },
    }).catch(() => {});
  }
  notifyFollowers(dropId).catch(() => {});
}

const MAX_FOLLOWER_PUSHES = 2000;

/** A store's new drop reaches the people following the store (content they asked for). */
async function notifyFollowers(dropId: number) {
  const drop = await prisma.drop.findUnique({
    where: { id: dropId },
    select: { storeId: true, store: { select: { name: true, ownerId: true } }, product: { select: { name: true } } },
  });
  if (!drop) return;
  const followers = await prisma.storeFollow.findMany({ where: { storeId: drop.storeId }, select: { userId: true }, take: MAX_FOLLOWER_PUSHES });
  const ids = followers.map((f) => f.userId).filter((id) => id !== drop.store.ownerId);
  if (ids.length) {
    await pushToUsers(ids, { title: t(`New drop from ${drop.store.name}`, `Uusi drop: ${drop.store.name}`), body: drop.product.name, data: { type: "drop", dropId: String(dropId) } });
  }
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
  localeOfUser(owner.id).then((locale) => sendDropRemovedEmail(owner.email, dropId, reason.trim(), locale)).catch(() => {});
  pushToUser(owner.id, { title: t("A drop was removed", "Drop poistettiin"), body: reason.trim().slice(0, 120), data: { type: "drop", dropId: String(dropId) } }).catch(() => {});
  return { status: "REMOVED" };
}

export async function resolveReport(reportId: number, adminId: number, status: "ACTIONED" | "DISMISSED") {
  const r = await prisma.dropReport.findUnique({ where: { id: reportId } });
  if (!r) throw new ApiError("Report not found", 404);
  return prisma.dropReport.update({ where: { id: reportId }, data: { status, resolvedById: adminId, resolvedAt: new Date() } });
}
