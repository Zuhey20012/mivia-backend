import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { mediaConfigured } from "../../lib/cloudinary";
import { pushConfigured } from "../../lib/push";
import { sendError } from "../../lib/errors";
import { storeAvailability } from "../../utils/openingHours";

const startedAt = new Date();

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
      version: "2.4.0",
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
      backgroundJobs: jobs.map((j) => ({ name: j.name, lastRunAt: j.lastRunAt })),
    });
  } catch (e) { sendError(res, e); }
}
