import { Router } from "express";
import { createOrderHandler } from "../controllers/ordersController";
const router = Router();
router.post("/orders", createOrderHandler);
export default router;
