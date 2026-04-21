"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const ordersController_1 = require("../controllers/ordersController");
const router = (0, express_1.Router)();
router.post("/orders", ordersController_1.createOrderHandler);
exports.default = router;
