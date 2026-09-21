import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

if (!admin.apps.length) {
  admin.initializeApp();
}

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY || "sk_test_placeholder", {
  apiVersion: "2024-06-20",
});

const STATUTORY_EU_VAT: Record<string, number> = {
  FI: 0.255, // Finland Standard VAT (25.5%)
  SE: 0.250, // Sweden Standard VAT (25.0%)
  DE: 0.190, // Germany Standard VAT (19.0%)
  FR: 0.200, // France Standard VAT (20.0%)
  DK: 0.250, // Denmark Standard VAT (25.0%)
};

export const createEuropeanApparelEscrow = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be authenticated.");
  const { garmentId, boutiqueId, countryCode, selectedSizes } = request.data;
  const db = admin.firestore();
  const [garmentDoc, boutiqueDoc] = await Promise.all([
    db.collection("garments").doc(garmentId).get(),
    db.collection("boutiques").doc(boutiqueId).get(),
  ]);

  if (!garmentDoc.exists || !boutiqueDoc.exists) {
    throw new HttpsError("not-found", "Garment or boutique record missing.");
  }

  const garmentData = garmentDoc.data()!;
  const boutiqueData = boutiqueDoc.data()!;

  // European VAT Destination Lookup
  const vatRate = STATUTORY_EU_VAT[countryCode] ?? 0.255;
  const unitPriceNetCents = garmentData.priceNetCents;
  const unitPriceGrossCents = Math.round(unitPriceNetCents * (1 + vatRate));
  // Dynamic concierge fitting fee resolved from boutique profile or request payload
  const fittingFeeCents = typeof request.data.fittingFeeCents === 'number'
    ? request.data.fittingFeeCents
    : (boutiqueData.conciergeFittingFeeCents ?? boutiqueData.fittingFeeCents ?? 0);

  // Pre-auth locks single garment price plus fitting fee
  const totalPreAuthAmountCents = unitPriceGrossCents + fittingFeeCents;

  const paymentIntent = await stripe.paymentIntents.create({
    amount: totalPreAuthAmountCents,
    currency: "eur",
    customer: request.auth.uid,
    capture_method: "manual", // Escrow hold pattern
    payment_method_types: ["card", "google_pay"],
    transfer_data: {
      destination: boutiqueData.stripeAccountId,
    },
    metadata: {
      garmentId,
      boutiqueId,
      tryAtHomeSizes: selectedSizes.join(","),
      countryCode,
      vatRate: vatRate.toString(),
    },
  });

  return { clientSecret: paymentIntent.client_secret, totalPreAuthAmountCents };
});

export const finalizeTryAtHomeFitting = onCall(async (request) => {
  const { paymentIntentId, returnedSkuBarcode, keptSkuBarcode } = request.data;
  const db = admin.firestore();
  const intent = await stripe.paymentIntents.retrieve(paymentIntentId);
  const garmentId = intent.metadata.garmentId;

  // 1. Capture the single kept garment + fitting fee
  await stripe.paymentIntents.capture(paymentIntentId);

  // 2. Instant Restock to Local H3 Grid (<60 minutes)
  await db.collection("garments").doc(garmentId).update({
    [`skuInventory.${returnedSkuBarcode}`]: admin.firestore.FieldValue.increment(1),
  });

  return { status: "SETTLED_AND_RESTOCKED", kept: keptSkuBarcode, returned: returnedSkuBarcode };
});
