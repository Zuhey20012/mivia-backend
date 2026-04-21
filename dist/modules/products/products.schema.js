"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.productQuerySchema = exports.updateProductSchema = exports.createProductSchema = void 0;
const zod_1 = require("zod");
exports.createProductSchema = zod_1.z.object({
    name: zod_1.z.string().min(2).max(200),
    description: zod_1.z.string().max(2000).optional(),
    category: zod_1.z.string().min(1),
    condition: zod_1.z.enum(["NEW", "LIKE_NEW", "GOOD", "FAIR", "POOR"]).default("NEW"),
    tags: zod_1.z.array(zod_1.z.string()).default([]),
    canBeSold: zod_1.z.boolean().default(true),
    salePriceCents: zod_1.z.number().int().positive().optional(),
    canBeRented: zod_1.z.boolean().default(false),
    rentalDayCents: zod_1.z.number().int().positive().optional(),
    depositCents: zod_1.z.number().int().positive().optional(),
    stockQuantity: zod_1.z.number().int().min(1).default(1),
    isEcoFriendly: zod_1.z.boolean().default(false),
    isHandmade: zod_1.z.boolean().default(false),
    isSecondHand: zod_1.z.boolean().default(false),
    variants: zod_1.z.array(zod_1.z.object({
        size: zod_1.z.string().optional(),
        color: zod_1.z.string().optional(),
        sku: zod_1.z.string().optional(),
        stock: zod_1.z.number().int().default(1),
        priceAdjustCents: zod_1.z.number().int().default(0),
    })).default([]),
}).refine(d => d.canBeSold ? !!d.salePriceCents : true, {
    message: "salePriceCents required when canBeSold is true",
}).refine(d => d.canBeRented ? !!d.rentalDayCents && !!d.depositCents : true, {
    message: "rentalDayCents and depositCents required when canBeRented is true",
});
exports.updateProductSchema = exports.createProductSchema.innerType().innerType().partial();
exports.productQuerySchema = zod_1.z.object({
    canBeSold: zod_1.z.string().optional(),
    canBeRented: zod_1.z.string().optional(),
    isEcoFriendly: zod_1.z.string().optional(),
    isSecondHand: zod_1.z.string().optional(),
    search: zod_1.z.string().optional(),
    minPrice: zod_1.z.string().optional(),
    maxPrice: zod_1.z.string().optional(),
    condition: zod_1.z.string().optional(),
    page: zod_1.z.string().default("1"),
    limit: zod_1.z.string().default("20"),
});
