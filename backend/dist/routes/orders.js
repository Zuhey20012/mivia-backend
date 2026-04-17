"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const assignment_1 = require("../services/assignment");
const eta_1 = require("../services/eta");
const notifications_1 = require("../services/notifications");
const prisma = new client_1.PrismaClient();
const router = (0, express_1.Router)();
router.get('/', async (req, res) => {
    const orders = await prisma.order.findMany({ include: { courier: true } });
    res.json({ ok: true, orders });
});
router.post('/', async (req, res) => {
    const { userId, items, total, type } = req.body;
    if (!userId || !items || !total)
        return res.status(400).json({ ok: false, message: 'Missing fields' });
    const order = await prisma.order.create({ data: { userId, items, total, type: type || 'purchase' } });
    const courier = await (0, assignment_1.assignCourierToOrder)(order.id);
    const eta = (0, eta_1.calculateETA)(3.2);
    await (0, notifications_1.sendNotification)(userId, 'Your order is confirmed and a courier is on the way.');
    res.json({ ok: true, order, courier, eta });
});
exports.default = router;
