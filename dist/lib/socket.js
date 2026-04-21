"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.initSocket = initSocket;
exports.getIo = getIo;
exports.emitCourierLocation = emitCourierLocation;
exports.emitOrderStatus = emitOrderStatus;
const socket_io_1 = require("socket.io");
let io;
function initSocket(httpServer) {
    io = new socket_io_1.Server(httpServer, {
        cors: { origin: "*" },
    });
    io.on("connection", (socket) => {
        // Client joins a room to track a specific order
        socket.on("track:order", (orderId) => {
            socket.join(`order:${orderId}`);
        });
        socket.on("track:rental", (rentalId) => {
            socket.join(`rental:${rentalId}`);
        });
        socket.on("disconnect", () => { });
    });
    return io;
}
function getIo() {
    if (!io)
        throw new Error("Socket.io not initialized");
    return io;
}
/**
 * Emit a courier location update to all clients tracking an order.
 */
function emitCourierLocation(orderId, data) {
    if (!io)
        return;
    io.to(`order:${orderId}`).emit("courier:location", data);
}
function emitOrderStatus(orderId, status) {
    if (!io)
        return;
    io.to(`order:${orderId}`).emit("order:status", { status });
}
