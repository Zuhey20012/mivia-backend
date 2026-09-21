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
exports.executeRightToBeForgotten = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const stripe_1 = __importDefault(require("stripe"));
const stripe = new stripe_1.default(process.env.STRIPE_SECRET_KEY || "sk_test_placeholder", {
    apiVersion: "2024-06-20",
});
/**
 * GDPR Article 17: Right to Erasure ("Right to be Forgotten")
 * Self-service account deletion trigger executing cascade deletion across:
 * 1. External payment records (Stripe customer scrub)
 * 2. Firestore user profile & cart sessions
 * 3. Ephemeral telemetry and RTDB presence nodes
 * 4. Firebase Authentication identity
 */
exports.executeRightToBeForgotten = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const uid = request.auth.uid;
    const db = admin.firestore();
    const rtdb = admin.database();
    try {
        // 1. Fetch customer metadata for external service scrub
        const userDoc = await db.collection("users").doc(uid).get();
        const userData = userDoc.data();
        // 2. Anonymize external payment records in Stripe
        if (userData?.stripeCustomerId) {
            try {
                await stripe.customers.del(userData.stripeCustomerId);
            }
            catch (err) {
                console.warn("Stripe customer erasure notice:", err);
            }
        }
        // 3. Cascade wipe across Firestore collections
        const batch = db.batch();
        batch.delete(db.collection("users").doc(uid));
        batch.delete(db.collection("cart_sessions").doc(uid));
        await batch.commit();
        // 4. Scrub ephemeral telemetry and RTDB presence nodes
        try {
            await rtdb.ref(`user_presence/${uid}`).remove();
            await rtdb.ref(`live_tracking/${uid}`).remove();
        }
        catch (rtdbErr) {
            console.warn("RTDB presence scrub notice:", rtdbErr);
        }
        // 5. Delete Firebase Authentication Identity
        await admin.auth().deleteUser(uid);
        return {
            success: true,
            message: "Account and personal data permanently purged in compliance with GDPR Art. 17.",
        };
    }
    catch (error) {
        throw new https_1.HttpsError("internal", error.message || "Failed to execute account erasure.");
    }
});
//# sourceMappingURL=gdpr_engine.js.map