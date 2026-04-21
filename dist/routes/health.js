"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const router = (0, express_1.Router)();
router.get("/health", (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));
exports.default = router;
