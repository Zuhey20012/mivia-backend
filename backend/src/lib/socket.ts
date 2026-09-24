import { Server as HttpServer } from "http";
import { Server as SocketServer, Socket } from "socket.io";
import { verifyAccessToken } from "../utils/jwt";
import { prisma } from "./prisma";
import { env } from "../config/env";
import { getOrderRelation, getRentalRelation, getCourierForUser } from "../modules/orders/access";

let io: SocketServer | null = null;

type SocketUser = { id: number; role: string; email: string };

const LOCATION_DB_WRITE_INTERVAL_MS = 15_000;

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

  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.headers.authorization?.split(" ")[1];
      if (!token) return next(new Error("Authentication error"));
      socket.data.user = verifyAccessToken(token) as SocketUser;
      next();
    } catch {
      next(new Error("Authentication error"));
    }
  });

  io.on("connection", async (socket: Socket) => {
    const user = socket.data.user as SocketUser;
    socket.join(`user:${user.id}`);

    // Role-specific rooms are joined server-side, never on the client's say-so.
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
    let lastDbWrite = 0;

    const handleLocation = async (data: any) => {
      const courierId = socket.data.courierId as number | undefined;
      const orderId = toId(data?.orderId);
      const lat = toCoord(data?.lat ?? data?.latitude, 90);
      const lng = toCoord(data?.lng ?? data?.longitude, 180);
      if (!courierId || !orderId || lat === null || lng === null) return;

      if (!verifiedCourierOrders.has(orderId)) {
        const order = await prisma.order.findFirst({
          where: { id: orderId, courierId, status: { in: ["CONFIRMED", "PROCESSING", "SHIPPED"] } },
          select: { id: true },
        }).catch(() => null);
        if (!order) return;
        verifiedCourierOrders.add(orderId);
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

      if (Date.now() - lastDbWrite > LOCATION_DB_WRITE_INTERVAL_MS) {
        lastDbWrite = Date.now();
        prisma.courier.update({ where: { id: courierId }, data: { latitude: lat, longitude: lng } }).catch(() => {});
      }
    };
    socket.on("courier:telemetry", handleLocation);
    socket.on("courier:update_location", handleLocation);

    // ── In-delivery chat (relayed, not stored) ─────────────────────────────
    socket.on("chat:join", async (orderId: unknown) => {
      const id = toId(orderId);
      if (id && (await getOrderRelation(id, user).catch(() => null))) socket.join(`chat:${id}`);
    });

    socket.on("chat:send", (data: any) => {
      const orderId = toId(data?.orderId);
      const text = typeof data?.text === "string" ? data.text.trim().slice(0, 1000) : "";
      if (!orderId || !text || !socket.rooms.has(`chat:${orderId}`)) return;
      io!.to(`chat:${orderId}`).emit("chat:message", {
        orderId,
        text,
        senderId: user.id,
        role: user.role,
        sender: typeof data?.sender === "string" ? data.sender.slice(0, 60) : user.role,
        timestamp: new Date().toISOString(),
      });
    });
  });

  return io;
}

export function getIo(): SocketServer | null {
  return io;
}

export function emitOrderStatus(orderId: number, payload: Record<string, unknown>) {
  io?.to(`order:${orderId}`).emit("order:status", { orderId, ...payload, timestamp: new Date().toISOString() });
}

export function emitToStore(storeId: number, event: string, payload: unknown) {
  io?.to(`store:${storeId}`).emit(event, payload);
}

export function emitToCourier(courierId: number, event: string, payload: unknown) {
  io?.to(`courier:${courierId}`).emit(event, payload);
}

export function emitToAllCouriers(event: string, payload: unknown) {
  io?.to("couriers").emit(event, payload);
}
