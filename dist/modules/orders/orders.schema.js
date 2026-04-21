"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateReturnStatusSchema = exports.createReturnSchema = exports.createRentalSchema = exports.createOrderSchema = void 0;
const zod_1 = require("zod");
exports.createOrderSchema = zod_1.z.object({
    storeId: zod_1.z.number().int().positive(),
    deliveryAddress: zod_1.z.string().min(5),
    deliveryLat: zod_1.z.number().optional(),
    deliveryLng: zod_1.z.number().optional(),
    notes: zod_1.z.string().max(500).optional(),
    items: zod_1.z.array(zod_1.z.object({
        productId: zod_1.z.number().int().positive(),
        variantId: zod_1.z.number().int().positive().optional(),
        quantity: zod_1.z.number().int().min(1),
    })).min(1),
});
exports.createRentalSchema = zod_1.z.object({
    startDate: zod_1.z.string().datetime(),
    endDate: zod_1.z.string().datetime(),
    deliveryAddress: zod_1.z.string().min(5),
    items: zod_1.z.array(zod_1.z.object({
        productId: zod_1.z.number().int().positive(),
        variantId: zod_1.z.number().int().positive().optional(),
        quantity: zod_1.z.number().int().min(1),
    })).min(1),
}).refine(d => new Date(d.endDate) > new Date(d.startDate), {
    message: "endDate must be after startDate",
}).refine(d => new Date(d.startDate) > new Date(), {
    message: "startDate must be in the future",
});
exports.createReturnSchema = zod_1.z.object({
    orderId: zod_1.z.number().int().positive().optional(),
    rentalId: zod_1.z.number().int().positive().optional(),
    reason: zod_1.z.enum(["WRONG_ITEM", "DAMAGED_ON_ARRIVAL", "NOT_AS_DESCRIBED", "CHANGED_MIND", "RENTAL_RETURN", "OTHER"]),
    conditionNote: zod_1.z.string().max(500).optional(),
}).refine(d => d.orderId || d.rentalId, {
    message: "Must provide either orderId or rentalId",
}).refine(d => !(d.orderId && d.rentalId), {
    message: "Cannot provide both orderId and rentalId",
});
exports.updateReturnStatusSchema = zod_1.z.object({
    status: zod_1.z.enum(["APPROVED", "IN_TRANSIT", "RECEIVED", "REFUNDED", "REJECTED"]),
    conditionNote: zod_1.z.string().max(500).optional(),
    refundCents: zod_1.z.number().int().min(0).optional(),
    damageDedCents: zod_1.z.number().int().min(0).optional(),
});
