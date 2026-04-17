import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const router = Router();

router.get('/', async (req, res) => {
    const vendors = await prisma.vendor.findMany();
    res.json({ ok: true, vendors });
});

export default router;
