"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.calcOrderPricing = calcOrderPricing;
exports.calcRentalPricing = calcRentalPricing;
exports.formatCents = formatCents;
const env_1 = require("../config/env");
/**
 * Calculate all pricing fields for a SALE order.
 * All values returned in cents (integers).
 */
function calcOrderPricing(subtotalCents) {
    const commissionCents = Math.round(subtotalCents * env_1.env.commissionRate);
    const sellerPayoutCents = subtotalCents - commissionCents;
    const deliveryFeeCents = env_1.env.deliveryFeeCents;
    const totalCents = subtotalCents + deliveryFeeCents;
    return { subtotalCents, commissionCents, sellerPayoutCents, deliveryFeeCents, totalCents };
}
/**
 * Calculate all pricing fields for a RENTAL.
 */
function calcRentalPricing(dailyCents, quantity, days, depositCents) {
    const subtotalCents = dailyCents * quantity * days;
    const commissionCents = Math.round(subtotalCents * env_1.env.commissionRate);
    const deliveryFeeCents = env_1.env.deliveryFeeCents;
    const totalCents = subtotalCents + depositCents + deliveryFeeCents;
    return { subtotalCents, commissionCents, depositCents, deliveryFeeCents, totalCents };
}
/**
 * Format cents to a display string.
 * e.g. 4999 → "$49.99"
 */
function formatCents(cents, currency = "USD") {
    return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}
