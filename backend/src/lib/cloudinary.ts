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

/** A sound track (uploaded as Cloudinary audio, i.e. resource type video), delivered as MP3 for every phone. */
export function audioMp3Url(publicId: string) {
  return `${base()}/video/upload/${publicId}.mp3`;
}

export function videoPosterUrl(publicId: string, width = 720) {
  // f_auto: WebP/AVIF where the client accepts it, JPEG otherwise (the .jpg name keeps old clients happy)
  return `${base()}/video/upload/so_0,c_limit,w_${width},q_auto,f_auto/${publicId}.jpg`;
}

/**
 * Delivery URL for a stored Cloudinary image: a plain upload URL (no transformation, e.g. `/image/upload/v123/…`)
 * gets the standard `c_limit,w_1200,q_auto,f_auto`, so every image goes out in the best format and quality for the
 * device. URLs that already carry a transformation, other hosts and anything else are returned unchanged.
 */
export function deliveryImageUrl(url: string): string {
  const m = /^(https:\/\/res\.cloudinary\.com\/[^/]+\/image\/upload\/)(v\d+\/.+)$/.exec(url);
  return m ? `${m[1]}c_limit,w_1200,q_auto,f_auto/${m[2]}` : url;
}

/** True once Cloudinary has produced the adaptive-streaming (HLS) version of a video. */
export function hlsReady(derived?: { transformation: string }[]) {
  return !!derived?.some((d) => d.transformation.startsWith("sp_auto"));
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

/** Cloudinary's Admin API ping: true when the account name, key and secret are accepted. Null when not set up. */
export async function pingCloudinary(): Promise<boolean | null> {
  if (!mediaConfigured()) return null;
  const res = await fetch(`${API_BASE}/v1_1/${cloudName}/ping`, { headers: { Authorization: adminAuthHeader() }, signal: AbortSignal.timeout(8_000) });
  if (res.status === 401 || res.status === 403) throw Object.assign(new Error("Cloudinary refused the API key or secret"), { safe: true });
  if (res.status === 404) throw Object.assign(new Error("No Cloudinary account with that cloud name"), { safe: true });
  if (!res.ok) throw Object.assign(new Error(`Cloudinary answered ${res.status}`), { safe: true });
  return true;
}

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

/**
 * Server-side upload of a remote image into our own account (catalogue import): Cloudinary fetches the
 * URL itself, so our server never downloads it. Signed with the secret; `overwrite=false` makes a repeated
 * import of the same photo return the existing upload instead of a copy.
 */
export async function uploadRemoteImage(remoteUrl: string, publicId: string): Promise<{ publicId: string; version: number }> {
  const params: Record<string, string | number> = {
    public_id: publicId,
    timestamp: Math.floor(Date.now() / 1000),
    overwrite: "false",
    allowed_formats: "jpg,jpeg,png,webp,gif,avif",
  };
  const body = new URLSearchParams({
    ...Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)])),
    file: remoteUrl,
    api_key: apiKey,
    signature: signParams(params),
  });
  const res = await fetch(`${API_BASE}/v1_1/${cloudName}/image/upload`, { method: "POST", body, signal: AbortSignal.timeout(30_000) });
  const json = (await res.json().catch(() => ({}))) as { public_id?: string; version?: number; error?: { message?: string } };
  if (!res.ok || !json.public_id) throw new Error(json.error?.message || `upload failed (${res.status})`);
  if (json.public_id !== publicId) throw new Error("upload stored under an unexpected name");
  return { publicId: json.public_id, version: Number(json.version) || 0 };
}

/**
 * Deletes every upload under a folder prefix (Admin API, max 1000 per call; repeated while Cloudinary says there
 * is more). Used when an account is deleted: the store's product photos and videos, store pictures and drops.
 */
export async function deleteByPrefix(prefix: string, resourceType: ResourceType) {
  if (!mediaConfigured()) return;
  for (let round = 0; round < 10; round++) {
    const url = `${API_BASE}/v1_1/${cloudName}/resources/${resourceType}/upload?prefix=${encodeURIComponent(prefix)}`;
    const res = await fetch(url, { method: "DELETE", headers: { Authorization: adminAuthHeader() }, signal: AbortSignal.timeout(15_000) });
    if (!res.ok) throw new Error(`Cloudinary delete by prefix failed (${res.status})`);
    const json = (await res.json().catch(() => ({}))) as { partial?: boolean };
    if (!json.partial) return;
  }
}
