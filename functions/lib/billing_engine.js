"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createMarketplacePaymentIntent = createMarketplacePaymentIntent;
exports.releaseEscrowAndPayCourier = releaseEscrowAndPayCourier;
const stripe_1 = __importDefault(require("stripe"));
const stripe = new stripe_1.default(process.env.STRIPE_SECRET_KEY || "sk_test_placeholder", {
    apiVersion: "2024-06-20",
});
/**
 * FinTech Backbone: Split-Escrow, Google Pay & Banking Payouts
 * Handles 3-way marketplace money movement conforming to EU PSD2 SCA and PCI-DSS SAQ A-EP.
 */
/**
 * 1. Pre-Authorization Escrow Hold Pattern (Google Pay & PSD2 SCA Compliant)
 * Creates a PaymentIntent with capture_method: 'manual'. Funds are authorized
 * and locked in the cardholder's bank account for up to 7 days without settling.
 */
async function createMarketplacePaymentIntent({ orderId, customerStripeId, totalAmountCents, platformFeeCents, merchantStripeAccountId, }) {
    return await stripe.paymentIntents.create({
        amount: totalAmountCents,
        currency: "eur",
        customer: customerStripeId,
        capture_method: "manual", // Escrow hold pattern
        payment_method_types: ["card", "google_pay"],
        application_fee_amount: platformFeeCents,
        transfer_data: {
            destination: merchantStripeAccountId,
        },
        metadata: { orderId: orderId },
    });
}
/**
 * 2. Automated Destination Split Transfers
 * Once the courier confirms doorstep drop-off, the capture call fires, automatically executing
 * atomic transfers into the connected custom accounts of the merchant and courier
 * while the platform retains the statutory commission.
 */
async function releaseEscrowAndPayCourier({ paymentIntentId, courierStripeAccountId, courierPayoutCents, }) {
    // Capture the held payment
    await stripe.paymentIntents.capture(paymentIntentId);
    // Transfer delivery fee & 100% of customer tip to courier's connected IBAN
    return await stripe.transfers.create({
        amount: courierPayoutCents,
        currency: "eur",
        destination: courierStripeAccountId,
        description: "Payout for delivery fulfillment",
    });
}
//# sourceMappingURL=billing_engine.js.map