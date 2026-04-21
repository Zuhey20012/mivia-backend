"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const health_1 = __importDefault(require("./health"));
const orders_1 = __importDefault(require("./orders"));
const router = (0, express_1.Router)();
router.use("/v1", health_1.default);
router.use("/v1", orders_1.default);
exports.default = router;
