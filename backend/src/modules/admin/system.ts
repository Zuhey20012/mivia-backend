import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { securityContacts } from "../ops/ops.routes";
import { env } from "../../config/env";
import { mediaConfigured } from "../../lib/cloudinary";
import { pushConfigured } from "../../lib/push";
import { sendError } from "../../lib/errors";
import { storeAvailability } from "../../utils/openingHours";
import { MIN_CHARGE_CENTS, deliveryFeeForDistance } from "../../utils/pricing";
import { approachPayFor, calcCourierPay, payRuleSummary, routeKm, waitPayFor } from "../../utils/courierPay";
import { appConfigSummary } from "../appConfig/appConfig.routes";
import { referralSummary } from "../referrals/referrals.service";
import { ordersPayingOutMoreThanCharged } from "../payouts/payouts.service";
import { encryptionStatus } from "../../lib/fieldCrypto";
import { taxInfoComplete, taxRowSelect } from "../sellers/taxInfo";
import { availableSlots } from "../../utils/deliverySlots";
import { readyForApprovalList } from "../onboarding/onboarding";
import { unpublishedLegalChanges } from "../legal/admin.legal";
import { LEGAL_DOCS, DOC_KEYS, legalState, versionText } from "../legal/legalDocs";

const startedAt = new Date();

/**
 * Courier pay settings and what Malvoya keeps on example jobs (customer delivery fee − courier pay, tips
 * excluded). Courier pay is set separately from the customer price, so the margin can be negative.
 * Examples are straight-line shop → customer distances, with no ride-to-shop pay, waiting or tip.
 */
export function courierPaySummary() {
  const cfg = env.courierPay;
  const examples = [1, 3, 6].map((straightKm) => {
    const customerFeeCents = deliveryFeeForDistance(straightKm);
    const pay = calcCourierPay({ straightKm, deliveryFeeCents: customerFeeCents });
    return {
      straightKm,
      routeKm: pay.distanceKm,
      customerFeeCents,
      courierPayCents: pay.totalCents,
      marginCents: customerFeeCents - pay.totalCents,
      explanation: pay.explanation,
    };
  });
  const formula = cfg.mode === "formula";
  return {
    ...cfg,
    summary: payRuleSummary(cfg),
    // Extra pay on top of the examples
    waitExample: { minutes: 10, cents: formula ? waitPayFor(10, cfg) : 0 },
    approachExample: { straightKm: 4, routeKm: routeKm(4, cfg), cents: formula ? approachPayFor(routeKm(4, cfg), cfg) : 0 },
    examples,
  };
}

/** What is switched on. Only yes/no and test/live — never a key or a secret. */
export function integrationStatus() {
  const stripeMode = env.stripeSecretKey.startsWith("sk_live_") || env.stripeSecretKey.startsWith("rk_live_")
    ? "live"
    : env.stripeSecretKey ? "test" : "off";
  return {
    payments: { configured: !!env.stripeSecretKey, mode: stripeMode },
    paymentWebhook: { configured: !!env.stripeWebhookSecret },
    email: { configured: !!(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) },
    supportInbox: { configured: !!process.env.SUPPORT_EMAIL },
    sms: { configured: !!(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER) },
    pushNotifications: { configured: pushConfigured() },
    photosAndVideos: { configured: mediaConfigured() },
    googleSignIn: { configured: !!env.googleClientId },
    // DATA_ENCRYPTION_KEY: needed to save sellers' tax IDs (DAC7); "invalid" = set but not 32 bytes of base64
    dataEncryption: { configured: encryptionStatus() === "ok", status: encryptionStatus() },
  };
}

/**
 * One screen that answers "can Malvoya take an order right now, and does anything need a human?".
 */
export async function getSystemStatus(_req: Request, res: Response) {
  try {
    const t = env.orderTimers;
    const fresh = new Date(Date.now() - 10 * 60_000);
    const [
      liveStores, pendingStores, approvedCouriers, onlineCouriers, pendingCouriers, waitlist,
      waitingForStore, waitingForCourier, refundProblems, failedPayouts, openSupport, openReports, jobs,
      waitingForPickup, referrals, overPaid, taxStores, scheduledUpcoming, deliveryProblems, reportedReviews,
    ] = await Promise.all([
      prisma.store.findMany({ where: { isVerified: true }, select: { acceptingOrders: true, openingHours: true } }),
      prisma.store.count({ where: { isVerified: false } }),
      prisma.courier.count({ where: { isApproved: true, userId: { not: null } } }),
      prisma.courier.count({ where: { isApproved: true, isActive: true, updatedAt: { gte: fresh } } }),
      prisma.courier.count({ where: { isApproved: false, userId: { not: null } } }),
      prisma.launchAlert.count({ where: { notifiedAt: null } }),
      prisma.order.count({ where: { status: "PENDING", paymentStatus: "SUCCEEDED" } }),
      prisma.order.count({ where: { status: { in: ["CONFIRMED", "PROCESSING"] }, paymentStatus: "SUCCEEDED", courierId: null, fulfilment: "DELIVERY", OR: [{ scheduledStart: null }, { dispatchStartedAt: { not: null } }] } }),
      // Cancelled but the money was not given back automatically (refund call failed). An order taken back to the
      // shop keeps the delivery fee and tip, so it counts only while its items have not been refunded.
      prisma.$queryRaw<{ n: bigint }[]>`
        SELECT count(*)::bigint AS n FROM "Order" WHERE status = 'CANCELLED' AND "paymentStatus" = 'SUCCEEDED'
          AND ("returnedToStoreAt" IS NULL OR "refundedCents" < GREATEST(0, LEAST("subtotalCents" - "discountCents", "totalCents")))`
        .then((r) => Number(r[0]?.n ?? 0)),
      prisma.payout.count({ where: { status: "FAILED" } }),
      prisma.supportRequest.count({ where: { status: "OPEN" } }).catch(() => 0),
      prisma.dropReport.count({ where: { status: "OPEN" } }),
      prisma.jobLease.findMany({ select: { name: true, lastRunAt: true } }),
      prisma.order.count({ where: { fulfilment: "PICKUP", status: "PROCESSING", paymentStatus: "SUCCEEDED" } }),
      referralSummary(),
      ordersPayingOutMoreThanCharged(),
      // DAC7: live stores and whether their tax data is complete
      prisma.store.findMany({ where: { isVerified: true }, select: { sellerType: true, businessId: true, taxInfo: { select: taxRowSelect } }, take: 5000 }),
      // Scheduled deliveries whose courier search has not started yet
      prisma.order.count({ where: { status: { in: ["CONFIRMED", "PROCESSING"] }, paymentStatus: "SUCCEEDED", courierId: null, fulfilment: "DELIVERY", dispatchStartedAt: null, scheduledStart: { gt: new Date() } } }),
      // Couriers at the address who cannot reach the customer right now
      prisma.order.findMany({
        where: { status: "SHIPPED", deliveryProblemAt: { not: null } },
        select: { id: true, deliveryProblemAt: true, deliveryProblemReason: true },
        orderBy: { deliveryProblemAt: "asc" },
        take: 20,
      }),
      prisma.review.count({ where: { reports: { some: { resolvedAt: null } } } }),
    ]);
    const missingTax = taxStores.filter((st) => !taxInfoComplete(st, st.taxInfo)).length;
    const storesOpenNow = liveStores.filter((s) => storeAvailability(s).openNow).length;
    const integrations = integrationStatus();

    // Plain-language checklist: what still blocks a real paid order
    const blockers: string[] = [];
    if (!integrations.payments.configured) blockers.push("Payments are off: add STRIPE_SECRET_KEY on Render.");
    else if (integrations.payments.mode === "test") blockers.push("Payments are in Stripe test mode: no real money moves yet.");
    if (!integrations.paymentWebhook.configured) blockers.push("Paid orders are never confirmed: add STRIPE_WEBHOOK_SECRET on Render.");
    if (!integrations.pushNotifications.configured) blockers.push("No push notifications: stores and couriers will not hear about new orders. Add FIREBASE_SERVICE_ACCOUNT.");
    if (!integrations.photosAndVideos.configured) blockers.push("Photo and video uploads are off: add the three CLOUDINARY_* settings.");
    if (process.env.MAINTENANCE_MESSAGE?.trim()) blockers.push("Maintenance message is on: the apps show it instead of letting people order. Remove MAINTENANCE_MESSAGE on Render to reopen.");
    // Legal texts in force that still have [PLACEHOLDERS] (company name, Y-tunnus, address…): consumer law needs the
    // trader's identity before real sales
    const unfinishedLegal = (await Promise.all(DOC_KEYS.map(async (doc) => {
      const cur = (await legalState(doc).catch(() => null))?.current;
      const text = cur ? await versionText(doc, cur.version).catch(() => null) : null;
      return text && /\[[A-Z][A-Z0-9 _/.,'-]{2,}\]/.test(text.textSnapshot) ? LEGAL_DOCS[doc].title.en : null;
    }))).filter((x): x is string => !!x);
    if (unfinishedLegal.length) {
      blockers.push(`Legal texts in force still have unfilled [PLACEHOLDERS] (company name, Y-tunnus, address, dates): ${unfinishedLegal.join(", ")}. Fill them in legal/*.md and publish them on Legal.`);
    }
    if (liveStores.length === 0) blockers.push("No approved stores yet.");
    if (approvedCouriers === 0) blockers.push("No approved couriers yet.");

    const attention: string[] = [];
    if (pendingStores) attention.push(`${pendingStores} store(s) waiting for approval`);
    if (pendingCouriers) attention.push(`${pendingCouriers} courier(s) waiting for approval`);
    if (refundProblems) attention.push(`${refundProblems} cancelled order(s) still need a refund — check Stripe`);
    if (failedPayouts) attention.push(`${failedPayouts} failed payout(s)`);
    if (openSupport) attention.push(`${openSupport} open support request(s)`);
    if (openReports) attention.push(`${openReports} open content report(s)`);
    if (reportedReviews) attention.push(`${reportedReviews} reported review(s) to look at (Moderation → Reported reviews)`);
    for (const p of deliveryProblems) {
      const min = Math.max(0, Math.round((Date.now() - p.deliveryProblemAt!.getTime()) / 60_000));
      const why = p.deliveryProblemReason === "WRONG_ADDRESS" ? "cannot find the address" : p.deliveryProblemReason === "CUSTOMER_UNAVAILABLE" ? "cannot reach the customer" : "cannot deliver";
      attention.push(`Order #${p.id}: the courier ${why} (reported ${min} min ago)`);
    }
    if (missingTax) attention.push(`${missingTax} store(s) missing tax data (DAC7): they are asked for it in the store app; the yearly report to Vero is due by 31 January`);
    if (integrations.dataEncryption.status === "missing") attention.push("Sellers' tax IDs cannot be saved: add DATA_ENCRYPTION_KEY (32 random bytes, base64, e.g. openssl rand -base64 32) on Render. Keep a copy: without it saved tax IDs cannot be read.");
    if (integrations.dataEncryption.status === "invalid") attention.push("DATA_ENCRYPTION_KEY is set but is not 32 bytes of base64: tax IDs cannot be saved or read until it is fixed.");
    // Onboarding finished, waiting for an admin (2.11)
    const [ready, legalDrafts] = await Promise.all([readyForApprovalList(), unpublishedLegalChanges().catch(() => [])]);
    for (const s of ready.stores) attention.push(`Store "${s.name}" (#${s.id}) is ready for approval (Vendors)`);
    for (const c of ready.couriers) attention.push(`Courier "${c.name}" (#${c.id}) is ready for approval (Couriers)`);
    for (const d of legalDrafts) attention.push(`${LEGAL_DOCS[d.doc].title.en}: the text in the repository has changed but is not published; the published version stays in force until you publish it (Legal)`);
    // Product safety and certificates (2.12)
    const [openProductReports, pendingCerts, uncategorised] = await Promise.all([
      prisma.productReport.count({ where: { status: "OPEN" } }),
      prisma.certificate.count({ where: { status: "PENDING" } }),
      prisma.product.count({ where: { isAvailable: true, deletedAt: null, categoryId: null } }),
    ]);
    if (openProductReports) attention.push(`${openProductReports} product report(s) to decide: product-safety notices within 3 working days (Product reports)`);
    if (pendingCerts) attention.push(`${pendingCerts} certificate(s) waiting for verification (Certificates)`);
    if (uncategorised) attention.push(`${uncategorised} visible product(s) made before 2.12 have no category and miss the required product information; ask the stores to complete them`);
    if (overPaid) attention.push(`${overPaid} delivered order(s) pay the store and courier more than the customer paid; Malvoya's Stripe balance covers the difference`);
    if (!securityContacts().length) attention.push("No security contact: set SECURITY_CONTACT (an email address you read) on Render, so /.well-known/security.txt tells researchers where to report a vulnerability.");
    // Two-step sign-in for admins (2.13)
    const [admins, adminsWithTwoStep] = await Promise.all([
      prisma.user.count({ where: { role: "ADMIN", isActive: true } }),
      prisma.user.count({ where: { role: "ADMIN", isActive: true, totpEnabledAt: { not: null } } }),
    ]);
    if (admins > adminsWithTwoStep) {
      attention.push(`${admins - adminsWithTwoStep} admin account(s) without two-step sign-in${env.adminMfaRequired ? " (they can only set it up until they do: Security)" : ": turn it on under Security"}`);
    }

    res.json({
      ok: true,
      version: "2.14.0",
      region: "frankfurt",
      startedAt,
      readyForOrders: blockers.length === 0,
      blockers,
      attention,
      integrations,
      security: { adminTwoStepRequired: env.adminMfaRequired, admins, adminsWithTwoStep },
      marketplace: {
        liveStores: liveStores.length, storesOpenNow, pendingStores,
        approvedCouriers, onlineCouriers, pendingCouriers,
        waitlist,
      },
      // Stores and couriers that finished onboarding (everything but approval), oldest first
      readyForApproval: ready,
      ordersInFlight: { waitingForStore, waitingForCourier, waitingForPickup, scheduledUpcoming, deliveryProblems: deliveryProblems.length },
      timers: t,
      // Reserve & collect (PICKUP_REMINDER_HOURS / PICKUP_HOLD_HOURS), counted from "ready for pickup"
      pickup: env.pickupTimers,
      // Scheduled delivery (DELIVERY_SLOTS, SCHEDULED_DELIVERY_DISCOUNT_CENTS), Finnish time; slots open now for an always-open store
      scheduledDelivery: { ...env.scheduledDelivery, bookableNow: availableSlots({ openingHours: null }).map((x) => ({ date: x.date, start: x.start, end: x.end, label: x.label })) },
      // Invite a friend (REFERRAL_DISCOUNT_CENTS / REFERRAL_REWARD_CENTS; off while the discount is 0)
      referrals,
      // Android App Links (ANDROID_APP_SHA256) published at /.well-known/assetlinks.json
      appLinks: { fingerprints: env.androidAppSha256.length, url: `${env.publicApiUrl}/.well-known/assetlinks.json` },
      // Fee levers (0 = off). Changed with env vars on Render; promo codes live under /admin/promo-codes.
      pricing: {
        ...env.pricing,
        courierFeeShare: env.courierPay.feeShare, // used only when courierPay.mode = "fee_share"
        minChargeCents: MIN_CHARGE_CENTS,
        // Courier pay per job (COURIER_PAY_* env vars) and the delivery margin on example jobs
        courierPay: courierPaySummary(),
        // Customer delivery fee by distance (DELIVERY_FEE_* env vars); flat fee when the distance is unknown
        deliveryFee: { ...env.deliveryFee, unknownDistanceCents: env.deliveryFeeCents },
      },
      apps: appConfigSummary(),
      backgroundJobs: jobs.map((j) => ({ name: j.name, lastRunAt: j.lastRunAt })),
    });
  } catch (e) { sendError(res, e); }
}
