"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.firebaseLinkSchema = exports.firebaseSignInSchema = exports.refreshSchema = exports.loginSchema = exports.registerSchema = void 0;
const zod_1 = require("zod");
exports.registerSchema = zod_1.z.object({
    name: zod_1.z.string().min(2).max(80),
    email: zod_1.z.string().email(),
    phone: zod_1.z.string().optional(),
    password: zod_1.z.string().min(8),
    role: zod_1.z.enum(["CUSTOMER", "VENDOR", "COURIER"]).default("CUSTOMER"),
});
exports.loginSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    password: zod_1.z.string().min(1),
});
exports.refreshSchema = zod_1.z.object({
    refreshToken: zod_1.z.string().min(1),
});
// Body for Firebase sign-in: the ID token from FirebaseUser.getIdToken() on the client.
// name/role are only used when the call creates a new account.
exports.firebaseSignInSchema = zod_1.z.object({
    idToken: zod_1.z.string().min(1),
    name: zod_1.z.string().min(2).max(80).optional(),
    role: zod_1.z.enum(["CUSTOMER", "VENDOR", "COURIER"]).default("CUSTOMER"),
});
exports.firebaseLinkSchema = zod_1.z.object({
    idToken: zod_1.z.string().min(1),
});
