"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assignCourierToOrder = assignCourierToOrder;
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
async function assignCourierToOrder(orderId) {
    const courier = await prisma.courier.findFirst({ where: { status: 'available' } });
    if (!courier)
        return null;
    await prisma.courier.update({ where: { id: courier.id }, data: { status: 'delivering' } });
    await prisma.order.update({ where: { id: orderId }, data: { courierId: courier.id, status: 'assigned' } });
    return courier;
}
