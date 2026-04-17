import { Router } from 'express';
const router = Router();
router.get('/', (req, res) => res.json({ ok: true, uptime: process.uptime() }));
export default router;
