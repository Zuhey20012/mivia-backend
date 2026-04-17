"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
const router = (0, express_1.Router)();
router.post('/', async (req, res) => {
    const { productId, userId, startDate, endDate, deposit, cleaningFee } = req.body;
    if (!productId || !userId || !startDate || !endDate)
        return res.status(400).json({ ok: false, message: 'Missing fields' });
    const rental = await prisma.rental.create({
        data: { productId, userId, startDate: new Date(startDate), endDate: new Date(endDate), deposit: deposit || 0, cleaningFee: cleaningFee || 0 }
    });
    res.json({ ok: true, rental });
});
exports.default = router;
