import { Router, Response } from "express";
import pino from "pino";
import { OrderStatus } from "@prisma/client";
import { auth, AuthRequest } from "../../middleware/auth";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { sendError, positiveId } from "../../lib/errors";
import { haversineKm } from "../../utils/distance";
import { getOrderRelation } from "./access";

const logger = pino({ name: "order-route" });

/**
 * Street route for the live tracking map (since 2.17.0): `GET /orders/:id/route`.
 *
 * - The route is **computed, never stored**: no table, no column, no log line with coordinates. A small in-memory
 *   cache per order and stage keeps the routing provider's quota and the app's battery in check; entries expire
 *   after 10 minutes (a courier → shop route after 1 minute) or as soon as the order's stage changes, and finished
 *   orders are dropped from it.
 * - Stages: `to_shop` (a courier has accepted and not picked up yet: courier → shop), `to_customer` (picked up:
 *   shop → customer), `preview` (otherwise: shop → customer, e.g. while the store prepares the order).
 * - Privacy (same rule as `orders.service.ts#withCourierPosition`, 2.16.1): a route that starts at the courier's
 *   position goes only to the order's customer and its store, and only while the order is active and assigned.
 *   Admins may open the endpoint but get the shop → customer preview instead. The courier and anyone else get 404.
 * - Provider: OpenRouteService (`ORS_API_KEY`; cycling-regular, driving-car for car/moped couriers) at the fixed host
 *   api.openrouteservice.org with a timeout; it receives two coordinate pairs and the profile, nothing else. Without
 *   a key, or when it fails, a smooth estimated path (a gentle curve between the two points) with `provider:"estimate"`.
 *   ORS_API_TEST_HOST ("host:port", plain http) is for the e2e mock only and ignored in production.
 */
export type RouteStage = "to_shop" | "to_customer" | "preview";
type LatLng = [number, number];
type Profile = "cycling-regular" | "driving-car";
export type RouteResult = { stage: RouteStage; points: LatLng[]; distanceM: number; durationS: number; provider: "openrouteservice" | "estimate" };

const ORS_HOST = "api.openrouteservice.org";
const ORS_TIMEOUT_MS = 5_000;
const CACHE_MS = 10 * 60_000;          // shop → customer routes
const COURIER_ROUTE_MS = 60_000;       // courier → shop: recomputed at most once a minute
const FAILED_RETRY_MS = 60_000;        // an estimate made because the provider failed is retried after a minute
const MAX_CACHE = 5_000;
const MAX_POINTS = 400;
/** Orders that can still be on their way; anything else (delivered, cancelled, refunded, unpaid) has no route. */
const ACTIVE: readonly OrderStatus[] = ["PENDING", "CONFIRMED", "PROCESSING", "SHIPPED"];
const COURIER_TRACKING: readonly OrderStatus[] = ["CONFIRMED", "PROCESSING", "SHIPPED"];

const round5 = (n: number) => Math.round(n * 1e5) / 1e5;

function orsBase() {
  const test = env.isProduction ? "" : (process.env.ORS_API_TEST_HOST || "").trim().toLowerCase();
  return /^[a-z0-9.-]+:\d{2,5}$/.test(test) ? `http://${test}` : `https://${ORS_HOST}`;
}
export function routingConfigured() {
  return !!(process.env.ORS_API_KEY || "").trim();
}

// ─── Cache (in memory only) ──────────────────────────────────────────────────
type Entry = { phase: string; at: number; ttl: number; route: RouteResult };
const cache = new Map<string, Entry>();
const inflight = new Map<string, Promise<RouteResult>>();

function sweep(now = Date.now()) {
  for (const [k, e] of cache) if (now - e.at >= e.ttl) cache.delete(k);
}
function forgetOrder(orderId: number) {
  const prefix = `${orderId}:`;
  for (const k of cache.keys()) if (k.startsWith(prefix)) cache.delete(k);
}
// Expired entries (a courier's route after a minute) leave memory even when nobody asks again
setInterval(() => sweep(), 60_000).unref();

/** Test helper: how many routes are held in memory (nothing else is kept anywhere). */
export function cachedRouteCount() {
  sweep();
  return cache.size;
}

// ─── Geometry ────────────────────────────────────────────────────────────────
/** Keeps at most MAX_POINTS points (first and last always), rounded to 5 decimals (~1 m), without repeats. */
function tidy(points: LatLng[]): LatLng[] {
  let pts = points;
  if (pts.length > MAX_POINTS) {
    const step = (pts.length - 1) / (MAX_POINTS - 1);
    pts = Array.from({ length: MAX_POINTS }, (_, i) => pts[Math.round(i * step)]);
  }
  const out: LatLng[] = [];
  for (const [lat, lng] of pts) {
    const p: LatLng = [round5(lat), round5(lng)];
    const last = out[out.length - 1];
    if (!last || last[0] !== p[0] || last[1] !== p[1]) out.push(p);
  }
  return out.length >= 2 ? out : [out[0] ?? [0, 0], out[0] ?? [0, 0]];
}

/**
 * A smooth estimated path: a quadratic curve that bows gently (about 8 % of the distance) to one side, sampled every
 * ~40 m (8–48 points). It reads as "a route", not as a precise street path. Distance = straight line × the road factor
 * (COURIER_ROAD_FACTOR, as courier pay uses), time at city speed (15 km/h by bike, 25 km/h by car or moped).
 */
export function estimateRoute(from: LatLng, to: LatLng, profile: Profile): Omit<RouteResult, "stage"> {
  const straightM = haversineKm(from[0], from[1], to[0], to[1]) * 1000;
  const distanceM = Math.round(straightM * env.courierPay.roadFactor);
  const kmh = profile === "driving-car" ? 25 : 15;
  const durationS = Math.round(distanceM / (kmh / 3.6));
  if (straightM < 30) return { points: tidy([from, to]), distanceM, durationS, provider: "estimate" };
  // Local flat projection around the midpoint (metres per degree), so the bow is the same on both axes
  const cos = Math.cos(((from[0] + to[0]) / 2) * Math.PI / 180);
  const dx = (to[1] - from[1]) * cos, dy = to[0] - from[0];
  const len = Math.hypot(dx, dy);
  const bow = 0.08 * len;
  // Perpendicular to the left of the direction of travel; the same two points always give the same path
  const cx = (from[1] * cos + to[1] * cos) / 2 - (dy / len) * bow;
  const cy = (from[0] + to[0]) / 2 + (dx / len) * bow;
  const n = Math.max(8, Math.min(48, Math.round(straightM / 40)));
  const pts: LatLng[] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, u = 1 - t;
    const x = u * u * from[1] * cos + 2 * u * t * cx + t * t * to[1] * cos;
    const y = u * u * from[0] + 2 * u * t * cy + t * t * to[0];
    pts.push([y, x / cos]);
  }
  return { points: tidy(pts), distanceM, durationS, provider: "estimate" };
}

async function orsRoute(from: LatLng, to: LatLng, profile: Profile): Promise<Omit<RouteResult, "stage"> | null> {
  const key = (process.env.ORS_API_KEY || "").trim();
  if (!key) return null;
  try {
    const res = await fetch(`${orsBase()}/v2/directions/${profile}/geojson`, {
      method: "POST",
      headers: { Authorization: key, "Content-Type": "application/json", Accept: "application/geo+json, application/json" },
      // ORS takes [lng, lat]; radiuses: snap each point to a road within 1 km (default 350 m fails on large yards)
      body: JSON.stringify({ coordinates: [[from[1], from[0]], [to[1], to[0]]], instructions: false, radiuses: [1000, 1000] }),
      redirect: "error",
      signal: AbortSignal.timeout(ORS_TIMEOUT_MS),
    });
    if (!res.ok) {
      logger.warn({ status: res.status, profile }, "routing provider refused");
      return null;
    }
    const text = await res.text();
    if (text.length > 2_000_000) throw new Error("response too large");
    const body = JSON.parse(text) as { features?: { geometry?: { coordinates?: unknown }; properties?: { summary?: { distance?: number; duration?: number } } }[] };
    const f = body.features?.[0];
    const coords = Array.isArray(f?.geometry?.coordinates) ? (f!.geometry!.coordinates as unknown[]) : [];
    const pts: LatLng[] = [];
    for (const c of coords) {
      if (Array.isArray(c) && Number.isFinite(c[0]) && Number.isFinite(c[1]) && Math.abs(c[1]) <= 90 && Math.abs(c[0]) <= 180) pts.push([c[1], c[0]]);
    }
    if (pts.length < 2) return null;
    const s = f?.properties?.summary ?? {};
    return {
      points: tidy(pts),
      distanceM: Math.max(0, Math.round(Number(s.distance) || 0)),
      durationS: Math.max(0, Math.round(Number(s.duration) || 0)),
      provider: "openrouteservice",
    };
  } catch (e: any) {
    // Never log coordinates; the message and profile are enough to see an outage
    logger.warn({ err: e?.message, profile }, "routing provider failed");
    return null;
  }
}

// ─── Stage and access ────────────────────────────────────────────────────────
export class RouteError extends Error {
  constructor(message: string, public status = 404) { super(message); }
}

export async function getOrderRoute(orderId: number, actor: { id: number; role: string }): Promise<RouteResult> {
  const relation = await getOrderRelation(orderId, actor);
  // The courier sees the addresses in its own app; this endpoint is for the people waiting (and admins)
  if (!relation || relation === "courier") throw new RouteError("Order not found", 404);

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      status: true, paymentStatus: true, fulfilment: true, courierId: true, pickedUpAt: true, deliveryLat: true, deliveryLng: true,
      store: { select: { latitude: true, longitude: true } },
      courier: { select: { latitude: true, longitude: true, vehicleType: true } },
    },
  });
  const active = !!order && order.fulfilment === "DELIVERY" && order.paymentStatus === "SUCCEEDED" && ACTIVE.includes(order.status);
  if (!order || !active || order.deliveryLat === null || order.deliveryLng === null || order.store.latitude === null || order.store.longitude === null) {
    forgetOrder(orderId);
    throw new RouteError("No route for this order", 404);
  }

  const shop: LatLng = [order.store.latitude, order.store.longitude];
  const home: LatLng = [order.deliveryLat, order.deliveryLng];
  const assigned = order.courierId !== null && COURIER_TRACKING.includes(order.status);
  const phase = !assigned ? "waiting" : order.status === "SHIPPED" || order.pickedUpAt ? "to_customer" : "to_shop";
  const vehicle = assigned ? order.courier?.vehicleType ?? "" : "";
  const profile: Profile = vehicle === "car" || vehicle === "moped" ? "driving-car" : "cycling-regular";

  // A route from the courier's position: only the customer and the store, only while active and assigned (2.16.1)
  const courierPos = order.courier && order.courier.latitude !== null && order.courier.longitude !== null
    ? [order.courier.latitude, order.courier.longitude] as LatLng : null;
  const mayUseCourier = (relation === "customer" || relation === "vendor") && phase === "to_shop" && !!courierPos;

  const stage: RouteStage = mayUseCourier ? "to_shop" : phase === "to_customer" ? "to_customer" : "preview";
  const [from, to] = stage === "to_shop" ? [courierPos!, shop] : [shop, home];
  const key = `${orderId}:${stage}:${profile}`;
  const now = Date.now();

  // Another stage of this order is history now
  for (const [k, e] of cache) if (k.startsWith(`${orderId}:`) && e.phase !== phase) cache.delete(k);
  const hit = cache.get(key);
  if (hit && hit.phase === phase && now - hit.at < hit.ttl) return { ...hit.route, stage };

  const pending = inflight.get(key);
  if (pending) return { ...(await pending), stage };
  const work = (async () => {
    const ors = await orsRoute(from, to, profile);
    const route: RouteResult = { stage, ...(ors ?? estimateRoute(from, to, profile)) };
    const ttl = stage === "to_shop" ? COURIER_ROUTE_MS : !ors && routingConfigured() ? FAILED_RETRY_MS : CACHE_MS;
    if (cache.size >= MAX_CACHE) {
      sweep();
      while (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value!);
    }
    cache.set(key, { phase, at: Date.now(), ttl, route });
    return route;
  })();
  inflight.set(key, work);
  try {
    return { ...(await work), stage };
  } finally {
    inflight.delete(key);
  }
}

// ─── HTTP ────────────────────────────────────────────────────────────────────
export const orderRouteRoutes = Router();

orderRouteRoutes.get("/orders/:id(\\d+)/route", auth, async (req: AuthRequest, res: Response) => {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    const route = await getOrderRoute(id, req.user!);
    // Personal and short-lived: never cached by proxies or the browser
    res.set("Cache-Control", "private, no-store");
    res.json({ ok: true, ...route });
  } catch (e) {
    sendError(res, e);
  }
});
