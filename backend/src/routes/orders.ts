import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
import { assignCourierToOrder } from '../services/assignment';
import { calculateETA } from '../services/eta';
import { sendNotification } from '../services/notifications';
const prisma = new PrismaClient();
const router = Router();

router.get('/', async (req, res) => {
    const orders = await prisma.order.findMany({ include: { courier: true } });
    res.json({ ok: true, orders });
});

router.post('/', async (req, res) => {
    const { userId, items, total, type } = req.body;
    if (!userId || !items || !total) return res.status(400).json({ ok: false, message: 'Missing fields' });

    const order = await prisma.order.create({ data: { userId, items, total, type: type || 'purchase' } });

    const courier = await assignCourierToOrder(order.id);
    const eta = calculateETA(3.2);
    await sendNotification(userId, 'Your order is confirmed and a courier is on the way.');

    res.json({ ok: true, order, courier, eta });
});

export default router;
