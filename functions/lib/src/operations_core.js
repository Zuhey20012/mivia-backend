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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.onOrderReadyDispatch = exports.sendPhoneOtp = void 0;
exports.emitVatCompliantReceipt = emitVatCompliantReceipt;
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const geofire = __importStar(require("geofire-common"));
const twilio_1 = __importDefault(require("twilio"));
const mail_1 = __importDefault(require("@sendgrid/mail"));
if (!admin.apps.length) {
    admin.initializeApp();
}
const twilioClient = (0, twilio_1.default)(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
mail_1.default.setApiKey(process.env.SENDGRID_API_KEY || "SG_PLACEHOLDER");
// 1. DISPATCH TWILIO SMS OTP
exports.sendPhoneOtp = (0, https_1.onCall)(async (request) => {
    const { phoneNumber } = request.data;
    if (!phoneNumber)
        throw new https_1.HttpsError("invalid-argument", "Phone number required.");
    const verification = await twilioClient.verify.v2
        .services(process.env.TWILIO_VERIFY_SERVICE_SID)
        .verifications.create({ to: phoneNumber, channel: "sms" });
    return { status: verification.status };
});
// 2. DISPATCH MATCHING ENGINE ON "READY"
exports.onOrderReadyDispatch = (0, firestore_1.onDocumentUpdated)("orders/{orderId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status !== "READY" && after?.status === "READY") {
        const boutiqueLat = after.boutiqueLocation.lat;
        const boutiqueLng = after.boutiqueLocation.lng;
        const radiusMeters = 3500;
        const bounds = geofire.geohashQueryBounds([boutiqueLat, boutiqueLng], radiusMeters);
        const db = admin.firestore();
        const candidates = [];
        for (const b of bounds) {
            const snaps = await db.collection("couriers")
                .where("isOnline", "==", true)
                .where("hasActiveTask", "==", false)
                .orderBy("geohash")
                .startAt(b[0])
                .endAt(b[1])
                .get();
            for (const doc of snaps.docs) {
                const c = doc.data();
                const d = geofire.distanceBetween([c.lat, c.lng], [boutiqueLat, boutiqueLng]);
                if (d * 1000 <= radiusMeters) {
                    candidates.push({ id: doc.id, dist: d, fcm: c.fcmToken });
                }
            }
        }
        if (candidates.length > 0) {
            candidates.sort((a, b) => a.dist - b.dist);
            const matchedCourier = candidates[0];
            await db.doc(`orders/${event.params.orderId}`).update({
                status: "COURIER_ASSIGNED",
                courierId: matchedCourier.id,
                assignedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            await admin.messaging().send({
                token: matchedCourier.fcm,
                notification: {
                    title: "New Apparel Delivery (€8.50)",
                    body: `Pickup at ${after.boutiqueName}`,
                },
                data: { orderId: event.params.orderId, action: "OFFER_ACCEPT" },
                android: { priority: "high" },
            });
        }
    }
});
// 3. EMIT FINNISH ALV COMPLIANT RECEIPT (SENDGRID)
async function emitVatCompliantReceipt(order) {
    await mail_1.default.send({
        to: order.customerEmail,
        from: "receipts@nordicqapparel.fi",
        subject: `Tilausvahvistus ja ALV-kuitti / Receipt #${order.id}`,
        html: `
<div style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 600px; margin: auto; padding: 20px;">
  <h2 style="color: #0f172a;">Tilausvahvistus / Order Confirmation</h2>
  <p>Order: <strong>#${order.id}</strong></p>
  <p>Boutique: <strong>${order.boutiqueName}</strong></p>
  <hr style="border: none; border-top: 1px solid #e2e8f0;" />
  <p>Item Kept: ${order.keptGarmentTitle}</p>
  <p><strong>Total Charged: €${order.totalGrossEur}</strong></p>
  <p style="color: #64748b; font-size: 12px;">Includes Finnish ALV 25.5%: €${order.alvAmountEur}</p>
  <p style="color: #64748b; font-size: 11px;">Nordic Q-Apparel Commerce Oy • Y-tunnus: 3491823-1 • Helsinki, Finland</p>
</div>
`,
    });
}
//# sourceMappingURL=operations_core.js.map