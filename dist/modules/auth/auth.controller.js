"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.register = register;
exports.login = login;
exports.refresh = refresh;
exports.logout = logout;
const auth_schema_1 = require("./auth.schema");
const authService = __importStar(require("./auth.service"));
async function register(req, res) {
    const result = auth_schema_1.registerSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const data = await authService.registerUser(result.data);
        res.status(201).json({ ok: true, ...data });
    }
    catch (e) {
        res.status(409).json({ ok: false, error: e.message });
    }
}
async function login(req, res) {
    const result = auth_schema_1.loginSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const data = await authService.loginUser(result.data);
        res.json({ ok: true, ...data });
    }
    catch (e) {
        res.status(401).json({ ok: false, error: e.message });
    }
}
async function refresh(req, res) {
    const result = auth_schema_1.refreshSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const data = await authService.refreshTokens(result.data.refreshToken);
        res.json({ ok: true, ...data });
    }
    catch (e) {
        res.status(401).json({ ok: false, error: e.message });
    }
}
async function logout(req, res) {
    const { refreshToken } = req.body;
    if (refreshToken)
        await authService.logoutUser(refreshToken);
    res.json({ ok: true });
}
