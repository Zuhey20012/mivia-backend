import { Router } from "express";
import healthRoutes from "./health";
import ordersRoutes from "./orders";
import authRoutes from "../modules/auth/auth.routes";

const router = Router();

router.use("/v1", healthRoutes);
router.use("/v1", ordersRoutes);
router.use("/v1/auth", authRoutes);

export default router;
