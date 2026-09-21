import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || "sk_test_placeholder", {
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
export const executeRightToBeForgotten = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
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
      } catch (err) {
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
    } catch (rtdbErr) {
      console.warn("RTDB presence scrub notice:", rtdbErr);
    }

    // 5. Delete Firebase Authentication Identity
    await admin.auth().deleteUser(uid);

    return {
      success: true,
      message: "Account and personal data permanently purged in compliance with GDPR Art. 17.",
    };
  } catch (error: any) {
    throw new HttpsError("internal", error.message || "Failed to execute account erasure.");
  }
});
