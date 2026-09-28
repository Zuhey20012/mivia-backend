import { Router } from "express";
import { auth, requireRole } from "../../middleware/auth";
import {
  createOrder, listOrders, getOrder, cancelOrder, updateOrderStatus,
  createRental, listRentals, getRental,
  createReturn, listReturns, getReturn, updateReturnStatus,
  deliverOrder, getDeliveryProof,
} from "./orders.controller";

const router = Router();

// Orders — `:id(\\d+)` keeps paths like /orders/available (courier router) from being captured here.
router.post("/orders",                        auth, requireRole("CUSTOMER"), createOrder);
router.get("/orders",                         auth, listOrders);
router.get("/orders/:id(\\d+)",               auth, getOrder);
router.post("/orders/:id(\\d+)/cancel",       auth, requireRole("CUSTOMER"), cancelOrder);
// Store, assigned courier and admin share one endpoint; the service enforces who may do which transition.
router.patch("/orders/:id(\\d+)/status",      auth, requireRole("VENDOR", "COURIER", "ADMIN"), updateOrderStatus);
// Courier completes the delivery (in person, or at the door with a photo)
router.post("/orders/:id(\\d+)/deliver",      auth, requireRole("COURIER"), deliverOrder);
router.get("/orders/:id(\\d+)/proof",         auth, getDeliveryProof);

// Rentals
router.post("/rentals",                       auth, requireRole("CUSTOMER"), createRental);
router.get("/rentals",                        auth, listRentals);
router.get("/rentals/:id(\\d+)",              auth, getRental);

// Returns
router.post("/returns",                       auth, requireRole("CUSTOMER"), createReturn);
router.get("/returns",                        auth, listReturns);
router.get("/returns/:id(\\d+)",              auth, getReturn);
router.patch("/returns/:id(\\d+)/status",     auth, requireRole("VENDOR", "ADMIN"), updateReturnStatus);

export default router;
