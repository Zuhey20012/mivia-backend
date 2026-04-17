import { Router } from 'express';
const router = Router();
// near other imports
import adminRouter from './routes/admin';

// after app.use(productsRouter);
app.use(adminRouter);

router.get('/admin/health', (_req, res) => {
    res.json({ ok: true, time: new Date().toISOString() });
});

export default router;
