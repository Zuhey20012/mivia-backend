import { Router } from "express";
import { auth, requireRole } from "../../middleware/auth";
import {
  createOrder, listOrders, getOrder,
  createRental, listRentals, getRental,
  createReturn, getReturn, updateReturnStatus,
} from "./orders.controller";

const router = Router();

// Orders
router.post("/orders",       auth, requireRole("CUSTOMER"), createOrder);
router.get("/orders",        auth, listOrders);
router.get("/orders/:id",    auth, getOrder);

// Rentals
router.post("/rentals",      auth, requireRole("CUSTOMER"), createRental);
router.get("/rentals",       auth, listRentals);
router.get("/rentals/:id",   auth, getRental);

// Returns
router.post("/returns",               auth, createReturn);
router.get("/returns/:id",            auth, getReturn);
router.patch("/returns/:id/status",   auth, requireRole("VENDOR","ADMIN"), updateReturnStatus);

export default router;
