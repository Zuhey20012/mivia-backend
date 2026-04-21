"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.storeQuerySchema = exports.updateStoreSchema = exports.createStoreSchema = void 0;
const zod_1 = require("zod");
exports.createStoreSchema = zod_1.z.object({
    name: zod_1.z.string().min(2).max(100),
    description: zod_1.z.string().max(1000).optional(),
    category: zod_1.z.enum(["APPAREL", "COSMETICS", "THRIFT", "ACCESSORIES", "HOME_DECOR", "HANDMADE", "ECO_FRIENDLY", "OTHER"]),
    isHomeBased: zod_1.z.boolean().default(false),
    isEcoFriendly: zod_1.z.boolean().default(false),
    address: zod_1.z.string().optional(),
    latitude: zod_1.z.number().optional(),
    longitude: zod_1.z.number().optional(),
    phone: zod_1.z.string().optional(),
    email: zod_1.z.string().email().optional(),
});
exports.updateStoreSchema = exports.createStoreSchema.partial();
exports.storeQuerySchema = zod_1.z.object({
    category: zod_1.z.string().optional(),
    isHomeBased: zod_1.z.string().optional(),
    search: zod_1.z.string().optional(),
    page: zod_1.z.string().default("1"),
    limit: zod_1.z.string().default("20"),
});
