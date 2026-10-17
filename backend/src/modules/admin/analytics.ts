import { Request, Response } from "express";
import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError, sendError } from "../../lib/errors";
import { addDays, helsinkiInstant, helsinkiParts, isValidDate } from "../../utils/deliverySlots";
import { platformRevenue, RevenueSums } from "./revenue";

/**
 * Owner analytics (admin only): daily series and totals over a range of Finnish days (default the last 28).
 * Everything is computed from orders, returns, users and the waiting list; nothing is sampled or estimated.
 * Courier hours online are not tracked, so they are not reported.
 */

/** How cancellations are labelled (Order.cancelReason as written by the API) → a stable key. */
const CANCEL_REASONS: Record<string, string> = {
  "The store did not respond in time": "store_timeout",
  "Declined by store": "store_declined",
  "No courier was available": "no_courier",
  "Cancelled by customer": "customer",
  "Not collected in time": "pickup_not_collected",
  "The store did not get the order ready in time": "store_not_ready",
  "Cancelled by Malvoya": "admin",
  "Customer could not be reached": "customer_unreachable",
};
// Since 2.10 a store can cancel in its own words (Order.cancelledBy = "STORE"): those are "store_cancelled"
export const CANCEL_REASON_KEYS = [...new Set(Object.values(CANCEL_REASONS)), "store_cancelled", "other"];

const MAX_DAYS = 366;

export function analyticsRange(fromRaw: unknown, toRaw: unknown) {
  const today = helsinkiParts(new Date()).date;
  const to = typeof toRaw === "string" && toRaw ? toRaw : today;
  const from = typeof fromRaw === "string" && fromRaw ? fromRaw : addDays(to, -27);
  if (!isValidDate(from) || !isValidDate(to)) throw new ApiError("Use dates as YYYY-MM-DD", 400);
  if (from > to) throw new ApiError("The start date must be before the end date", 400);
  const days: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    days.push(d);
    if (days.length > MAX_DAYS) throw new ApiError(`Pick at most ${MAX_DAYS} days`, 400);
  }
  return { from, to, days, start: helsinkiInstant(from, "00:00").toISOString(), end: helsinkiInstant(addDays(to, 1), "00:00").toISOString() };
}

// Timestamps are stored as UTC without a zone: this is the Finnish calendar day of a column
const day = (col: string) => Prisma.raw(`((${col} AT TIME ZONE 'UTC') AT TIME ZONE 'Europe/Helsinki')::date::text`);
const n = (v: unknown) => Number(v ?? 0);
const rate = (part: number, whole: number) => (whole > 0 ? Math.round((part / whole) * 10_000) / 10_000 : null);

export async function analytics(fromRaw: unknown, toRaw: unknown) {
  const r = analyticsRange(fromRaw, toRaw);
  // Range bounds as UTC timestamps, comparable with the stored columns
  const start = Prisma.sql`(${r.start}::timestamptz AT TIME ZONE 'UTC')`;
  const end = Prisma.sql`(${r.end}::timestamptz AT TIME ZONE 'UTC')`;

  const [paid, delivered, cancelled, revenue, acceptance, onTime, returns, refunds, firsts, repeat, signups, waitlist] = await Promise.all([
    prisma.$queryRaw<{ day: string; orders: number; gmv: bigint }[]>`
      SELECT ${day('"paidAt"')} AS day, count(*)::int AS orders, coalesce(sum("subtotalCents"), 0)::bigint AS gmv
      FROM "Order" WHERE "paidAt" >= ${start} AND "paidAt" < ${end} GROUP BY 1`,
    prisma.$queryRaw<{ day: string; orders: number }[]>`
      SELECT ${day('"deliveredAt"')} AS day, count(*)::int AS orders
      FROM "Order" WHERE "deliveredAt" >= ${start} AND "deliveredAt" < ${end} AND status IN ('DELIVERED', 'REFUNDED') GROUP BY 1`,
    // Cancellations of paid orders (unpaid checkouts that lapse are not cancellations anyone experienced)
    prisma.$queryRaw<{ day: string; reason: string | null; orders: number }[]>`
      SELECT ${day('"cancelledAt"')} AS day,
        CASE WHEN "cancelledBy" = 'STORE' AND "cancelReason" IS DISTINCT FROM 'Declined by store' THEN '#store_cancelled' ELSE "cancelReason" END AS reason,
        count(*)::int AS orders
      FROM "Order" WHERE "cancelledAt" >= ${start} AND "cancelledAt" < ${end} AND status = 'CANCELLED' AND "paidAt" IS NOT NULL
      GROUP BY 1, 2`,
    // Malvoya's revenue, same rule as /admin/stats: paid, not refunded or cancelled; by payment day
    prisma.$queryRaw<(RevenueSums & { day: string })[]>`
      SELECT ${day('"paidAt"')} AS day,
        sum("commissionCents")::bigint AS "commissionCents", sum("serviceFeeCents")::bigint AS "serviceFeeCents",
        sum("smallOrderFeeCents")::bigint AS "smallOrderFeeCents", sum("discountCents")::bigint AS "discountCents",
        sum("deliveryFeeCents")::bigint AS "deliveryFeeCents", sum("courierFeeCents")::bigint AS "courierFeeCents",
        sum("tipCents")::bigint AS "tipCents"
      FROM "Order" WHERE "paidAt" >= ${start} AND "paidAt" < ${end} AND "paymentStatus" = 'SUCCEEDED' AND status <> 'CANCELLED'
      GROUP BY 1`,
    // Store answers to orders paid in the range
    prisma.$queryRaw<{ accepted: number; declined: number; timed_out: number; median_s: number | null }[]>`
      SELECT count(*) FILTER (WHERE "confirmedAt" IS NOT NULL)::int AS accepted,
        count(*) FILTER (WHERE "confirmedAt" IS NULL AND ("cancelReason" = 'Declined by store' OR "cancelledBy" = 'STORE'))::int AS declined,
        count(*) FILTER (WHERE "confirmedAt" IS NULL AND "cancelReason" = 'The store did not respond in time')::int AS timed_out,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM "confirmedAt" - "paidAt"))
          FILTER (WHERE "confirmedAt" IS NOT NULL AND "confirmedAt" >= "paidAt") AS median_s
      FROM "Order" WHERE "paidAt" >= ${start} AND "paidAt" < ${end}`,
    // Courier deliveries in the range: on time = by the end of the promised window (etaMinutes + 10 from payment,
    // or the scheduled slot's end). Orders without a promise (unknown distance) are not measured.
    prisma.$queryRaw<{ measured: number; on_time: number; median_min: number | null }[]>`
      SELECT count(*) FILTER (WHERE "scheduledEnd" IS NOT NULL OR "etaMinutes" IS NOT NULL)::int AS measured,
        count(*) FILTER (WHERE ("scheduledEnd" IS NOT NULL AND "deliveredAt" <= "scheduledEnd")
          OR ("scheduledEnd" IS NULL AND "etaMinutes" IS NOT NULL AND "deliveredAt" <= "paidAt" + ("etaMinutes" + 10) * interval '1 minute'))::int AS on_time,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM "deliveredAt" - "paidAt") / 60)
          FILTER (WHERE "scheduledStart" IS NULL) AS median_min
      FROM "Order" WHERE "deliveredAt" >= ${start} AND "deliveredAt" < ${end} AND fulfilment = 'DELIVERY'
        AND status IN ('DELIVERED', 'REFUNDED') AND "paidAt" IS NOT NULL`,
    // Returns of orders delivered in the range (any return that was not rejected)
    prisma.$queryRaw<{ orders: number; items: number; orders_returned: number; items_returned: number }[]>`
      WITH d AS (SELECT id FROM "Order" WHERE "deliveredAt" >= ${start} AND "deliveredAt" < ${end} AND status IN ('DELIVERED', 'REFUNDED')),
      r AS (SELECT id, "orderId" FROM "Return" WHERE "orderId" IN (SELECT id FROM d) AND status <> 'REJECTED')
      SELECT (SELECT count(*) FROM d)::int AS orders,
        (SELECT coalesce(sum(quantity), 0) FROM "OrderItem" WHERE "orderId" IN (SELECT id FROM d))::int AS items,
        (SELECT count(DISTINCT "orderId") FROM r)::int AS orders_returned,
        ((SELECT coalesce(sum(quantity), 0) FROM "ReturnItem" WHERE "returnId" IN (SELECT id FROM r))
          + (SELECT coalesce(sum(oi.quantity), 0) FROM r JOIN "OrderItem" oi ON oi."orderId" = r."orderId"
             WHERE NOT EXISTS (SELECT 1 FROM "ReturnItem" x WHERE x."returnId" = r.id)))::int AS items_returned`,
    // Money given back on orders paid in the range (cancellations and returns)
    prisma.$queryRaw<{ cents: bigint; orders: number; cancelled_cents: bigint }[]>`
      SELECT coalesce(sum("refundedCents"), 0)::bigint AS cents, count(*) FILTER (WHERE "refundedCents" > 0)::int AS orders,
        coalesce(sum("refundedCents") FILTER (WHERE status = 'CANCELLED'), 0)::bigint AS cancelled_cents
      FROM "Order" WHERE "paidAt" >= ${start} AND "paidAt" < ${end}`,
    // New customers: their first paid order (not cancelled) falls in the range
    prisma.$queryRaw<{ day: string; customers: number }[]>`
      SELECT ${day("f.first")} AS day, count(*)::int AS customers FROM (
        SELECT "userId", min("paidAt") AS first FROM "Order" WHERE "paidAt" IS NOT NULL AND status <> 'CANCELLED' GROUP BY "userId"
      ) f WHERE f.first >= ${start} AND f.first < ${end} GROUP BY 1`,
    // Of those, how many paid for another order within 30 days of their first
    prisma.$queryRaw<{ cohort: number; repeaters: number }[]>`
      WITH f AS (
        SELECT "userId", min("paidAt") AS first FROM "Order" WHERE "paidAt" IS NOT NULL AND status <> 'CANCELLED' GROUP BY "userId"
      )
      SELECT count(*)::int AS cohort,
        count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM "Order" o WHERE o."userId" = f."userId" AND o."paidAt" IS NOT NULL AND o.status <> 'CANCELLED'
            AND o."paidAt" > f.first AND o."paidAt" <= f.first + interval '30 days'))::int AS repeaters
      FROM f WHERE f.first >= ${start} AND f.first < ${end}`,
    prisma.user.count({ where: { role: "CUSTOMER", createdAt: { gte: new Date(r.start), lt: new Date(r.end) } } }),
    prisma.launchAlert.count({ where: { notifiedAt: null } }),
  ]);

  const byDay = <T extends { day: string }>(rows: T[]) => new Map(rows.map((x) => [x.day, x]));
  const paidBy = byDay(paid);
  const deliveredBy = byDay(delivered);
  const revenueBy = byDay(revenue);
  const firstsBy = byDay(firsts);
  const cancelledBy = new Map<string, number>();
  const reasons: Record<string, number> = Object.fromEntries(CANCEL_REASON_KEYS.map((k) => [k, 0]));
  for (const c of cancelled) {
    cancelledBy.set(c.day, (cancelledBy.get(c.day) ?? 0) + c.orders);
    reasons[c.reason === "#store_cancelled" ? "store_cancelled" : CANCEL_REASONS[c.reason ?? ""] ?? "other"] += c.orders;
  }

  const daily = r.days.map((d) => ({
    date: d,
    ordersPaid: n(paidBy.get(d)?.orders),
    gmvCents: n(paidBy.get(d)?.gmv),
    delivered: n(deliveredBy.get(d)?.orders),
    cancelled: cancelledBy.get(d) ?? 0,
    netRevenueCents: revenueBy.has(d) ? platformRevenue(revenueBy.get(d)!).netPlatformRevenueCents : 0,
    newCustomers: n(firstsBy.get(d)?.customers),
  }));

  const sumRevenue = revenue.reduce<RevenueSums>((t, x) => ({
    commissionCents: n(t.commissionCents) + n(x.commissionCents), serviceFeeCents: n(t.serviceFeeCents) + n(x.serviceFeeCents),
    smallOrderFeeCents: n(t.smallOrderFeeCents) + n(x.smallOrderFeeCents), discountCents: n(t.discountCents) + n(x.discountCents),
    deliveryFeeCents: n(t.deliveryFeeCents) + n(x.deliveryFeeCents), courierFeeCents: n(t.courierFeeCents) + n(x.courierFeeCents),
    tipCents: n(t.tipCents) + n(x.tipCents),
  }), { commissionCents: 0, serviceFeeCents: 0, smallOrderFeeCents: 0, discountCents: 0, deliveryFeeCents: 0, courierFeeCents: 0, tipCents: 0 });

  const a = acceptance[0];
  const answered = n(a?.accepted) + n(a?.declined) + n(a?.timed_out);
  const ot = onTime[0];
  const ret = returns[0];
  const rep = repeat[0];
  const sum = (k: keyof (typeof daily)[number]) => daily.reduce((t, x) => t + (x[k] as number), 0);

  return {
    range: { from: r.from, to: r.to, days: r.days.length, timeZone: "Europe/Helsinki" },
    totals: {
      ordersPaid: sum("ordersPaid"),
      gmvCents: sum("gmvCents"),
      delivered: sum("delivered"),
      cancelled: sum("cancelled"),
      cancelledByReason: reasons,
      storeAcceptance: {
        rate: rate(n(a?.accepted), answered),
        accepted: n(a?.accepted), declined: n(a?.declined), timedOut: n(a?.timed_out),
        medianSecondsToAccept: a?.median_s === null || a?.median_s === undefined ? null : Math.round(n(a.median_s)),
      },
      onTimeDelivery: { rate: rate(n(ot?.on_time), n(ot?.measured)), onTime: n(ot?.on_time), measured: n(ot?.measured) },
      medianDeliveryMinutes: ot?.median_min === null || ot?.median_min === undefined ? null : Math.round(n(ot.median_min)),
      returns: {
        orderRate: rate(n(ret?.orders_returned), n(ret?.orders)),
        itemRate: rate(n(ret?.items_returned), n(ret?.items)),
        ordersWithReturn: n(ret?.orders_returned), deliveredOrders: n(ret?.orders),
        returnedItems: n(ret?.items_returned), deliveredItems: n(ret?.items),
      },
      refunds: {
        refundedCents: n(refunds[0]?.cents), refundedOrders: n(refunds[0]?.orders),
        cancellationsCents: n(refunds[0]?.cancelled_cents), returnsCents: n(refunds[0]?.cents) - n(refunds[0]?.cancelled_cents),
      },
      revenue: platformRevenue(sumRevenue),
      customers: {
        newCustomers: sum("newCustomers"),
        signups,
        repeatWithin30Days: { cohort: n(rep?.cohort), repeaters: n(rep?.repeaters), rate: rate(n(rep?.repeaters), n(rep?.cohort)) },
      },
      waitlist,
    },
    daily,
  };
}

export async function getAnalytics(req: Request, res: Response) {
  try {
    res.json({ ok: true, ...(await analytics(req.query.from, req.query.to)) });
  } catch (e) { sendError(res, e); }
}
