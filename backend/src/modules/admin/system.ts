import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { mediaConfigured } from "../../lib/cloudinary";
import { pushConfigured } from "../../lib/push";
import { sendError } from "../../lib/errors";
import { storeAvailability } from "../../utils/openingHours";
import { MIN_CHARGE_CENTS, deliveryFeeForDistance } from "../../utils/pricing";
import { approachPayFor, calcCourierPay, payRuleSummary, routeKm, waitPayFor } from "../../utils/courierPay";
import { appConfigSummary } from "../appConfig/appConfig.routes";

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
    ] = await Promise.all([
      prisma.store.findMany({ where: { isVerified: true }, select: { acceptingOrders: true, openingHours: true } }),
      prisma.store.count({ where: { isVerified: false } }),
      prisma.courier.count({ where: { isApproved: true, userId: { not: null } } }),
      prisma.courier.count({ where: { isApproved: true, isActive: true, updatedAt: { gte: fresh } } }),
      prisma.courier.count({ where: { isApproved: false, userId: { not: null } } }),
      prisma.launchAlert.count({ where: { notifiedAt: null } }),
      prisma.order.count({ where: { status: "PENDING", paymentStatus: "SUCCEEDED" } }),
      prisma.order.count({ where: { status: { in: ["CONFIRMED", "PROCESSING"] }, paymentStatus: "SUCCEEDED", courierId: null } }),
      // Cancelled but the money was not given back automatically (refund call failed)
      prisma.order.count({ where: { status: "CANCELLED", paymentStatus: "SUCCEEDED" } }),
      prisma.payout.count({ where: { status: "FAILED" } }),
      prisma.supportRequest.count({ where: { status: "OPEN" } }).catch(() => 0),
      prisma.dropReport.count({ where: { status: "OPEN" } }),
      prisma.jobLease.findMany({ select: { name: true, lastRunAt: true } }),
    ]);
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
    if (liveStores.length === 0) blockers.push("No approved stores yet.");
    if (approvedCouriers === 0) blockers.push("No approved couriers yet.");

    const attention: string[] = [];
    if (pendingStores) attention.push(`${pendingStores} store(s) waiting for approval`);
    if (pendingCouriers) attention.push(`${pendingCouriers} courier(s) waiting for approval`);
    if (refundProblems) attention.push(`${refundProblems} cancelled order(s) still need a refund — check Stripe`);
    if (failedPayouts) attention.push(`${failedPayouts} failed payout(s)`);
    if (openSupport) attention.push(`${openSupport} open support request(s)`);
    if (openReports) attention.push(`${openReports} open content report(s)`);

    res.json({
      ok: true,
      version: "2.7.0",
      region: "frankfurt",
      startedAt,
      readyForOrders: blockers.length === 0,
      blockers,
      attention,
      integrations,
      marketplace: {
        liveStores: liveStores.length, storesOpenNow, pendingStores,
        approvedCouriers, onlineCouriers, pendingCouriers,
        waitlist,
      },
      ordersInFlight: { waitingForStore, waitingForCourier },
      timers: t,
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
