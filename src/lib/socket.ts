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

    socket.on("track:rental", (rentalId: number) => {
      socket.join(`rental:${rentalId}`);
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
  data: { lat: number; lng: number; etaMinutes: number }
) {
  if (!io) return;
  io.to(`order:${orderId}`).emit("courier:location", data);
}

export function emitOrderStatus(orderId: number, status: string) {
  if (!io) return;
  io.to(`order:${orderId}`).emit("order:status", { status });
}
