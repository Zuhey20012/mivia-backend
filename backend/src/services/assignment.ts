import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

export async function assignCourierToOrder(orderId: number) {
    const courier = await prisma.courier.findFirst({ where: { status: 'available' } });
    if (!courier) return null;
    await prisma.courier.update({ where: { id: courier.id }, data: { status: 'delivering' } });
    await prisma.order.update({ where: { id: orderId }, data: { courierId: courier.id, status: 'assigned' } });
    return courier;
}
