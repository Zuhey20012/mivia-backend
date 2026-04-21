"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createOrder = createOrder;
const prisma_1 = require("../lib/prisma");
const queue_1 = require("../lib/queue");
async function createOrder(input) {
    const order = await prisma_1.prisma.order.create({
        data: {
            userId: input.userId,
            storeId: input.vendorId,
            total: input.total
        }
    });
    await queue_1.assignmentQueue.add("assign", { orderId: order.id });
    return order;
}
