import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const router = Router();

router.get('/', async (req, res) => {
    const couriers = await prisma.courier.findMany();
    res.json({ ok: true, couriers });
});

export default router;
