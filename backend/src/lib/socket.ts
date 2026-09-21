import { Server as HttpServer } from "http";
import { Server as SocketServer } from "socket.io";

let io: SocketServer;

export function initSocket(httpServer: HttpServer): SocketServer {
  io = new SocketServer(httpServer, {
    cors: { origin: "*" },
  });

  io.on("connection", (socket) => {
    // Client joins a room to track a specific order
    socket.on("track:order", (orderId: number) => {
      socket.join(`order:${orderId}`);
    });

    socket.on('track:store', (storeId) => {
      socket.join(`store:${storeId}`);
      console.log(`[Socket] Client joined store room: store:${storeId}`);
    });

    socket.on("track:rental", (rentalId: number) => {
      socket.join(`rental:${rentalId}`);
    });

    // Courier updates location during delivery transit (high-precision telemetry stream)
    socket.on("courier:telemetry", (data: {
      courierId: number;
      orderId?: number;
      lat: number;
      lng: number;
      bearing?: number;
      speed?: number;
      accuracy?: number;
      etaMinutes?: number;
    }) => {
      if (data && data.lat && data.lng) {
        if (data.orderId) {
          io.to(`order:${data.orderId}`).emit("courier:location", {
            courierId: data.courierId,
            orderId: data.orderId,
            lat: data.lat,
            lng: data.lng,
            bearing: data.bearing ?? 0,
            speed: data.speed ?? 0,
            accuracy: data.accuracy ?? 5.0,
            etaMinutes: data.etaMinutes ?? 15,
            timestamp: Date.now(),
          });
        }
      }
    });

    socket.on("courier:update_location", (data: { orderId: number; lat: number; lng: number; etaMinutes?: number; bearing?: number }) => {
      if (data && data.orderId && data.lat && data.lng) {
        emitCourierLocation(data.orderId, {
          lat: data.lat,
          lng: data.lng,
          bearing: data.bearing ?? 0,
          etaMinutes: data.etaMinutes ?? 15,
        });
      }
    });

    // In-transit chat message relay
    socket.on("chat:join", (orderId: number) => {
      socket.join(`chat:${orderId}`);
    });

    socket.on("chat:send", (data: { orderId: number; sender: string; text: string; role: string }) => {
      if (data && data.orderId && data.text) {
        io.to(`chat:${data.orderId}`).emit("chat:message", {
          ...data,
          timestamp: new Date().toISOString(),
        });
      }
    });

    socket.on("disconnect", () => {});
  });

  return io;
}

export function getIo(): SocketServer {
  if (!io) throw new Error("Socket.io not initialized");
  return io;
}

/**
 * Emit a courier location update to all clients tracking an order.
 */
export function emitCourierLocation(
  orderId: number,
  data: { lat: number; lng: number; bearing?: number; etaMinutes: number }
) {
  if (!io) return;
  io.to(`order:${orderId}`).emit("courier:location", data);
}

export function emitOrderStatus(orderId: number, status: string) {
  if (!io) return;
  io.to(`order:${orderId}`).emit("order:status", { status });
}

export function emitNewOrderToStore(storeId: number | string, orderData: any) {
  const io = getIo();
  if (io) {
    io.to(`store:${storeId}`).emit('order:new', orderData);
    console.log(`[Socket] Emitted order:new to store:${storeId}`);
  }
}

export function emitOrderStatusToStore(storeId: number | string, statusData: any) {
  const io = getIo();
  if (io) {
    io.to(`store:${storeId}`).emit('order:status', statusData);
  }
}
