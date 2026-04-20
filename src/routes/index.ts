import { Router } from "express";
import healthRoutes from "./health";
import ordersRoutes from "./orders";
const router = Router();
router.use("/v1", healthRoutes);
router.use("/v1", ordersRoutes);
export default router;
