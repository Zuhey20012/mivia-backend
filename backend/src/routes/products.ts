import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const router = Router();

router.get('/', async (req, res) => {
    const { category } = req.query;
    const where: any = {};
    if (category) where.category = String(category);
    const products = await prisma.product.findMany({ where, include: { variants: true, vendor: true } });
    res.json({ ok: true, products });
});

router.get('/:id', async (req, res) => {
    const id = Number(req.params.id);
    const product = await prisma.product.findUnique({ where: { id }, include: { variants: true, vendor: true } });
    if (!product) return res.status(404).json({ ok: false, message: 'Not found' });
    res.json({ ok: true, product });
});

export default router;
