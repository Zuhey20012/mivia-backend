import { prisma } from "../lib/prisma";
import { assignmentQueue } from "../lib/queue";

export async function createOrder(input: { userId: number; vendorId: number; total: number }) {
  const order = await prisma.order.create({
    data: {
      userId: input.userId,
      storeId: input.vendorId,
      total: input.total
    } as any
  });

  await assignmentQueue.add("assign", { orderId: order.id });
  return order;
}
