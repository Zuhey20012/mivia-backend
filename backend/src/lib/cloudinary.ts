import crypto from "crypto";
import { env } from "../config/env";

/**
 * Cloudinary without the SDK: signed direct uploads from the apps, signature checks on what they
 * send back, and delivery URLs. The API secret never leaves the server.
 */

export type ResourceType = "image" | "video";
export type DeliveryType = "upload" | "authenticated";

const { cloudName, apiKey, apiSecret } = env.cloudinary;
// Upload/Admin API host; overridable so tests can use a local mock
const API_BASE = (process.env.CLOUDINARY_API_BASE || "https://api.cloudinary.com").replace(/\/+$/, "");

export function mediaConfigured() {
  return !!(cloudName && apiKey && apiSecret);
}

function sha1(input: string) {
  return crypto.createHash("sha1").update(input).digest("hex");
}

/** Cloudinary request signature: sorted "key=value" pairs joined by "&", followed by the secret. */
export function signParams(params: Record<string, string | number>) {
  const toSign = Object.keys(params)
    .filter((k) => params[k] !== undefined && params[k] !== "")
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join("&");
  return sha1(toSign + apiSecret);
}

/** Parameters the app posts (with the file) to Cloudinary's upload endpoint. */
export function signedUpload(opts: {
  publicId: string;
  resourceType: ResourceType;
  type?: DeliveryType;
  allowedFormats: string;
  eager?: string;
  notificationUrl?: string;
}) {
  const params: Record<string, string | number> = {
    public_id: opts.publicId,
    timestamp: Math.floor(Date.now() / 1000),
    allowed_formats: opts.allowedFormats,
    overwrite: "false",
  };
  if (opts.type && opts.type !== "upload") params.type = opts.type;
  if (opts.eager) {
    params.eager = opts.eager;
    params.eager_async = "true";
  }
  if (opts.notificationUrl) params.notification_url = opts.notificationUrl;

  return {
    uploadUrl: `${API_BASE}/v1_1/${cloudName}/${opts.resourceType}/upload`,
    params: { ...params, api_key: apiKey, signature: signParams(params) },
  };
}

/** Cloudinary signs every upload response with sha1("public_id=…&version=…" + secret). */
export function verifyUploadSignature(publicId: string, version: string | number, signature: string) {
  if (!publicId || !version || !/^[a-f0-9]{40}$/.test(signature || "")) return false;
  const expected = sha1(`public_id=${publicId}&version=${version}${apiSecret}`);
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

/** Webhook check: X-Cld-Signature = sha1(body + X-Cld-Timestamp + secret), not older than 2 hours. */
export function verifyNotification(rawBody: string, timestamp: string, signature: string) {
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Date.now() / 1000 - ts) > 2 * 60 * 60) return false;
  if (!/^[a-f0-9]{40}$/.test(signature || "")) return false;
  const expected = sha1(rawBody + timestamp + apiSecret);
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

// ─── Delivery URLs ──────────────────────────────────────────────────────────

const base = () => `https://res.cloudinary.com/${cloudName}`;

export function imageUrl(publicId: string, transformation = "c_limit,w_1200,q_auto,f_auto") {
  return `${base()}/image/upload/${transformation}/${publicId}`;
}

/** Adaptive streaming (HLS) — prepared by the eager transformation at upload time. */
export function videoHlsUrl(publicId: string) {
  return `${base()}/video/upload/sp_auto/${publicId}.m3u8`;
}

/** 720p MP4 fallback — also prepared at upload time. */
export function videoMp4Url(publicId: string) {
  return `${base()}/video/upload/${VIDEO_MP4_TRANSFORMATION}/${publicId}.mp4`;
}

export function videoPosterUrl(publicId: string, width = 720) {
  return `${base()}/video/upload/so_0,c_limit,w_${width},q_auto,f_jpg/${publicId}.jpg`;
}

export const VIDEO_MP4_TRANSFORMATION = "c_limit,h_1280,w_720,q_auto,vc_h264";
export const VIDEO_EAGER = `sp_auto/m3u8|${VIDEO_MP4_TRANSFORMATION}/mp4`;

/** Private images (delivery proof): signed URL that only works for this exact transformation. */
export function authenticatedImageUrl(publicId: string, transformation = "c_limit,w_1200,q_auto") {
  const path = `${transformation}/${publicId}.jpg`;
  const sig = crypto.createHash("sha1").update(path + apiSecret).digest("base64")
    .replace(/\+/g, "-").replace(/\//g, "_").slice(0, 8);
  return `${base()}/image/authenticated/s--${sig}--/${path}`;
}

/** True when a URL points at an image in our own Cloudinary account under the given folder. */
export function isOwnImageUrl(url: string, folderPrefix: string) {
  if (!mediaConfigured()) return false;
  const prefix = `${base()}/image/upload/`;
  if (!url.startsWith(prefix)) return false;
  return url.slice(prefix.length).split("/").slice(1).join("/").startsWith(folderPrefix);
}

// ─── Admin API ──────────────────────────────────────────────────────────────

function adminAuthHeader() {
  return "Basic " + Buffer.from(`${apiKey}:${apiSecret}`).toString("base64");
}

export type ResourceInfo = {
  public_id: string;
  format: string;
  bytes: number;
  width?: number;
  height?: number;
  duration?: number;
  derived?: { transformation: string; format?: string; secure_url?: string }[];
};

export async function getResource(publicId: string, resourceType: ResourceType, type: DeliveryType = "upload"): Promise<ResourceInfo | null> {
  const url = `${API_BASE}/v1_1/${cloudName}/resources/${resourceType}/${type}/${encodeURIComponent(publicId).replace(/%2F/g, "/")}`;
  const res = await fetch(url, { headers: { Authorization: adminAuthHeader() }, signal: AbortSignal.timeout(10_000) });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Cloudinary resource lookup failed (${res.status})`);
  return (await res.json()) as ResourceInfo;
}

export async function destroyResource(publicId: string, resourceType: ResourceType, type: DeliveryType = "upload") {
  if (!mediaConfigured()) return;
  const params = { public_id: publicId, timestamp: Math.floor(Date.now() / 1000), type, invalidate: "true" };
  const body = new URLSearchParams({
    ...Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)])),
    api_key: apiKey,
    signature: signParams(params),
  });
  await fetch(`${API_BASE}/v1_1/${cloudName}/${resourceType}/destroy`, {
    method: "POST",
    body,
    signal: AbortSignal.timeout(10_000),
  });
}
