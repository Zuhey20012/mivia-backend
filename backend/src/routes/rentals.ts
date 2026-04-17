import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const router = Router();

router.post('/', async (req, res) => {
    const { productId, userId, startDate, endDate, deposit, cleaningFee } = req.body;
    if (!productId || !userId || !startDate || !endDate) return res.status(400).json({ ok: false, message: 'Missing fields' });

    const rental = await prisma.rental.create({
        data: { productId, userId, startDate: new Date(startDate), endDate: new Date(endDate), deposit: deposit || 0, cleaningFee: cleaningFee || 0 }
    });

    res.json({ ok: true, rental });
});

export default router;
