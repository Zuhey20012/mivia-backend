import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { audioMp3Url, destroyResource, getResource } from "../../lib/cloudinary";
import { UploadProof, verifyOwnedUpload } from "../media/media.service";
import { getFeed } from "../drops/drops.service";

/**
 * Malvoya's sound library (since 2.14.0): tracks Malvoya holds a licence for (a bought commercial licence, CC0 or our
 * own recordings). Only admins add them (upload kind `library_sound`, folder malvoya/sounds/); every store may put
 * them on its drops. A store's own uploaded sound is never offered to other stores (no licence to share it).
 */

export const MAX_LIBRARY_SOUND_SECONDS = 180;
/** Drops that count as using a sound: live or still processing. */
const USING_STATUSES = ["READY", "PROCESSING"] as const;

type SoundRow = Prisma.SoundGetPayload<object>;
type Viewer = { id: number; role: string } | undefined;

/** How many live or processing drops use each sound. */
async function useCounts(ids: number[]) {
  if (!ids.length) return new Map<number, number>();
  const rows = await prisma.drop.groupBy({
    by: ["soundId"],
    where: { soundId: { in: ids }, status: { in: [...USING_STATUSES] } },
    _count: { _all: true },
  });
  return new Map(rows.map((r) => [r.soundId as number, r._count._all]));
}

/** What stores and shoppers see. */
function publicSound(s: SoundRow, useCount: number) {
  return { id: s.id, title: s.title, artist: s.artist, durationSec: s.durationSec, url: audioMp3Url(s.publicId), useCount };
}

/** What admins see: everything, including the licence. */
function adminSound(s: SoundRow, useCount: number) {
  return {
    ...publicSound(s, useCount),
    publicId: s.publicId, licence: s.licence, licenceUrl: s.licenceUrl, active: s.active,
    createdById: s.createdById, createdAt: s.createdAt, updatedAt: s.updatedAt,
  };
}

const audit = (adminId: number, action: string, entityId: number, oldValue: unknown, newValue: unknown) =>
  prisma.adminAuditLog.create({ data: { adminId, action, entity: "Sound", entityId, oldValue: oldValue as any, newValue: newValue as any } });

// ─── Admin ──────────────────────────────────────────────────────────────────

export async function adminList() {
  const rows = await prisma.sound.findMany({ orderBy: { id: "desc" }, take: 500 });
  const counts = await useCounts(rows.map((r) => r.id));
  return rows.map((r) => adminSound(r, counts.get(r.id) ?? 0));
}

export async function adminCreate(admin: { id: number; role: string }, input: {
  title: string; artist?: string | null; licence: string; licenceUrl?: string | null; upload: UploadProof;
}) {
  await verifyOwnedUpload("library_sound", admin, input.upload);
  const resource = await getResource(input.upload.publicId, "video");
  if (!resource) throw new ApiError("The sound upload was not found. Please try again.", 400);
  const duration = resource.duration ?? 0;
  if (duration > MAX_LIBRARY_SOUND_SECONDS) {
    await destroyResource(input.upload.publicId, "video").catch(() => {}); // erased before answering
    throw new ApiError(`Library sounds can be up to ${MAX_LIBRARY_SOUND_SECONDS} seconds`, 400);
  }
  if (!(duration > 0)) throw new ApiError("The length of the sound could not be read. Upload an audio file.", 400);
  try {
    const sound = await prisma.sound.create({
      data: {
        title: input.title,
        artist: input.artist || null,
        publicId: input.upload.publicId,
        durationSec: Math.round(duration * 100) / 100,
        licence: input.licence,
        licenceUrl: input.licenceUrl || null,
        createdById: admin.id,
      },
    });
    await audit(admin.id, "sound.create", sound.id, null, {
      title: sound.title, artist: sound.artist, publicId: sound.publicId, durationSec: sound.durationSec,
      licence: sound.licence, licenceUrl: sound.licenceUrl, rightsConfirmed: true,
    });
    return adminSound(sound, 0);
  } catch (e: any) {
    if (e?.code === "P2002") throw new ApiError("That sound is already in the library", 409);
    throw e;
  }
}

export async function adminUpdate(adminId: number, id: number, patch: {
  title?: string; artist?: string | null; licence?: string; licenceUrl?: string | null; active?: boolean;
}) {
  const cur = await prisma.sound.findUnique({ where: { id } });
  if (!cur) throw new ApiError("Sound not found", 404);
  const data: Prisma.SoundUpdateInput = {};
  const oldValue: Record<string, unknown> = {};
  const newValue: Record<string, unknown> = {};
  for (const key of ["title", "artist", "licence", "licenceUrl", "active"] as const) {
    if (patch[key] === undefined) continue;
    const next = key === "artist" || key === "licenceUrl" ? (patch[key] || null) : patch[key];
    if (cur[key] === next) continue;
    (data as any)[key] = next;
    oldValue[key] = cur[key];
    newValue[key] = next;
  }
  const sound = Object.keys(data).length ? await prisma.sound.update({ where: { id }, data }) : cur;
  if (Object.keys(data).length) await audit(adminId, "sound.update", id, oldValue, newValue);
  const counts = await useCounts([id]);
  return adminSound(sound, counts.get(id) ?? 0);
}

// ─── Stores and shoppers ────────────────────────────────────────────────────

/** Active sounds, newest first, optionally searched by title or artist. */
export async function listActive(opts: { q?: string; limit: number; before?: number }) {
  const q = opts.q?.trim();
  const rows = await prisma.sound.findMany({
    where: {
      active: true,
      ...(opts.before ? { id: { lt: opts.before } } : {}),
      ...(q ? { OR: [{ title: { contains: q, mode: "insensitive" } }, { artist: { contains: q, mode: "insensitive" } }] } : {}),
    },
    orderBy: { id: "desc" },
    take: opts.limit + 1,
  });
  const page = rows.slice(0, opts.limit);
  const counts = await useCounts(page.map((r) => r.id));
  return {
    sounds: page.map((r) => publicSound(r, counts.get(r.id) ?? 0)),
    nextBefore: rows.length > opts.limit ? page[page.length - 1].id : null,
  };
}

/** A sound page: an active sound, or an inactive one that drops still use (404 otherwise). */
async function visibleSound(id: number) {
  const s = await prisma.sound.findUnique({ where: { id } });
  if (!s) throw new ApiError("Sound not found", 404);
  const useCount = (await useCounts([id])).get(id) ?? 0;
  if (!s.active && useCount === 0) throw new ApiError("Sound not found", 404);
  return { s, useCount };
}

export async function getSound(id: number) {
  const { s, useCount } = await visibleSound(id);
  return publicSound(s, useCount);
}

/** Live drops using the sound, newest first (the same payload and cursor as the feed). */
export async function soundDrops(id: number, opts: { cursor?: string; limit: number }, viewer: Viewer) {
  await visibleSound(id);
  return getFeed({ mode: "latest", cursor: opts.cursor, limit: opts.limit, lat: null, lng: null, soundId: id }, viewer);
}

