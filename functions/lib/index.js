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
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.purgeExpiredTelemetry = exports.settleOrderSplitEscrow = exports.dispatchCourierOnOrderReady = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = __importStar(require("firebase-admin"));
const geofire = __importStar(require("geofire-common"));
const stripe_1 = __importDefault(require("stripe"));
admin.initializeApp();
const stripe = new stripe_1.default(process.env.STRIPE_SECRET_KEY || "sk_test_placeholder", {
    apiVersion: "2024-06-20",
});
/**
 * 1. AUTOMATED PROXIMITY COURIER DISPATCH
 * Bipartite proximity dispatch triggered when a vendor begins preparation.
 */
exports.dispatchCourierOnOrderReady = (0, firestore_1.onDocumentUpdated)("orders/{orderId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status === "PLACED" && after?.status === "PREPARING") {
        const merchantLocation = [after.merchantLat, after.merchantLng];
        const radiusInMeters = 3500; // 3.5 km search radius
        const bounds = geofire.geohashQueryBounds(merchantLocation, radiusInMeters);
        const db = admin.firestore();
        const candidateCouriers = [];
        for (const b of bounds) {
            const q = db.collection("couriers")
                .where("isOnline", "==", true)
                .where("hasActiveOrder", "==", false)
                .orderBy("geohash")
                .startAt(b[0])
                .endAt(b[1]);
            const snaps = await q.get();
            for (const doc of snaps.docs) {
                const cData = doc.data();
                const distKm = geofire.distanceBetween([cData.lat, cData.lng], merchantLocation);
                if (distKm * 1000 <= radiusInMeters) {
                    candidateCouriers.push({ id: doc.id, distance: distKm, fcmToken: cData.fcmToken });
                }
            }
        }
        if (candidateCouriers.length > 0) {
            candidateCouriers.sort((a, b) => a.distance - b.distance);
            const chosen = candidateCouriers[0];
            await db.doc(`orders/${event.params.orderId}`).update({
                status: "COURIER_ASSIGNED",
                courierId: chosen.id,
                assignedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            if (chosen.fcmToken) {
                await admin.messaging().send({
                    token: chosen.fcmToken,
                    notification: {
                        title: "New Delivery Assigned",
                        body: `Pickup from ${after.merchantName || "Partner Store"}`,
                    },
                    data: {
                        orderId: event.params.orderId,
                        type: "ORDER_ASSIGNMENT",
                    },
                    android: { priority: "high" },
                });
            }
        }
    }
});
/**
 * 2. STRIPE SPLIT ESCROW SETTLEMENT
 * Automatic multi-sided transfer execution upon verified doorstep delivery.
 */
exports.settleOrderSplitEscrow = (0, firestore_1.onDocumentUpdated)("orders/{orderId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status === "IN_TRANSIT" && after?.status === "DELIVERED") {
        const paymentIntentId = after.paymentIntentId;
        const merchantStripeAccountId = after.merchantStripeAccountId;
        const courierStripeAccountId = after.courierStripeAccountId;
        const merchantShareCents = after.merchantAmountCents;
        const courierShareCents = after.courierAmountCents;
        if (paymentIntentId) {
            await stripe.paymentIntents.capture(paymentIntentId);
            if (merchantStripeAccountId && merchantShareCents) {
                // Merchant Net Split
                await stripe.transfers.create({
                    amount: merchantShareCents,
                    currency: "eur",
                    destination: merchantStripeAccountId,
                    source_transaction: paymentIntentId,
                });
            }
            if (courierStripeAccountId && courierShareCents) {
                // Courier Split (Base + Distance + Tips)
                await stripe.transfers.create({
                    amount: courierShareCents,
                    currency: "eur",
                    destination: courierStripeAccountId,
                    source_transaction: paymentIntentId,
                });
            }
        }
    }
});
/**
 * 3. GDPR 60-MINUTE TELEMETRY PURGE CRON
 * Storage minimization cron permanently scrubbing high-resolution trajectory trails.
 */
exports.purgeExpiredTelemetry = (0, scheduler_1.onSchedule)("every 60 minutes", async () => {
    const rtdb = admin.database();
    const firestore = admin.firestore();
    const threshold = Date.now() - (60 * 60 * 1000);
    const deliveredOrders = await firestore.collection("orders")
        .where("status", "==", "DELIVERED")
        .where("deliveredAt", "<=", admin.firestore.Timestamp.fromMillis(threshold))
        .get();
    for (const doc of deliveredOrders.docs) {
        await rtdb.ref(`live_tracking/${doc.id}`).remove();
    }
});
// Re-export Enterprise Subsystems
__exportStar(require("./notifications"), exports);
__exportStar(require("./billing_engine"), exports);
__exportStar(require("./gdpr_engine"), exports);
__exportStar(require("./european_fashion_escrow"), exports);
__exportStar(require("./operations_core"), exports);
//# sourceMappingURL=index.js.map