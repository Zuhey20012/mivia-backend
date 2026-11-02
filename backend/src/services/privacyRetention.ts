import pino from "pino";
import { prisma } from "../lib/prisma";
import { courierPositionTtlMinutes } from "../config/env";
import { mediaConfigured } from "../lib/cloudinary";
import { emitToCourier } from "../lib/socket";
import { purgeOldDeliveryProofs } from "../modules/orders/orders.service";

/**
 * Retention jobs added by the data audit (2.16.1, docs/compliance/data-transparency-report.md C1, C3, C4, C5, C9).
 * Each one is idempotent and safe on several instances (the scheduler holds a lease). The periods are the ones
 * legal/privacy_policy.md §7 and legal/data_explained.md promise; change them together.
 */

const logger = pino({ name: "privacy-retention" });
const DAY_MS = 86_400_000;

/** Handover position and the delivery pin: 30 days after the order was delivered or closed. */
export const DELIVERY_LOCATION_RETENTION_DAYS = 30;
/** Per-viewer drop view rows: today and yesterday are kept (they de-duplicate views within a day). */
export const DROP_VIEW_RETENTION_DAYS = 2;
/** Contact-form and other no-account support messages: 24 months after the last change. */
export const CONTACT_MESSAGE_RETENTION_MONTHS = 24;

/**
 * C1: nulls the courier's handover position (deliveredLat/Lng) and the customer's delivery pin (deliveryLat/Lng) on
 * every order delivered, cancelled or refunded more than 30 days ago, whatever the handover method (in person,
 * photo, admin). The written delivery address stays with the order record (Accounting Act); the pin and the
 * handover position are not needed for it.
 */
export async function purgeOldDeliveryLocations(now = new Date()) {
  const cutoff = new Date(now.getTime() - DELIVERY_LOCATION_RETENTION_DAYS * DAY_MS);
  const closed = ["CANCELLED", "REFUNDED"] as const;
  const res = await prisma.order.updateMany({
    where: {
      AND: [
        { OR: [{ deliveredLat: { not: null } }, { deliveredLng: { not: null } }, { deliveryLat: { not: null } }, { deliveryLng: { not: null } }] },
        {
          OR: [
            { deliveredAt: { lt: cutoff } },
            { deliveredAt: null, status: { in: [...closed] }, cancelledAt: { lt: cutoff } },
            // Closed without a cancellation time (old rows): the last change counts
            { deliveredAt: null, status: { in: [...closed] }, cancelledAt: null, updatedAt: { lt: cutoff } },
          ],
        },
      ],
    },
    data: { deliveredLat: null, deliveredLng: null, deliveryLat: null, deliveryLng: null },
  });
  return res.count;
}

/**
 * Scheduler job "delivery-proof-purge": always runs (the positions live in our database); the delivery photos at
 * Cloudinary are deleted only when Cloudinary is configured (otherwise there is nothing we can delete them with).
 */
export async function purgeDeliveryProofsAndLocations(opts: { media?: boolean; now?: Date } = {}) {
  const locations = await purgeOldDeliveryLocations(opts.now);
  const photos = (opts.media ?? mediaConfigured()) ? await purgeOldDeliveryProofs() : 0;
  return { locations, photos };
}

/**
 * C3: a courier's stored position is cleared when no update has arrived for COURIER_POSITION_TTL_MINUTES
 * (default 15), e.g. because the app was killed without going offline.
 *  - Carrying an order (or rental/return job): only the position is cleared. The job, its status and chat carry on
 *    unchanged; `locationExpiredAt` is set so the admin panel shows "no position"; the next update restores it.
 *  - Idle (online, no job): the position is cleared and the courier is marked offline (no more offers until they
 *    go online again), told over the socket if the app is still connected.
 *  - Offline couriers never keep a position (going offline clears it; this also catches older paths that did not).
 * A courier who is online without ever sending a position counts from their last profile change.
 */
export async function expireStaleCourierPositions(now = new Date()) {
  const cutoff = new Date(now.getTime() - courierPositionTtlMinutes() * 60_000);
  const stale = [{ locationAt: { lt: cutoff } }, { locationAt: null }];
  const busy = [{ currentOrderId: { not: null } }, { currentRentalId: { not: null } }, { currentReturnId: { not: null } }];
  const idle = { currentOrderId: null, currentRentalId: null, currentReturnId: null };

  const carrying = await prisma.courier.updateMany({
    where: { latitude: { not: null }, OR: stale, AND: [{ OR: busy }] },
    data: { latitude: null, longitude: null, locationAt: null, locationExpiredAt: now },
  });

  const idleStale = { isActive: true, ...idle, OR: [{ locationAt: { lt: cutoff } }, { locationAt: null, updatedAt: { lt: cutoff } }] };
  const candidates = await prisma.courier.findMany({ where: idleStale, select: { id: true, latitude: true }, take: 500 });
  let offline = 0;
  for (const c of candidates) {
    const r = await prisma.courier.updateMany({
      where: { id: c.id, ...idleStale },
      data: { isActive: false, latitude: null, longitude: null, locationAt: null, ...(c.latitude !== null ? { locationExpiredAt: now } : {}) },
    });
    if (r.count) {
      offline++;
      emitToCourier(c.id, "courier:status", { isOnline: false, reason: "no_position", ttlMinutes: courierPositionTtlMinutes() });
    }
  }

  const leftovers = await prisma.courier.updateMany({
    where: { isActive: false, ...idle, OR: [{ latitude: { not: null } }, { longitude: { not: null } }, { locationAt: { not: null } }] },
    data: { latitude: null, longitude: null, locationAt: null },
  });

  if (carrying.count || offline) logger.info({ carrying: carrying.count, offline }, "Stale courier positions cleared");
  return { carrying: carrying.count, offline, offlineCleared: leftovers.count };
}

/**
 * C4: drop view rows exist only to count one view per viewer per day (the totals are on Drop.viewCount /
 * completeCount), so rows older than yesterday (UTC) are deleted.
 */
export async function purgeOldDropViews(now = new Date()) {
  const today = new Date(now.toISOString().slice(0, 10));
  const cutoff = new Date(today.getTime() - (DROP_VIEW_RETENTION_DAYS - 1) * DAY_MS);
  const res = await prisma.dropView.deleteMany({ where: { day: { lt: cutoff } } });
  return res.count;
}

/**
 * C5: support requests sent without an account (the /contact form, or an app before signing in) are deleted 24 months
 * after their last change. Requests from an account are deleted with the account.
 */
export async function purgeOldContactMessages(now = new Date()) {
  const cutoff = new Date(now);
  cutoff.setUTCMonth(cutoff.getUTCMonth() - CONTACT_MESSAGE_RETENTION_MONTHS);
  const res = await prisma.supportRequest.deleteMany({ where: { userId: null, updatedAt: { lt: cutoff } } });
  return res.count;
}

/** C9: expired sign-in and reset codes, and expired refresh tokens of every user (also those who never come back). */
export async function purgeExpiredCredentials(now = new Date()) {
  const [codes, tokens, counters, sessions] = await Promise.all([
    prisma.otpCode.deleteMany({ where: { expiresAt: { lt: now } } }),
    prisma.refreshToken.deleteMany({ where: { expiresAt: { lt: now } } }),
    // Shared counters (sign-in failures, SMS per day, code guesses, failed payments; 2.17) whose window has ended
    prisma.counter.deleteMany({ where: { expiresAt: { lt: now } } }),
    // Signed-in devices (2.17): ended a day ago, or unused for longer than a refresh token lives
    prisma.userSession.deleteMany({
      where: { OR: [{ revokedAt: { lt: new Date(now.getTime() - 86_400_000) } }, { lastUsedAt: { lt: new Date(now.getTime() - 8 * 86_400_000) } }] },
    }),
  ]);
  return { codes: codes.count, refreshTokens: tokens.count, counters: counters.count, sessions: sessions.count };
}
