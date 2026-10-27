import { Server as HttpServer } from "http";
import { Server as SocketServer, Socket } from "socket.io";
import { verifyAccessToken } from "../utils/jwt";
import { adminNeedsMfa } from "../middleware/auth";
import { prisma } from "./prisma";
import { env } from "../config/env";
import { getOrderRelation, getRentalRelation, getCourierForUser } from "../modules/orders/access";
import { haversineKm } from "../utils/distance";
import { pushToUser } from "./push";
import { t } from "./i18n";
import { canReadChat, chatHistory, postMessage } from "../modules/orders/chat";
import { createAdapter } from "@socket.io/redis-adapter";
import { Emitter } from "@socket.io/redis-emitter";
import { createRedisClient, redis, redisEnabled, rkey } from "./redis";

let io: SocketServer | null = null;

type SocketUser = { id: number; role: string; email: string };

const LOCATION_DB_WRITE_INTERVAL_MS = 15_000;
/** "Your courier is arriving" goes out once, when a carried order is this close to the door. */
const ARRIVING_RADIUS_KM = 0.3;

function toId(value: unknown): number | null {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function toCoord(value: unknown, limit: number): number | null {
  const n = Number(value);
  return Number.isFinite(n) && Math.abs(n) <= limit ? n : null;
}

export function initSocket(httpServer: HttpServer): SocketServer {
  io = new SocketServer(httpServer, {
    cors: { origin: env.allowedOrigins.length ? env.allowedOrigins : false, credentials: true },
    maxHttpBufferSize: 16 * 1024,
  });
  // Several instances: rooms and emits are shared through Redis, so an event emitted on one instance reaches a
  // client connected to another. Without REDIS_URL rooms are local to this process, as before.
  if (redisEnabled()) {
    io.adapter(createAdapter(createRedisClient("socket-pub"), createRedisClient("socket-sub", { blocking: true }), { key: SOCKET_KEY }));
  }

  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.headers.authorization?.split(" ")[1];
      if (!token) return next(new Error("Authentication error"));
      const user = verifyAccessToken(token);
      // An admin who has not passed two-step sign-in while it is required gets nothing live either
      if (adminNeedsMfa(user)) return next(new Error("Authentication error"));
      socket.data.user = user as SocketUser;
      next();
    } catch {
      next(new Error("Authentication error"));
    }
  });

  io.on("connection", async (socket: Socket) => {
    const user = socket.data.user as SocketUser;
    socket.join(`user:${user.id}`);

    // Role-specific rooms are joined server-side, never on the client's say-so. The handlers below are registered
    // at once (an app emits chat:join right after connecting) and wait for this where they need it.
    const ready = (async () => {
      try {
        if (user.role === "VENDOR") {
          const store = await prisma.store.findUnique({ where: { ownerId: user.id }, select: { id: true } });
          if (store) socket.join(`store:${store.id}`);
        }
        if (user.role === "COURIER") {
          const courier = await getCourierForUser(user.id);
          if (courier?.isApproved) {
            socket.data.courierId = courier.id;
            socket.join(`courier:${courier.id}`);
            socket.join("couriers");
          }
        }
      } catch {
        // DB hiccup: the client can still join per-order rooms below
      }
    })();

    // Kept for app compatibility: only lets a vendor into their own store room.
    socket.on("track:store", async (storeId: unknown) => {
      const id = toId(storeId);
      if (!id || user.role !== "VENDOR") return;
      const store = await prisma.store.findFirst({ where: { id, ownerId: user.id }, select: { id: true } }).catch(() => null);
      if (store) socket.join(`store:${id}`);
    });

    socket.on("track:order", async (orderId: unknown) => {
      const id = toId(orderId);
      if (id && (await getOrderRelation(id, user).catch(() => null))) socket.join(`order:${id}`);
    });

    socket.on("track:rental", async (rentalId: unknown) => {
      const id = toId(rentalId);
      if (id && (await getRentalRelation(id, user).catch(() => null))) socket.join(`rental:${id}`);
    });

    // ── Courier live location ──────────────────────────────────────────────
    const verifiedCourierOrders = new Set<number>();
    // Destination of each verified order, for the one-time "arriving" notification
    const destinations = new Map<number, { lat: number; lng: number; userId: number; notified: boolean; triedAt: number }>();
    let lastDbWrite = 0;

    const handleLocation = async (data: any) => {
      await ready;
      const courierId = socket.data.courierId as number | undefined;
      const orderId = toId(data?.orderId);
      const lat = toCoord(data?.lat ?? data?.latitude, 90);
      const lng = toCoord(data?.lng ?? data?.longitude, 180);
      if (!courierId || !orderId || lat === null || lng === null) return;

      if (!verifiedCourierOrders.has(orderId)) {
        const order = await prisma.order.findFirst({
          where: { id: orderId, courierId, status: { in: ["CONFIRMED", "PROCESSING", "SHIPPED"] } },
          select: { id: true, userId: true, deliveryLat: true, deliveryLng: true, arrivingNotifiedAt: true },
        }).catch(() => null);
        if (!order) return;
        verifiedCourierOrders.add(orderId);
        if (order.deliveryLat !== null && order.deliveryLng !== null) {
          destinations.set(orderId, { lat: order.deliveryLat, lng: order.deliveryLng, userId: order.userId, notified: !!order.arrivingNotifiedAt, triedAt: 0 });
        }
      }

      io!.to(`order:${orderId}`).emit("courier:location", {
        orderId,
        lat,
        lng,
        bearing: Number(data?.bearing) || 0,
        speed: Number(data?.speed) || 0,
        accuracy: Number(data?.accuracy) || 0,
        etaMinutes: toId(data?.etaMinutes) ?? undefined,
        timestamp: Date.now(),
      });

      const dest = destinations.get(orderId);
      // Near the door before pickup (status not SHIPPED yet) is retried at most every 30 s
      if (dest && !dest.notified && Date.now() - dest.triedAt > 30_000 && haversineKm(lat, lng, dest.lat, dest.lng) <= ARRIVING_RADIUS_KM) {
        dest.notified = true;
        dest.triedAt = Date.now();
        // Only once per order and only after pickup, even across reconnects and several instances
        prisma.order.updateMany({ where: { id: orderId, status: "SHIPPED", arrivingNotifiedAt: null }, data: { arrivingNotifiedAt: new Date() } })
          .then((r) => {
            if (!r.count) { dest.notified = false; return; }
            pushToUser(dest.userId, {
              title: t("Your courier is arriving", "Lähetti on pian perillä"),
              body: t(`Order #${orderId} is almost at your door.`, `Tilaus #${orderId} on melkein ovellasi.`),
              data: { type: "order", orderId: String(orderId) },
            }).catch(() => {});
            io!.to(`order:${orderId}`).emit("order:status", { orderId, arriving: true, timestamp: new Date().toISOString() });
          })
          .catch(() => { dest.notified = false; });
      }

      if (Date.now() - lastDbWrite > LOCATION_DB_WRITE_INTERVAL_MS) {
        lastDbWrite = Date.now();
        prisma.courier.update({ where: { id: courierId }, data: { latitude: lat, longitude: lng, locationAt: new Date() } }).catch(() => {});
      }
    };
    socket.on("courier:telemetry", handleLocation);
    socket.on("courier:update_location", handleLocation);

    // ── In-delivery chat (stored; see modules/orders/chat.ts) ──────────────
    // The ack (when the app passes one) carries the recent history: { ok, messages }
    socket.on("chat:join", async (orderId: unknown, ack?: unknown) => {
      const id = toId(orderId);
      const reply = typeof ack === "function" ? (ack as (r: unknown) => void) : null;
      const relation = id ? await getOrderRelation(id, user).catch(() => null) : null;
      if (!id || !relation) return reply?.({ ok: false, error: "Order not found" });
      socket.join(`chat:${id}`);
      if (!reply) return;
      const readable = await canReadChat(id, user).catch(() => false);
      reply({ ok: true, messages: readable ? await chatHistory(id).catch(() => []) : [] });
    });

    socket.on("chat:send", async (data: any, ack?: unknown) => {
      const reply = typeof ack === "function" ? (ack as (r: unknown) => void) : null;
      const orderId = toId(data?.orderId);
      const text = typeof data?.text === "string" ? data.text : "";
      if (!orderId || !text.trim() || !socket.rooms.has(`chat:${orderId}`)) return reply?.({ ok: false, error: "Join the order chat first" });
      try {
        const message = await postMessage(orderId, user, text, typeof data?.sender === "string" ? data.sender : undefined);
        reply?.({ ok: true, message });
      } catch (e: any) {
        reply?.({ ok: false, error: typeof e?.status === "number" && e.status < 500 ? e.message : "Message not sent" });
      }
    });
  });

  return io;
}

export function getIo(): SocketServer | null {
  return io;
}

/** Sockets connected to this instance (metrics). */
export function localSocketConnections(): number {
  return io?.engine?.clientsCount ?? 0;
}

const SOCKET_KEY = rkey("socket.io");
let emitter: Emitter | null = null;

/**
 * Where emits go: this process's socket server, or (in the separate background worker, which has no socket server)
 * the Redis emitter, which hands the event to whichever API instance holds the room's clients.
 */
function target(): { to(room: string): { emit(event: string, ...args: any[]): unknown } } | null {
  if (io) return io;
  const r = redis();
  if (!r) return null;
  if (!emitter) emitter = new Emitter(r, { key: SOCKET_KEY });
  return emitter;
}

export function emitOrderStatus(orderId: number, payload: Record<string, unknown>) {
  target()?.to(`order:${orderId}`).emit("order:status", { orderId, ...payload, timestamp: new Date().toISOString() });
}

export function emitToStore(storeId: number, event: string, payload: unknown) {
  target()?.to(`store:${storeId}`).emit(event, payload);
}

export function emitToCourier(courierId: number, event: string, payload: unknown) {
  target()?.to(`courier:${courierId}`).emit(event, payload);
}

export function emitToAllCouriers(event: string, payload: unknown) {
  target()?.to("couriers").emit(event, payload);
}
