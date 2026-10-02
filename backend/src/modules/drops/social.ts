import { Router, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { pushToUser } from "../../lib/push";
import { auth, optionalAuth, requireRole, AuthRequest } from "../../middleware/auth";
import { REPORT_REASONS } from "./drops.service";

const MAX_COMMENT_LENGTH = 300;
const COMMENTS_PER_WINDOW = 20; // per user, per 10 minutes
const AUTO_HIDE_REPORTS = 3;

type Viewer = { id: number; role: string } | undefined;

// ─── Comments ───────────────────────────────────────────────────────────────

async function visibleDrop(dropId: number) {
  const drop = await prisma.drop.findUnique({ where: { id: dropId }, select: { id: true, status: true, store: { select: { ownerId: true, name: true } } } });
  if (!drop || drop.status !== "READY") throw new ApiError("This drop is not available", 404);
  return drop;
}

type CommentRow = {
  id: number; body: string; createdAt: Date; userId: number;
  user: { name: string; role: string; store: { id: number; name: string } | null };
};

/** Commenters appear by first name; the store that posted the drop appears as the store. */
function presentComment(c: CommentRow, viewer: Viewer, dropOwnerId: number) {
  const byStore = c.userId === dropOwnerId && !!c.user.store;
  return {
    id: c.id,
    body: c.body,
    createdAt: c.createdAt,
    author: byStore ? c.user.store!.name : (c.user.name.trim().split(/\s+/)[0] || "Customer"),
    byStore,
    mine: viewer?.id === c.userId,
    canDelete: !!viewer && (viewer.id === c.userId || viewer.id === dropOwnerId || viewer.role === "ADMIN"),
  };
}

const commentSelect = {
  id: true, body: true, createdAt: true, userId: true,
  user: { select: { name: true, role: true, store: { select: { id: true, name: true } } } },
} as const;

export async function listComments(dropId: number, viewer: Viewer, before?: number, limit = 30) {
  const drop = await visibleDrop(dropId);
  const rows = await prisma.dropComment.findMany({
    where: { dropId, status: "VISIBLE", ...(before ? { id: { lt: before } } : {}) },
    select: commentSelect,
    orderBy: { id: "desc" },
    take: limit + 1,
  });
  const page = rows.slice(0, limit);
  return {
    comments: page.map((c) => presentComment(c, viewer, drop.store.ownerId)),
    nextBefore: rows.length > limit ? page[page.length - 1].id : null,
  };
}

export async function addComment(dropId: number, user: { id: number; role: string }, rawBody: string) {
  const drop = await visibleDrop(dropId);
  const body = rawBody.replace(/\s+/g, " ").trim();
  if (!body) throw new ApiError("Write a comment first", 400);
  if (body.length > MAX_COMMENT_LENGTH) throw new ApiError(`Comments can be up to ${MAX_COMMENT_LENGTH} characters`, 400);
  const recent = await prisma.dropComment.count({ where: { userId: user.id, createdAt: { gte: new Date(Date.now() - 10 * 60_000) } } });
  if (recent >= COMMENTS_PER_WINDOW) throw new ApiError("You are commenting very fast. Please wait a few minutes.", 429);

  const [comment] = await prisma.$transaction([
    prisma.dropComment.create({ data: { dropId, userId: user.id, body }, select: commentSelect }),
    prisma.drop.update({ where: { id: dropId }, data: { commentCount: { increment: 1 } } }),
  ]);
  if (user.id !== drop.store.ownerId) {
    pushToUser(drop.store.ownerId, {
      title: "New comment on your drop",
      body: body.length > 80 ? `${body.slice(0, 79)}…` : body,
      data: { type: "drop_comment", dropId: String(dropId) },
    }).catch(() => {});
  }
  return presentComment(comment, user, drop.store.ownerId);
}

/** Hides a visible comment and keeps the drop's comment count in step. */
async function takeDown(commentId: number, status: "HIDDEN" | "REMOVED") {
  const changed = await prisma.dropComment.updateMany({ where: { id: commentId, status: "VISIBLE" }, data: { status } });
  if (changed.count) {
    const c = await prisma.dropComment.findUnique({ where: { id: commentId }, select: { dropId: true } });
    if (c) await prisma.drop.update({ where: { id: c.dropId }, data: { commentCount: { decrement: 1 } } });
  } else if (status === "REMOVED") {
    await prisma.dropComment.updateMany({ where: { id: commentId, status: "HIDDEN" }, data: { status } });
  }
}

/** The author, the store that posted the drop, or an admin can delete a comment. */
export async function deleteComment(dropId: number, commentId: number, user: { id: number; role: string }) {
  const comment = await prisma.dropComment.findFirst({
    where: { id: commentId, dropId, status: { not: "REMOVED" } },
    select: { userId: true, drop: { select: { store: { select: { ownerId: true } } } } },
  });
  if (!comment) throw new ApiError("Comment not found", 404);
  const allowed = comment.userId === user.id || comment.drop.store.ownerId === user.id || user.role === "ADMIN";
  if (!allowed) throw new ApiError("You can only delete your own comments", 403);
  await takeDown(commentId, "REMOVED");
}

/** DSA notice: three distinct reporters hide the comment until an admin decides. */
export async function reportComment(dropId: number, commentId: number, reporterId: number, reason: string) {
  const comment = await prisma.dropComment.findFirst({ where: { id: commentId, dropId, status: "VISIBLE" }, select: { id: true, userId: true } });
  if (!comment) throw new ApiError("Comment not found", 404);
  if (comment.userId === reporterId) throw new ApiError("You cannot report your own comment", 400);
  try {
    await prisma.dropCommentReport.create({ data: { commentId, reporterId, reason } });
  } catch (e: any) {
    if (e?.code === "P2002") return { reported: true }; // already reported by this user
    throw e;
  }
  const updated = await prisma.dropComment.update({ where: { id: commentId }, data: { reportCount: { increment: 1 } }, select: { reportCount: true } });
  if (updated.reportCount >= AUTO_HIDE_REPORTS) await takeDown(commentId, "HIDDEN");
  return { reported: true };
}

export async function adminReportedComments() {
  return prisma.dropComment.findMany({
    where: { reportCount: { gt: 0 }, status: { in: ["VISIBLE", "HIDDEN"] } },
    select: {
      id: true, dropId: true, body: true, status: true, reportCount: true, createdAt: true,
      user: { select: { id: true, name: true } },
      reports: { select: { reason: true, createdAt: true }, orderBy: { createdAt: "desc" }, take: 10 },
    },
    orderBy: [{ reportCount: "desc" }, { id: "desc" }],
    take: 100,
  });
}

export async function adminModerateComment(commentId: number, action: "remove" | "restore") {
  const comment = await prisma.dropComment.findUnique({ where: { id: commentId }, select: { status: true, dropId: true } });
  if (!comment) throw new ApiError("Comment not found", 404);
  if (action === "remove") {
    await takeDown(commentId, "REMOVED");
  } else if (comment.status === "HIDDEN") {
    await prisma.$transaction([
      prisma.dropComment.update({ where: { id: commentId }, data: { status: "VISIBLE", reportCount: 0 } }),
      prisma.dropCommentReport.deleteMany({ where: { commentId } }),
      prisma.drop.update({ where: { id: comment.dropId }, data: { commentCount: { increment: 1 } } }),
    ]);
  }
  return prisma.dropComment.findUnique({ where: { id: commentId }, select: { id: true, status: true } });
}

// ─── Following stores ───────────────────────────────────────────────────────

async function followableStore(storeId: number) {
  const store = await prisma.store.findUnique({ where: { id: storeId }, select: { id: true, isVerified: true } });
  if (!store || !store.isVerified) throw new ApiError("Store not found", 404);
  return store;
}

export async function follow(storeId: number, userId: number) {
  await followableStore(storeId);
  await prisma.storeFollow.upsert({ where: { userId_storeId: { userId, storeId } }, create: { userId, storeId }, update: {} });
  return { following: true, followerCount: await prisma.storeFollow.count({ where: { storeId } }) };
}

export async function unfollow(storeId: number, userId: number) {
  await prisma.storeFollow.deleteMany({ where: { userId, storeId } });
  return { following: false, followerCount: await prisma.storeFollow.count({ where: { storeId } }) };
}

export async function followInfo(storeId: number, viewerId?: number) {
  const [followerCount, mine] = await Promise.all([
    prisma.storeFollow.count({ where: { storeId } }),
    viewerId ? prisma.storeFollow.findUnique({ where: { userId_storeId: { userId: viewerId, storeId } } }) : Promise.resolve(null),
  ]);
  return { followerCount, followedByMe: !!mine };
}

export async function followedStoreIds(userId: number) {
  const rows = await prisma.storeFollow.findMany({ where: { userId }, select: { storeId: true }, take: 2000 });
  return rows.map((r) => r.storeId);
}

// ─── Routes ─────────────────────────────────────────────────────────────────

export const socialRoutes = Router();

socialRoutes.get("/drops/:id(\\d+)/comments", optionalAuth, async (req: AuthRequest, res: Response) => {
  const before = req.query.before !== undefined ? positiveId(req.query.before) ?? undefined : undefined;
  try {
    res.json({ ok: true, ...(await listComments(positiveId(req.params.id)!, req.user, before)) });
  } catch (e) { sendError(res, e); }
});

socialRoutes.post("/drops/:id(\\d+)/comments", auth, async (req: AuthRequest, res: Response) => {
  const body = z.object({ body: z.string().max(2000) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Write a comment first" });
  try {
    res.status(201).json({ ok: true, comment: await addComment(positiveId(req.params.id)!, req.user!, body.data.body) });
  } catch (e) { sendError(res, e); }
});

socialRoutes.delete("/drops/:id(\\d+)/comments/:commentId(\\d+)", auth, async (req: AuthRequest, res: Response) => {
  try {
    await deleteComment(positiveId(req.params.id)!, positiveId(req.params.commentId)!, req.user!);
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});

socialRoutes.post("/drops/:id(\\d+)/comments/:commentId(\\d+)/report", auth, async (req: AuthRequest, res: Response) => {
  const body = z.object({ reason: z.enum(REPORT_REASONS) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Choose a reason" });
  try {
    res.json({ ok: true, ...(await reportComment(positiveId(req.params.id)!, positiveId(req.params.commentId)!, req.user!.id, body.data.reason)) });
  } catch (e) { sendError(res, e); }
});

socialRoutes.put("/stores/:id(\\d+)/follow", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await follow(positiveId(req.params.id)!, req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

socialRoutes.delete("/stores/:id(\\d+)/follow", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await unfollow(positiveId(req.params.id)!, req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

socialRoutes.get("/admin/comments/reported", auth, requireRole("ADMIN"), async (_req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, comments: await adminReportedComments() });
  } catch (e) { sendError(res, e); }
});

socialRoutes.post("/admin/comments/:commentId(\\d+)", auth, requireRole("ADMIN"), async (req: AuthRequest, res: Response) => {
  const body = z.object({ action: z.enum(["remove", "restore"]) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid action" });
  try {
    res.json({ ok: true, comment: await adminModerateComment(positiveId(req.params.commentId)!, body.data.action) });
  } catch (e) { sendError(res, e); }
});
