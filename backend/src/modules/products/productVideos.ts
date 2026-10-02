import pino from "pino";
import { Router, Response } from "express";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { destroyResource, getResource, hlsReady } from "../../lib/cloudinary";
import { auth, AuthRequest, requireRole } from "../../middleware/auth";
import { verifyOwnedUpload, UploadProof } from "../media/media.service";
import { presentVideo } from "./pricing";

const logger = pino({ name: "product-videos" });

const MAX_VIDEOS_PER_PRODUCT = 3;
const MAX_VIDEO_SECONDS = 60;

type Actor = { id: number; role: string };

async function ownedProduct(actor: Actor, productId: number) {
  const product = await prisma.product.findUnique({ where: { id: productId }, select: { id: true, store: { select: { ownerId: true } } } });
  if (!product || product.store.ownerId !== actor.id) throw new ApiError("Product not found", 404);
  return product;
}

/** Attaches a finished, signed video upload to one of the store's own products. */
export async function addProductVideo(actor: Actor, productId: number, upload: UploadProof) {
  await ownedProduct(actor, productId);
  const count = await prisma.productVideo.count({ where: { productId, status: { not: "FAILED" } } });
  if (count >= MAX_VIDEOS_PER_PRODUCT) throw new ApiError(`A product can have up to ${MAX_VIDEOS_PER_PRODUCT} videos`, 409);

  await verifyOwnedUpload("product_video", actor, upload);
  const resource = await getResource(upload.publicId, "video");
  if (!resource) throw new ApiError("The upload was not found. Please try again.", 400);
  if ((resource.duration ?? 0) > MAX_VIDEO_SECONDS) {
    destroyResource(upload.publicId, "video").catch(() => {});
    throw new ApiError(`Product videos can be up to ${MAX_VIDEO_SECONDS} seconds`, 400);
  }

  try {
    const video = await prisma.productVideo.create({
      data: {
        productId,
        publicId: upload.publicId,
        status: hlsReady(resource.derived) ? "READY" : "PROCESSING",
        durationSec: resource.duration ?? null,
        width: resource.width ?? null,
        height: resource.height ?? null,
        position: count,
      },
    });
    return presentVideo(video, { owner: true });
  } catch (e: any) {
    if (e?.code === "P2002") throw new ApiError("That video is already added", 409);
    throw e;
  }
}

export async function deleteProductVideo(actor: Actor, productId: number, videoId: number) {
  await ownedProduct(actor, productId);
  const video = await prisma.productVideo.findFirst({ where: { id: videoId, productId } });
  if (!video) throw new ApiError("Video not found", 404);
  await prisma.productVideo.delete({ where: { id: video.id } });
  destroyResource(video.publicId, "video").catch(() => {});
}

/** Cloudinary's eager notification (see media.routes): the streaming versions are ready, or failed. */
export async function onProductVideoProcessed(publicId: string, failed: boolean) {
  await prisma.productVideo.updateMany({ where: { publicId, status: "PROCESSING" }, data: { status: failed ? "FAILED" : "READY" } });
}

/** Safety net when a webhook is missed: ask Cloudinary directly. */
export async function checkProcessingProductVideos() {
  const pending = await prisma.productVideo.findMany({
    where: { status: "PROCESSING", createdAt: { lte: new Date(Date.now() - 60_000) } },
    select: { id: true, publicId: true, createdAt: true },
    take: 20,
  });
  for (const v of pending) {
    try {
      const resource = await getResource(v.publicId, "video");
      if (resource && hlsReady(resource.derived)) {
        await prisma.productVideo.update({ where: { id: v.id }, data: { status: "READY" } });
      } else if (Date.now() - v.createdAt.getTime() > 2 * 3_600_000) {
        await prisma.productVideo.update({ where: { id: v.id }, data: { status: "FAILED" } });
      }
    } catch (err: any) {
      logger.warn({ videoId: v.id, err: err?.message }, "Could not check product video processing");
    }
  }
}

// ─── Routes (store app) ─────────────────────────────────────────────────────

const uploadSchema = z.object({
  publicId: z.string().min(5).max(200),
  version: z.union([z.string().max(20), z.number().int()]),
  signature: z.string().length(40),
});

export const productVideoRoutes = Router();

productVideoRoutes.post("/products/:id(\\d+)/videos", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  const body = uploadSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "Invalid upload" });
  try {
    res.status(201).json({ ok: true, video: await addProductVideo(req.user!, positiveId(req.params.id)!, body.data) });
  } catch (e) { sendError(res, e); }
});

productVideoRoutes.delete("/products/:id(\\d+)/videos/:videoId(\\d+)", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  try {
    await deleteProductVideo(req.user!, positiveId(req.params.id)!, positiveId(req.params.videoId)!);
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
});
