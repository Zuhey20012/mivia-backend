import crypto from "crypto";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { env } from "../../config/env";
import {
  mediaConfigured, signedUpload, verifyUploadSignature, imageUrl, videoHlsUrl, videoMp4Url, videoPosterUrl,
  VIDEO_EAGER, ResourceType, DeliveryType,
} from "../../lib/cloudinary";

export type MediaKind = "product_image" | "store_image" | "drop_video" | "drop_image" | "delivery_proof" | "avatar";
export const MEDIA_KINDS: MediaKind[] = ["product_image", "store_image", "drop_video", "drop_image", "delivery_proof", "avatar"];

type Actor = { id: number; role: string };

type Target = {
  prefix: string; // every public id for this kind and owner starts with this
  resourceType: ResourceType;
  type: DeliveryType;
  formats: string;
  eager?: string;
  notify?: boolean;
};

const IMAGE_FORMATS = "jpg,jpeg,png,webp,heic,heif";
const VIDEO_FORMATS = "mp4,mov,m4v,webm,3gp";

async function storeIdFor(actor: Actor) {
  if (actor.role !== "VENDOR") throw new ApiError("Only store accounts can upload this", 403);
  const store = await prisma.store.findUnique({ where: { ownerId: actor.id }, select: { id: true } });
  if (!store) throw new ApiError("Create your store first", 409);
  return store.id;
}

/** Where an actor may upload a given kind of media. Also used to check ownership of what they send back. */
export async function targetFor(kind: MediaKind, actor: Actor, orderId?: number): Promise<Target> {
  switch (kind) {
    case "product_image":
      return { prefix: `malvoya/products/s${await storeIdFor(actor)}/`, resourceType: "image", type: "upload", formats: IMAGE_FORMATS };
    case "store_image":
      return { prefix: `malvoya/stores/s${await storeIdFor(actor)}/`, resourceType: "image", type: "upload", formats: IMAGE_FORMATS };
    case "drop_image":
      return { prefix: `malvoya/drops/s${await storeIdFor(actor)}/`, resourceType: "image", type: "upload", formats: IMAGE_FORMATS };
    case "drop_video":
      return {
        prefix: `malvoya/drops/s${await storeIdFor(actor)}/`, resourceType: "video", type: "upload", formats: VIDEO_FORMATS,
        eager: VIDEO_EAGER, notify: true,
      };
    case "delivery_proof": {
      if (actor.role !== "COURIER") throw new ApiError("Only couriers can upload delivery photos", 403);
      if (!orderId) throw new ApiError("orderId is required");
      const order = await prisma.order.findFirst({
        where: { id: orderId, status: "SHIPPED", courier: { userId: actor.id } },
        select: { id: true },
      });
      if (!order) throw new ApiError("You can only add a photo to a delivery you are carrying", 403);
      // Private: only the customer, the courier and Malvoya can see it, through signed links
      return { prefix: `malvoya/proofs/o${orderId}/`, resourceType: "image", type: "authenticated", formats: IMAGE_FORMATS };
    }
    case "avatar":
      return { prefix: `malvoya/avatars/u${actor.id}/`, resourceType: "image", type: "upload", formats: IMAGE_FORMATS };
  }
}

function requireMedia() {
  if (!mediaConfigured()) throw new ApiError("Photo and video uploads are not switched on yet", 503);
}

export async function signUpload(kind: MediaKind, actor: Actor, orderId?: number) {
  requireMedia();
  const target = await targetFor(kind, actor, orderId);
  const publicId = target.prefix + crypto.randomBytes(12).toString("hex");
  const signed = signedUpload({
    publicId,
    resourceType: target.resourceType,
    type: target.type,
    allowedFormats: target.formats,
    eager: target.eager,
    notificationUrl: target.notify ? `${env.publicApiUrl}/api/v1/media/cloudinary/notify` : undefined,
  });
  return { kind, publicId, resourceType: target.resourceType, ...signed };
}

export type UploadProof = { publicId: string; version: string | number; signature: string };

/** Checks that an upload really came from Cloudinary and belongs to this actor. */
export async function verifyOwnedUpload(kind: MediaKind, actor: Actor, proof: UploadProof, orderId?: number) {
  requireMedia();
  const target = await targetFor(kind, actor, orderId);
  if (!proof?.publicId?.startsWith(target.prefix)) throw new ApiError("That upload does not belong to you", 403);
  if (!verifyUploadSignature(proof.publicId, proof.version, proof.signature)) throw new ApiError("Upload could not be verified", 400);
  return target;
}

/** Canonical URLs for a verified upload (the apps never send us URLs of their own). */
export function describe(kind: MediaKind, publicId: string) {
  if (kind === "drop_video") {
    return { publicId, hls: videoHlsUrl(publicId), mp4: videoMp4Url(publicId), poster: videoPosterUrl(publicId) };
  }
  if (kind === "delivery_proof") return { publicId };
  return { publicId, url: imageUrl(publicId), thumb: imageUrl(publicId, "c_fill,w_400,h_500,q_auto,f_auto") };
}
