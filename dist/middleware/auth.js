"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.auth = auth;
exports.requireRole = requireRole;
const jwt_1 = require("../utils/jwt");
function auth(req, res, next) {
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) {
        return res.status(401).json({ ok: false, error: "Unauthorized" });
    }
    try {
        const token = header.split(" ")[1];
        const payload = (0, jwt_1.verifyAccessToken)(token);
        req.user = { id: Number(payload.id), role: payload.role, email: payload.email };
        next();
    }
    catch {
        return res.status(401).json({ ok: false, error: "Invalid or expired token" });
    }
}
function requireRole(...roles) {
    return (req, res, next) => {
        if (!req.user || !roles.includes(req.user.role)) {
            return res.status(403).json({ ok: false, error: "Forbidden" });
        }
        next();
    };
}
