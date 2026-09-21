import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as geofire from "geofire-common";
import twilio from "twilio";
import sgMail from "@sendgrid/mail";

if (!admin.apps.length) {
  admin.initializeApp();
}

const twilioClient = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
sgMail.setApiKey(process.env.SENDGRID_API_KEY || "SG_PLACEHOLDER");

// 1. DISPATCH TWILIO SMS OTP
export const sendPhoneOtp = onCall(async (request) => {
  const { phoneNumber } = request.data;
  if (!phoneNumber) throw new HttpsError("invalid-argument", "Phone number required.");
  const verification = await twilioClient.verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID!)
    .verifications.create({ to: phoneNumber, channel: "sms" });
  return { status: verification.status };
});

// 2. DISPATCH MATCHING ENGINE ON "READY"
export const onOrderReadyDispatch = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (before?.status !== "READY" && after?.status === "READY") {
    const boutiqueLat = after.boutiqueLocation.lat;
    const boutiqueLng = after.boutiqueLocation.lng;
    const radiusMeters = 3500;
    const bounds = geofire.geohashQueryBounds([boutiqueLat, boutiqueLng], radiusMeters);
    const db = admin.firestore();
    const candidates: Array<{ id: string; dist: number; fcm: string }> = [];

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

      const courierPayoutEur = after.courierPayoutEur 
        ? ` (€${Number(after.courierPayoutEur).toFixed(2)})` 
        : after.deliveryFee 
          ? ` (€${Number(after.deliveryFee).toFixed(2)})` 
          : "";

      await admin.messaging().send({
        token: matchedCourier.fcm,
        notification: {
          title: `New Apparel Delivery${courierPayoutEur}`,
          body: `Pickup at ${after.boutiqueName || "Boutique"}`,
        },
        data: { orderId: event.params.orderId, action: "OFFER_ACCEPT" },
        android: { priority: "high" },
      });
    }
  }
});

// 3. EMIT FINNISH ALV COMPLIANT RECEIPT (SENDGRID)
export async function emitVatCompliantReceipt(order: {
  id: string;
  customerEmail: string;
  boutiqueName: string;
  totalGrossEur: string;
  alvAmountEur: string;
  keptGarmentTitle: string;
}) {
  await sgMail.send({
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
