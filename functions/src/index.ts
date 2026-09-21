import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as geofire from "geofire-common";
import Stripe from "stripe";

admin.initializeApp();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || "sk_test_placeholder", {
  apiVersion: "2024-06-20",
});

/**
 * 1. AUTOMATED PROXIMITY COURIER DISPATCH
 * Bipartite proximity dispatch triggered when a vendor begins preparation.
 */
export const dispatchCourierOnOrderReady = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (before?.status === "PLACED" && after?.status === "PREPARING") {
    const merchantLocation: [number, number] = [after.merchantLat, after.merchantLng];
    const radiusInMeters = 3500; // 3.5 km search radius
    const bounds = geofire.geohashQueryBounds(merchantLocation, radiusInMeters);
    const db = admin.firestore();
    const candidateCouriers: Array<{ id: string; distance: number; fcmToken: string }> = [];

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
export const settleOrderSplitEscrow = onDocumentUpdated("orders/{orderId}", async (event) => {
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
export const purgeExpiredTelemetry = onSchedule("every 60 minutes", async () => {
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
export * from "./notifications";
export * from "./billing_engine";
export * from "./gdpr_engine";
export * from "./european_fashion_escrow";
export * from "./operations_core";
