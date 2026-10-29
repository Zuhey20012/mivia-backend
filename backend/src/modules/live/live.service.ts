import pino from "pino";
import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { ApiError } from "../../lib/errors";
import { pushToUser, pushToUsers } from "../../lib/push";
import { localeOfUser, t } from "../../lib/i18n";
import { closeRoom, liveConfigured, LiveOffError, participantToken, randomId } from "../../lib/livekit";
import { emitToLive } from "../../lib/socket";
import { priceInfoFor, presentProduct, productInclude } from "../products/pricing";
import { storesInReach } from "../catalog/categories";
import { blockedIdsFor } from "../me/safety";
import { followInfo } from "../drops/social";
import { sendLiveEndedEmail } from "../../services/notificationDeliveryService";

/**
 * Live shopping (since 2.15.0): a store goes live with its phone camera (LiveKit WebRTC, nothing recorded) and shows
 * 1–10 of its own products; signed-in viewers chat and send hearts over the socket (lib/socket.ts, room live:<id>).
 * The store sends a heartbeat every 30 s; the watchdog ends a live without one for 2 min, or after 4 h.
 */
const logger = pino({ name: "live" });

export const MAX_PRODUCTS = 10;
export const MAX_LIVES_PER_DAY = 10;
export const MAX_MESSAGE_LENGTH = 200;
const MESSAGES_PER_MINUTE = 10;
const HEARTBEAT_TIMEOUT_MS = 2 * 60_000;
const MAX_DURATION_MS = 4 * 3600_000;
const FOLLOWER_PUSH_GAP_MS = 6 * 3600_000;
const MAX_FOLLOWER_PUSHES = 2000;
const CHAT_KEEP_DAYS = 30;
/** Namespace of the per-store advisory lock that makes "one live at a time" race-free. */
const LIVE_LOCK_NS = 7342;

type Viewer = { id: number; role: string } | undefined;
type Actor = { id: number; role: string };

const storeSelect = { id: true, name: true, logoUrl: true, isVerified: true, ownerId: true, latitude: true, longitude: true } as const;
type LiveRow = Prisma.LiveStreamGetPayload<{ include: { store: { select: typeof storeSelect } } }>;

const PUBLIC_REASONS = new Set(["store", "timeout", "max_duration"]);
/** Viewers see why a live ended as a code; the admin's own words go only to the store (and the admin panel). */
const publicReason = (r: string | null) => (r === null ? null : PUBLIC_REASONS.has(r) ? r : "admin");

const firstName = (name: string) => name.trim().split(/\s+/)[0] || "Viewer";

/** First photo of the first featured product that has one, per live. */
async function covers(rows: { id: number; productIds: number[] }[]) {
  const ids = [...new Set(rows.flatMap((r) => r.productIds))];
  const products = ids.length ? await prisma.product.findMany({ where: { id: { in: ids } }, select: { id: true, images: true } }) : [];
  const byId = new Map(products.map((p) => [p.id, p.images[0] ?? null]));
  return new Map(rows.map((r) => [r.id, r.productIds.map((id) => byId.get(id)).find((u) => !!u) ?? null]));
}

function presentLive(row: LiveRow, cover: string | null) {
  const live = row.status === "LIVE";
  return {
    id: row.id,
    title: row.title,
    status: row.status,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    endedReason: publicReason(row.endedReason),
    viewers: live ? row.viewers : 0,
    likeCount: row.likeCount,
    store: { id: row.store.id, name: row.store.name, logoUrl: row.store.logoUrl },
    cover,
    pinnedProductId: row.pinnedProductId,
    productIds: row.productIds,
  };
}

async function presentMany(rows: LiveRow[]) {
  const c = await covers(rows);
  return rows.map((r) => presentLive(r, c.get(r.id) ?? null));
}

async function findLive(id: number) {
  return prisma.liveStream.findUnique({ where: { id }, include: { store: { select: storeSelect } } });
}

const isOwner = (row: { store: { ownerId: number } }, user: Viewer) => !!user && row.store.ownerId === user.id;
const isAdmin = (user: Viewer) => user?.role === "ADMIN";

/** Shoppers see lives of approved stores; the store itself and admins always. */
async function visibleLive(id: number, viewer: Viewer) {
  const row = await findLive(id);
  if (!row || (!row.store.isVerified && !isOwner(row, viewer) && !isAdmin(viewer))) throw new ApiError("Live not found", 404);
  return row;
}

async function ownedLive(id: number, user: Actor) {
  const row = await findLive(id);
  if (!row || !isOwner(row, user)) throw new ApiError("Live not found", 404);
  return row;
}

function endedError(row: { endedReason: string | null }) {
  const e = new ApiError("This live has ended", 409);
  e.extra = { code: "LIVE_ENDED", reason: publicReason(row.endedReason) };
  return e;
}

// ─── Going live (store) ─────────────────────────────────────────────────────

export async function startLive(user: Actor, input: { title: string; productIds: number[] }) {
  if (!liveConfigured()) throw new LiveOffError();
  const store = await prisma.store.findUnique({ where: { ownerId: user.id }, select: { id: true, name: true, isVerified: true } });
  if (!store) throw new ApiError("Create your store first", 409);
  if (!store.isVerified) throw new ApiError("Your store must be approved before you can go live", 403);

  const title = input.title.replace(/\s+/g, " ").trim();
  if (title.length < 3 || title.length > 100) throw new ApiError("Give the live a title of 3–100 characters", 400);
  const productIds = [...new Set(input.productIds)];
  if (productIds.length < 1 || productIds.length > MAX_PRODUCTS) throw new ApiError(`Choose 1–${MAX_PRODUCTS} products`, 400);
  // Only the store's own products that shoppers can buy now
  const buyable = await prisma.product.count({
    where: { id: { in: productIds }, storeId: store.id, isAvailable: true, canBeSold: true, deletedAt: null, lockedAt: null },
  });
  if (buyable !== productIds.length) throw new ApiError("Choose your own products that are for sale", 400);

  const created = await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT 1 AS locked FROM (SELECT pg_advisory_xact_lock(${LIVE_LOCK_NS}::int, ${store.id}::int)) AS l`;
    const current = await tx.liveStream.findFirst({ where: { storeId: store.id, status: "LIVE" }, select: { id: true, roomName: true } });
    if (current) {
      // The app can resume that live with the fresh publisher token (or end it first)
      const e = new ApiError("You are already live. End that live first.", 409);
      e.extra = { code: "ALREADY_LIVE", liveId: current.id, publish: participantToken({ room: current.roomName, identity: `store-${store.id}`, name: store.name, canPublish: true }) };
      throw e;
    }
    const today = await tx.liveStream.count({ where: { storeId: store.id, createdAt: { gte: new Date(Date.now() - 86_400_000) } } });
    if (today >= MAX_LIVES_PER_DAY) throw new ApiError(`You can go live up to ${MAX_LIVES_PER_DAY} times a day`, 429);
    const row = await tx.liveStream.create({ data: { storeId: store.id, title, productIds, roomName: `pending-${randomId(8)}` } });
    return tx.liveStream.update({ where: { id: row.id }, data: { roomName: `live-${row.id}-${randomId()}` }, include: { store: { select: storeSelect } } });
  });

  // Followers hear about it, at most once per store per 6 h (conditional update: one winner across instances)
  const followersNotified = await notifyFollowers(created.id, store, title).catch((err) => {
    logger.warn({ liveId: created.id, err: err?.message }, "Followers not notified");
    return null;
  });
  const publish = participantToken({ room: created.roomName, identity: `store-${store.id}`, name: store.name, canPublish: true });
  const [live] = await presentMany([{ ...created, followersNotified } as LiveRow]);
  return { live, publish };
}

async function notifyFollowers(liveId: number, store: { id: number; name: string }, title: string) {
  const claimed = await prisma.store.updateMany({
    where: { id: store.id, OR: [{ liveNotifiedAt: null }, { liveNotifiedAt: { lt: new Date(Date.now() - FOLLOWER_PUSH_GAP_MS) } }] },
    data: { liveNotifiedAt: new Date() },
  });
  if (!claimed.count) return null;
  const owner = await prisma.store.findUnique({ where: { id: store.id }, select: { ownerId: true } });
  const followers = await prisma.storeFollow.findMany({ where: { storeId: store.id }, select: { userId: true }, take: MAX_FOLLOWER_PUSHES });
  const ids = followers.map((f) => f.userId).filter((id) => id !== owner?.ownerId);
  await prisma.liveStream.update({ where: { id: liveId }, data: { followersNotified: ids.length } });
  if (ids.length) {
    pushToUsers(ids, {
      title: t(`${store.name} is live`, `${store.name} on livenä`),
      body: title,
      data: { type: "live", liveId: String(liveId) },
    }).catch(() => {});
  }
  return ids.length;
}

/** A fresh publisher token for the store's live (the app reconnects after a crash or a network change). */
export async function publishToken(id: number, user: Actor) {
  if (!liveConfigured()) throw new LiveOffError();
  const row = await ownedLive(id, user);
  if (row.status !== "LIVE") throw endedError(row);
  return participantToken({ room: row.roomName, identity: `store-${row.store.id}`, name: row.store.name, canPublish: true });
}

export async function heartbeat(id: number, user: Actor) {
  const done = await prisma.liveStream.updateMany({ where: { id, status: "LIVE", store: { ownerId: user.id } }, data: { lastHeartbeatAt: new Date() } });
  if (done.count) return;
  const row = await ownedLive(id, user);
  throw endedError(row);
}

export async function pin(id: number, user: Actor, productId: number | null) {
  const row = await ownedLive(id, user);
  if (row.status !== "LIVE") throw endedError(row);
  if (productId !== null && !row.productIds.includes(productId)) throw new ApiError("Pin one of the products in this live", 400);
  await prisma.liveStream.update({ where: { id }, data: { pinnedProductId: productId } });
  emitToLive(id, "live:pinned", { productId });
  return { pinnedProductId: productId };
}

/**
 * Ends a live once (conditional update, so the store, an admin and the watchdog cannot end it twice) and tells
 * everyone watching. Returns whether this call ended it.
 */
async function finish(id: number, reason: string, endedById: number | null = null) {
  const done = await prisma.liveStream.updateMany({
    where: { id, status: "LIVE" },
    data: { status: "ENDED", endedAt: new Date(), endedReason: reason, endedById, viewers: 0 },
  });
  if (!done.count) return false;
  emitToLive(id, "live:ended", { reason: publicReason(reason) });
  const row = await prisma.liveStream.findUnique({ where: { id }, select: { roomName: true } });
  if (row) closeRoom(row.roomName).catch(() => {});
  return true;
}

/** POST /live/:id/end: the store ends its own live (idempotent). Admins go through adminEnd (a reason is required). */
export async function endByOwner(id: number, user: Actor) {
  await ownedLive(id, user);
  await finish(id, "store");
  return getLive(id, user);
}

// ─── Watching ───────────────────────────────────────────────────────────────

/** GET /live: lives of approved stores (within reach of lat/lng when given), most viewers first. */
export async function listLive(lat: number | null, lng: number | null) {
  const near = await storesInReach(lat, lng);
  if (near && !near.length) return [];
  const rows = await prisma.liveStream.findMany({
    where: { status: "LIVE", store: { isVerified: true }, ...(near ? { storeId: { in: near } } : {}) },
    include: { store: { select: storeSelect } },
    orderBy: [{ viewers: "desc" }, { startedAt: "desc" }],
    take: 50,
  });
  return presentMany(rows);
}

export async function getLive(id: number, viewer: Viewer) {
  const row = await visibleLive(id, viewer);
  const products = await prisma.product.findMany({
    where: { id: { in: row.productIds }, deletedAt: null, isAvailable: true },
    include: productInclude,
  });
  const info = await priceInfoFor(products);
  const order = new Map(row.productIds.map((pid, i) => [pid, i]));
  products.sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0));
  const [live] = await presentMany([row]);
  const follow = await followInfo(row.store.id, viewer?.id);
  return {
    ...live,
    store: { ...live.store, ...follow },
    // The store's share page (opens the app); lives have no page of their own
    shareUrl: `${env.publicApiUrl}/s/${row.store.id}`,
    products: products.map((p) => presentProduct(p, info.get(p.id))),
    viewerPeak: row.viewerPeak,
    ...(isOwner(row, viewer) || isAdmin(viewer) ? { lastHeartbeatAt: row.lastHeartbeatAt, followersNotified: row.followersNotified } : {}),
  };
}

/** A viewer token (subscribe only). Guests may watch; chat needs a signed-in socket. */
export async function join(id: number, viewer: Viewer) {
  if (!liveConfigured()) throw new LiveOffError();
  const row = await visibleLive(id, viewer);
  if (row.status !== "LIVE") throw endedError(row);
  let identity = `guest-${randomId()}`;
  let name = "Guest";
  if (viewer) {
    const user = await prisma.user.findUnique({ where: { id: viewer.id }, select: { name: true } });
    identity = `u-${viewer.id}`;
    name = isOwner(row, viewer) ? row.store.name : firstName(user?.name ?? "");
  }
  return participantToken({ room: row.roomName, identity, name, canPublish: false });
}

// ─── Chat ───────────────────────────────────────────────────────────────────

type MessageRow = { id: number; text: string; userId: number; hidden: boolean; createdAt: Date; user: { name: string } };
const messageSelect = { id: true, text: true, userId: true, hidden: true, createdAt: true, user: { select: { name: true } } } as const;

function presentMessage(m: MessageRow, store: { ownerId: number; name: string }) {
  const byStore = m.userId === store.ownerId;
  // userId: the store and admins mute a viewer by it (live:ban); the apps also offer Block user
  return { id: m.id, text: m.text, name: byStore ? store.name : firstName(m.user.name), byStore, userId: m.userId, createdAt: m.createdAt };
}

/** The last 50 visible messages, oldest first (messages of users the viewer blocked are left out for the viewer). */
export async function recentMessages(id: number, viewer: Viewer) {
  const row = await visibleLive(id, viewer);
  const blocked = await blockedIdsFor(viewer?.id);
  const rows = await prisma.liveMessage.findMany({
    where: { liveId: id, hidden: false, ...(blocked.length ? { userId: { notIn: blocked } } : {}) },
    select: messageSelect,
    orderBy: { id: "desc" },
    take: 50,
  });
  return rows.reverse().map((m) => presentMessage(m, row.store));
}

/** Socket live:join: the live must be on and visible to the user. */
export async function joinRoom(id: number, user: Actor) {
  const row = await visibleLive(id, user);
  if (row.status !== "LIVE") throw endedError(row);
  return {
    host: isOwner(row, user),
    likeCount: row.likeCount,
    pinnedProductId: row.pinnedProductId,
    messages: await recentMessages(id, user),
  };
}

export async function postMessage(id: number, user: Actor, raw: string) {
  const text = raw.replace(/\s+/g, " ").trim();
  if (!text) throw new ApiError("Write a message first", 400);
  if (text.length > MAX_MESSAGE_LENGTH) throw new ApiError(`Messages can be up to ${MAX_MESSAGE_LENGTH} characters`, 400);
  const row = await visibleLive(id, user);
  if (row.status !== "LIVE") throw endedError(row);
  const [banned, recent] = await Promise.all([
    prisma.liveBan.findUnique({ where: { liveId_userId: { liveId: id, userId: user.id } }, select: { id: true } }),
    prisma.liveMessage.count({ where: { userId: user.id, createdAt: { gte: new Date(Date.now() - 60_000) } } }),
  ]);
  if (banned) throw new ApiError("The store has muted you in this live", 403);
  if (recent >= MESSAGES_PER_MINUTE) throw new ApiError("You are writing very fast. Please wait a moment.", 429);
  const created = await prisma.liveMessage.create({ data: { liveId: id, userId: user.id, text }, select: messageSelect });
  const message = presentMessage(created, row.store);
  emitToLive(id, "live:message", message);
  return message;
}

async function moderatedLive(id: number, user: Actor) {
  const row = await findLive(id);
  if (!row || (!isOwner(row, user) && !isAdmin(user))) throw new ApiError("Live not found", 404);
  return row;
}

/** The store or an admin hides a message for everyone. */
export async function hideMessage(id: number, messageId: number, user: Actor) {
  await moderatedLive(id, user);
  const done = await prisma.liveMessage.updateMany({ where: { id: messageId, liveId: id, hidden: false }, data: { hidden: true } });
  if (!done.count && !(await prisma.liveMessage.findFirst({ where: { id: messageId, liveId: id }, select: { id: true } }))) {
    throw new ApiError("Message not found", 404);
  }
  if (done.count) emitToLive(id, "live:message_hidden", { id: messageId });
  return { hidden: true };
}

/** The store or an admin mutes a viewer in this live: their messages are refused from now on. */
export async function banViewer(id: number, targetId: number, user: Actor) {
  const row = await moderatedLive(id, user);
  if (targetId === row.store.ownerId || targetId === user.id) throw new ApiError("You cannot mute yourself", 400);
  const target = await prisma.user.findUnique({ where: { id: targetId }, select: { role: true } });
  if (!target) throw new ApiError("User not found", 404);
  if (target.role === "ADMIN") throw new ApiError("Admins cannot be muted", 400);
  await prisma.liveBan.upsert({
    where: { liveId_userId: { liveId: id, userId: targetId } },
    create: { liveId: id, userId: targetId, bannedById: user.id },
    update: {},
  });
  return { banned: true };
}

/** Hearts, added in batches by the socket layer (at most every 2 s per live and instance). Returns the new count. */
export async function addLikes(id: number, n: number) {
  const done = await prisma.liveStream.updateMany({ where: { id, status: "LIVE" }, data: { likeCount: { increment: n } } });
  if (!done.count) return null;
  return (await prisma.liveStream.findUnique({ where: { id }, select: { likeCount: true } }))?.likeCount ?? null;
}

/** The current number of viewers (counted from the socket room) and the peak. */
export async function recordViewers(id: number, count: number) {
  await prisma.liveStream.updateMany({ where: { id, status: "LIVE" }, data: { viewers: count } });
  await prisma.liveStream.updateMany({ where: { id, status: "LIVE", viewerPeak: { lt: count } }, data: { viewerPeak: count } });
}

/** Owner of a live (socket layer: the store's own sockets are not counted as viewers). */
export async function liveOwnerId(id: number) {
  return (await prisma.liveStream.findUnique({ where: { id }, select: { store: { select: { ownerId: true } } } }))?.store.ownerId ?? null;
}

// ─── Reports (DSA Art. 16) ──────────────────────────────────────────────────

export async function report(id: number, reporterId: number | null, reason: string, details?: string) {
  const row = await findLive(id);
  if (!row) throw new ApiError("Live not found", 404);
  if (reporterId) {
    const dup = await prisma.liveReport.findFirst({ where: { liveId: id, reporterId, status: "OPEN" }, select: { id: true } });
    if (dup) return { received: true };
  }
  await prisma.liveReport.create({ data: { liveId: id, reporterId, reason, details: details?.trim().slice(0, 1000) || null } });
  return { received: true };
}

// ─── Store's own lives ──────────────────────────────────────────────────────

export async function myLives(ownerId: number) {
  const store = await prisma.store.findUnique({ where: { ownerId }, select: { id: true } });
  if (!store) throw new ApiError("Create your store first", 409);
  const rows = await prisma.liveStream.findMany({
    where: { storeId: store.id },
    include: { store: { select: storeSelect } },
    orderBy: { createdAt: "desc" },
    take: 20,
  });
  const presented = await presentMany(rows);
  const withStats = presented.map((p, i) => ({ ...p, viewerPeak: rows[i].viewerPeak, lastHeartbeatAt: rows[i].lastHeartbeatAt, followersNotified: rows[i].followersNotified }));
  const current = rows.find((r) => r.status === "LIVE") ?? null;
  // A fresh publisher token for the current live, so the store app can resume it after a restart
  const publish = current && liveConfigured()
    ? participantToken({ room: current.roomName, identity: `store-${current.store.id}`, name: current.store.name, canPublish: true })
    : null;
  return { live: withStats.find((l) => l.status === "LIVE") ?? null, publish, recent: withStats };
}

// ─── Admin ──────────────────────────────────────────────────────────────────

const adminInclude = { store: { select: { id: true, name: true } }, _count: { select: { reports: true } } } as const;
type AdminRow = Prisma.LiveStreamGetPayload<{ include: typeof adminInclude }>;

async function presentAdmin(rows: AdminRow[]) {
  const ids = rows.map((r) => r.id);
  const open = ids.length
    ? await prisma.liveReport.groupBy({ by: ["liveId"], where: { liveId: { in: ids }, status: "OPEN" }, _count: { _all: true } })
    : [];
  const openBy = new Map(open.map((o) => [o.liveId, o._count._all]));
  return rows.map((r) => ({
    id: r.id, title: r.title, status: r.status, startedAt: r.startedAt, endedAt: r.endedAt, endedReason: r.endedReason,
    viewers: r.status === "LIVE" ? r.viewers : 0, viewerPeak: r.viewerPeak, likeCount: r.likeCount,
    reportCount: r._count.reports, openReports: openBy.get(r.id) ?? 0,
    store: r.store, lastHeartbeatAt: r.lastHeartbeatAt, productIds: r.productIds,
  }));
}

/** Live now and the last 50 ended, with report counts (admin panel → Live). */
export async function adminList() {
  const [live, ended] = await Promise.all([
    prisma.liveStream.findMany({ where: { status: "LIVE" }, include: adminInclude, orderBy: { startedAt: "desc" }, take: 200 }),
    prisma.liveStream.findMany({ where: { status: "ENDED" }, include: adminInclude, orderBy: { endedAt: "desc" }, take: 50 }),
  ]);
  return { live: await presentAdmin(live), ended: await presentAdmin(ended) };
}

async function adminItem(id: number) {
  const row = await prisma.liveStream.findUnique({ where: { id }, include: adminInclude });
  return row ? (await presentAdmin([row]))[0] : null;
}

/** Every message of a live, hidden ones included (marked), oldest first, and its reports. */
export async function adminMessages(id: number) {
  const row = await findLive(id);
  if (!row) throw new ApiError("Live not found", 404);
  const [rows, reports] = await Promise.all([
    prisma.liveMessage.findMany({ where: { liveId: id }, select: messageSelect, orderBy: { id: "desc" }, take: 500 }),
    prisma.liveReport.findMany({
      where: { liveId: id },
      select: { id: true, reason: true, details: true, status: true, createdAt: true, resolvedAt: true },
      orderBy: { createdAt: "desc" },
      take: 100,
    }),
  ]);
  return {
    messages: rows.reverse().map((m) => ({ ...presentMessage(m, row.store), hidden: m.hidden })),
    reports,
  };
}

/**
 * An admin ends a live: audited, the open reports are actioned, and the store gets a statement of reasons by email
 * (DSA Art. 17: what was decided, why, how to object) and a push.
 */
export async function adminEnd(id: number, adminId: number, rawReason: string) {
  const reason = rawReason.replace(/\s+/g, " ").trim();
  if (reason.length < 10) throw new ApiError("Give the store a clear reason (at least 10 characters)", 400);
  const row = await prisma.liveStream.findUnique({
    where: { id },
    include: { store: { select: { id: true, name: true, owner: { select: { id: true, email: true } } } } },
  });
  if (!row) throw new ApiError("Live not found", 404);
  const ended = await finish(id, reason.slice(0, 500), adminId);
  if (ended) {
    await prisma.$transaction([
      prisma.adminAuditLog.create({
        data: { adminId, action: "live.end", entity: "LiveStream", entityId: id, oldValue: { status: "LIVE" }, newValue: { status: "ENDED", reason: reason.slice(0, 500) } },
      }),
      prisma.liveReport.updateMany({ where: { liveId: id, status: "OPEN" }, data: { status: "ACTIONED", resolvedById: adminId, resolvedAt: new Date() } }),
    ]);
    const owner = row.store.owner;
    localeOfUser(owner.id).then((locale) => sendLiveEndedEmail(owner.email, id, row.title, reason, locale)).catch(() => {});
    pushToUser(owner.id, {
      title: t("Your live was ended", "Livelähetyksesi lopetettiin"),
      body: reason.slice(0, 120),
      data: { type: "live", liveId: String(id) },
    }).catch(() => {});
  }
  return { ended, live: await adminItem(id) };
}

export async function resolveReport(reportId: number, adminId: number, status: "ACTIONED" | "DISMISSED") {
  const r = await prisma.liveReport.findUnique({ where: { id: reportId }, select: { id: true } });
  if (!r) throw new ApiError("Report not found", 404);
  return prisma.liveReport.update({ where: { id: reportId }, data: { status, resolvedById: adminId, resolvedAt: new Date() } });
}

// ─── Background jobs ────────────────────────────────────────────────────────

/** Ends lives whose store stopped sending heartbeats (2 min) or that ran longer than 4 h. */
export async function runLiveWatchdog() {
  const now = Date.now();
  const [tooLong, silent] = await Promise.all([
    prisma.liveStream.findMany({ where: { status: "LIVE", startedAt: { lt: new Date(now - MAX_DURATION_MS) } }, select: { id: true }, take: 100 }),
    prisma.liveStream.findMany({ where: { status: "LIVE", lastHeartbeatAt: { lt: new Date(now - HEARTBEAT_TIMEOUT_MS) } }, select: { id: true }, take: 100 }),
  ]);
  let ended = 0;
  for (const l of tooLong) if (await finish(l.id, "max_duration")) ended++;
  for (const l of silent) if (await finish(l.id, "timeout")) ended++;
  if (ended) logger.info({ ended }, "Lives ended by the watchdog");
  return ended;
}

/** Live chat is kept 30 days after the live ended. */
export async function purgeOldLiveMessages() {
  const cutoff = new Date(Date.now() - CHAT_KEEP_DAYS * 86_400_000);
  const r = await prisma.liveMessage.deleteMany({ where: { live: { status: "ENDED", endedAt: { lt: cutoff } } } });
  await prisma.liveBan.deleteMany({ where: { live: { status: "ENDED", endedAt: { lt: cutoff } } } });
  return r.count;
}

/** Account deletion of a store owner: its live ends at once. */
export async function endLivesOfStore(storeId: number) {
  const rows = await prisma.liveStream.findMany({ where: { storeId, status: "LIVE" }, select: { id: true }, take: 10 });
  for (const r of rows) await finish(r.id, "store");
}
