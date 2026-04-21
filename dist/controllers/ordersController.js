"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createOrderHandler = createOrderHandler;
const ordersService_1 = require("../services/ordersService");
async function createOrderHandler(req, res) {
    try {
        const { userId, vendorId, total } = req.body;
        if (!userId || !vendorId || !total) {
            return res.status(400).json({ ok: false, error: "Missing fields" });
        }
        const order = await (0, ordersService_1.createOrder)({ userId: Number(userId), vendorId: Number(vendorId), total: Number(total) });
        res.status(201).json({ ok: true, order });
    }
    catch (e) {
        console.error(e);
        res.status(500).json({ ok: false, error: "Failed to create order" });
    }
}
