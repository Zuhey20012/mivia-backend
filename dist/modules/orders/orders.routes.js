"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../../middleware/auth");
const orders_controller_1 = require("./orders.controller");
const router = (0, express_1.Router)();
// Orders
router.post("/orders", auth_1.auth, (0, auth_1.requireRole)("CUSTOMER"), orders_controller_1.createOrder);
router.get("/orders", auth_1.auth, orders_controller_1.listOrders);
router.get("/orders/:id", auth_1.auth, orders_controller_1.getOrder);
// Rentals
router.post("/rentals", auth_1.auth, (0, auth_1.requireRole)("CUSTOMER"), orders_controller_1.createRental);
router.get("/rentals", auth_1.auth, orders_controller_1.listRentals);
router.get("/rentals/:id", auth_1.auth, orders_controller_1.getRental);
// Returns
router.post("/returns", auth_1.auth, orders_controller_1.createReturn);
router.get("/returns/:id", auth_1.auth, orders_controller_1.getReturn);
router.patch("/returns/:id/status", auth_1.auth, (0, auth_1.requireRole)("VENDOR", "ADMIN"), orders_controller_1.updateReturnStatus);
exports.default = router;
