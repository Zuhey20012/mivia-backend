import crypto from "crypto";
import jwt from "jsonwebtoken";
import pino from "pino";
import { ApiError } from "./errors";

/**
 * LiveKit (WebRTC) for live shopping (since 2.15.0). The store publishes its camera to a LiveKit room and viewers
 * subscribe; the API only hands out access tokens (JWT HS256 signed with LIVEKIT_API_SECRET, no server SDK) and
 * calls the RoomService (Twirp) to list rooms (Test connections) and to close a room when a live ends.
 * Without LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET live video is off (503 LIVE_OFF). Nothing is recorded.
 */
const logger = pino({ name: "livekit" });

/** The longest a token is valid; a live lasts at most 4 h. */
const TOKEN_TTL_SECONDS = 4 * 3600 + 15 * 60;

function config() {
  const url = (process.env.LIVEKIT_URL || "").trim();
  const apiKey = (process.env.LIVEKIT_API_KEY || "").trim();
  const apiSecret = (process.env.LIVEKIT_API_SECRET || "").trim();
  return url && apiKey && apiSecret ? { url, apiKey, apiSecret } : null;
}

export function liveConfigured() {
  return !!config();
}

export class LiveOffError extends ApiError {
  constructor() {
    super("Live video is not switched on yet", 503);
    this.extra = { code: "LIVE_OFF" };
  }
}

function requireConfig() {
  const c = config();
  if (!c) throw new LiveOffError();
  return c;
}

type VideoGrant = {
  room?: string; roomJoin?: boolean; canPublish?: boolean; canSubscribe?: boolean; canPublishData?: boolean;
  roomList?: boolean; roomAdmin?: boolean; roomCreate?: boolean;
};

function sign(c: { apiKey: string; apiSecret: string }, identity: string | undefined, video: VideoGrant, ttlSeconds: number, name?: string) {
  const now = Math.floor(Date.now() / 1000);
  return jwt.sign(
    { ...(name ? { name } : {}), video, nbf: now, exp: now + ttlSeconds },
    c.apiSecret,
    { algorithm: "HS256", issuer: c.apiKey, ...(identity ? { subject: identity, jwtid: identity } : {}) },
  );
}

/**
 * A token for one participant of one room. The store publishes (camera + microphone); viewers only subscribe.
 * Nobody may send data messages through LiveKit: chat goes through the API (stored, moderated).
 */
export function participantToken(input: { room: string; identity: string; name: string; canPublish: boolean }) {
  const c = requireConfig();
  const token = sign(c, input.identity, {
    room: input.room, roomJoin: true, canPublish: input.canPublish, canSubscribe: true, canPublishData: false,
  }, TOKEN_TTL_SECONDS, input.name.slice(0, 100));
  return { url: c.url, token };
}

/** Random part of room names and guest identities. */
export function randomId(bytes = 6) {
  return crypto.randomBytes(bytes).toString("hex");
}

/** wss://host → https://host (the RoomService API is plain HTTPS on the same host). */
function apiBase(url: string) {
  return url.replace(/^ws(s?):\/\//i, "http$1://").replace(/\/+$/, "");
}

async function roomService(method: string, body: Record<string, unknown>, grant: VideoGrant, timeoutMs: number) {
  const c = requireConfig();
  const token = sign(c, undefined, grant, 600);
  const res = await fetch(`${apiBase(c.url)}/twirp/livekit.RoomService/${method}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  return res;
}

/** Test connections: true when LiveKit accepts the key (lists rooms), false when it refuses, null when not set up. */
export async function pingLiveKit(): Promise<{ ok: boolean | null; rooms?: number; status?: number }> {
  if (!config()) return { ok: null };
  const res = await roomService("ListRooms", {}, { roomList: true }, 8000);
  if (!res.ok) return { ok: false, status: res.status };
  const json = (await res.json().catch(() => ({}))) as { rooms?: unknown[] };
  return { ok: true, rooms: Array.isArray(json.rooms) ? json.rooms.length : 0 };
}

/** Closes a room when its live ends, so every viewer and the store are disconnected (best effort). */
export async function closeRoom(room: string) {
  if (!config()) return;
  try {
    const res = await roomService("DeleteRoom", { room }, { roomCreate: true, roomAdmin: true, room }, 5000);
    // 404: nobody ever joined (LiveKit creates rooms on first join), nothing to close
    if (!res.ok && res.status !== 404) logger.warn({ room, status: res.status }, "LiveKit did not close the room");
  } catch (err: any) {
    logger.warn({ room, err: err?.message }, "Could not reach LiveKit to close the room");
  }
}
