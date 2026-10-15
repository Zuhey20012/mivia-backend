import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { escapeHtml } from "../../services/notificationDeliveryService";
import { formatCents } from "../../utils/pricing";
import { helsinkiInstant, helsinkiParts } from "../../utils/deliverySlots";
import { settle, settlementSelect } from "./settlement";

/** "2026-10" → the month's start and end instants in Finnish time. */
export function monthRange(month: string) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new ApiError("Use the month as YYYY-MM", 400);
  const [y, m] = month.split("-").map(Number);
  const next = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, "0")}`;
  return { from: helsinkiInstant(`${month}-01`, "00:00"), to: helsinkiInstant(`${next}-01`, "00:00") };
}

/** The current month in Finnish time, e.g. "2026-10". */
export const currentMonth = () => helsinkiParts(new Date()).date.slice(0, 7);

const MAX_ROWS = 5000;

/**
 * A store's monthly statement: every order delivered (or collected) in the month, with what it means for the
 * store under the payout rules (see settlement.ts), and the month's totals.
 */
export async function storeStatement(storeId: number, month: string) {
  const { from, to } = monthRange(month);
  const orders = await prisma.order.findMany({
    where: { storeId, deliveredAt: { gte: from, lt: to }, status: { in: ["DELIVERED", "REFUNDED"] } },
    select: settlementSelect,
    orderBy: { deliveredAt: "asc" },
    take: MAX_ROWS,
  });
  const rows = orders.map((o) => {
    const s = settle(o);
    return {
      id: o.id,
      deliveredAt: o.deliveredAt,
      itemsCents: s.itemsCents,
      refundsCents: s.refundsCents,
      commissionRate: s.commissionRate,
      commissionCents: s.commissionCents,
      payoutCents: s.payoutCents,
      payoutStatus: s.payoutStatus,
    };
  });
  const sum = (f: (r: (typeof rows)[number]) => number) => rows.reduce((t, r) => t + f(r), 0);
  const pending = new Set(["SCHEDULED", "WAITING_FOR_ACCOUNT", "FAILED", "NOT_CREATED"]);
  return {
    month,
    orders: rows,
    totals: {
      salesCents: sum((r) => r.itemsCents),
      refundsCents: sum((r) => r.refundsCents),
      commissionCents: sum((r) => r.commissionCents),
      payoutsSentCents: sum((r) => (r.payoutStatus === "PAID" ? r.payoutCents : 0)),
      payoutsPendingCents: sum((r) => (pending.has(r.payoutStatus) ? r.payoutCents : 0)),
    },
    truncated: orders.length === MAX_ROWS,
  };
}

export async function myStoreId(ownerId: number) {
  const store = await prisma.store.findUnique({ where: { ownerId }, select: { id: true } });
  if (!store) throw new ApiError("Create your store first", 409);
  return store.id;
}

const PAYOUT_TEXT: Record<string, string> = {
  PAID: "Paid", SCHEDULED: "Scheduled", WAITING_FOR_ACCOUNT: "Waiting for payout setup", FAILED: "Failed – Malvoya retries",
  CANCELLED: "None (refunded)", NOT_CREATED: "Pending",
};

/**
 * The statement as a printable page. Everything shown is escaped; the page has no scripts (strict CSP).
 * Malvoya has no company details yet, so its own name, business ID and address are placeholders.
 */
export async function statementHtml(storeId: number, month: string) {
  const store = await prisma.store.findUniqueOrThrow({
    where: { id: storeId },
    select: { name: true, sellerType: true, businessId: true, address: true, taxInfo: { select: { legalName: true } } },
  });
  const st = await storeStatement(storeId, month);
  const [y, m] = month.split("-").map(Number);
  const monthName = new Date(Date.UTC(y, m - 1, 1)).toLocaleString("en-GB", { month: "long", year: "numeric", timeZone: "UTC" });
  const date = (d: Date | null) => (d ? helsinkiParts(d).date.split("-").reverse().join(".") : "");
  const eur = (c: number) => escapeHtml(formatCents(c));
  const rows = st.orders.map((o) => `<tr><td>#${o.id}</td><td>${date(o.deliveredAt)}</td><td class="n">${eur(o.itemsCents)}</td><td class="n">${o.refundsCents ? `−${eur(o.refundsCents)}` : eur(0)}</td><td class="n">${escapeHtml((o.commissionRate * 100).toLocaleString("en-GB", { maximumFractionDigits: 2 }))} %</td><td class="n">−${eur(o.commissionCents)}</td><td class="n">${eur(o.payoutCents)}</td><td>${escapeHtml(PAYOUT_TEXT[o.payoutStatus] ?? o.payoutStatus)}</td></tr>`).join("");
  const t = st.totals;
  const seller = store.sellerType === "BUSINESS"
    ? `Business ID (Y-tunnus): ${escapeHtml(store.businessId ?? "not given")}`
    : "Private seller";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Statement ${escapeHtml(month)} – ${escapeHtml(store.name)}</title>
<style>
body{margin:0;background:#F6F3EE;color:#17131C;font:14px/1.5 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif}
main{max-width:860px;margin:24px auto;background:#fff;border-radius:18px;padding:32px}
h1{font-size:22px;margin:0 0 4px}.sub{color:#5b5360;margin:0 0 24px}
.cols{display:flex;gap:32px;flex-wrap:wrap;margin-bottom:24px}.cols div{flex:1;min-width:220px}
.label{color:#5b5360;font-size:12px;text-transform:uppercase;letter-spacing:.04em;margin:0 0 4px}
table{width:100%;border-collapse:collapse;font-size:13px}th,td{padding:8px 6px;border-bottom:1px solid #ece8e1;text-align:left;vertical-align:top}
th{color:#5b5360;font-weight:600;font-size:12px}.n{text-align:right;white-space:nowrap}
.totals{margin:24px 0 0 auto;max-width:360px}.totals td{border:none;padding:4px 6px}.totals tr.sum td{border-top:2px solid #17131C;font-weight:700}
.note{color:#5b5360;font-size:12px;margin-top:24px}
.badge{display:inline-block;background:#F2C14E;border-radius:999px;padding:2px 10px;font-size:12px;font-weight:600;margin-bottom:12px}
@media print{body{background:#fff}main{margin:0;border-radius:0;padding:0}}
</style></head><body><main>
<span class="badge">Statement — not a VAT invoice</span>
<h1>Statement — not a VAT invoice</h1>
<p class="sub">Sales through Malvoya, ${escapeHtml(monthName)} (orders delivered or collected in the month, Finnish time)</p>
<div class="cols">
<div><p class="label">Seller</p><strong>${escapeHtml(store.taxInfo?.legalName || store.name)}</strong><br>Store: ${escapeHtml(store.name)}<br>${seller}${store.address ? `<br>${escapeHtml(store.address)}` : ""}</div>
<div><p class="label">Marketplace</p><strong>Malvoya</strong><br>[COMPANY LEGAL NAME]<br>Business ID (Y-tunnus): [Y-TUNNUS]<br>[COMPANY ADDRESS]</div>
</div>
<table><thead><tr><th>Order</th><th>Delivered</th><th class="n">Sales</th><th class="n">Refunds</th><th class="n">Rate</th><th class="n">Commission</th><th class="n">Payout</th><th>Payout status</th></tr></thead>
<tbody>${rows || `<tr><td colspan="8">No orders were delivered in this month.</td></tr>`}</tbody></table>
<table class="totals"><tbody>
<tr><td>Sales</td><td class="n">${eur(t.salesCents)}</td></tr>
<tr><td>Refunds (returned goods)</td><td class="n">−${eur(t.refundsCents)}</td></tr>
<tr><td>Malvoya commission</td><td class="n">−${eur(t.commissionCents)}</td></tr>
<tr class="sum"><td>Payouts</td><td class="n">${eur(t.payoutsSentCents + t.payoutsPendingCents)}</td></tr>
<tr><td>· sent</td><td class="n">${eur(t.payoutsSentCents)}</td></tr>
<tr><td>· pending</td><td class="n">${eur(t.payoutsPendingCents)}</td></tr>
</tbody></table>
<p class="note">Amounts include VAT where the seller charges it. Sales are at full item prices: discounts from Malvoya promo and invite codes are paid by Malvoya and do not reduce them. Delivery, service and small-order fees and courier tips are not part of the seller's sales. Refunds take back the value of returned goods, and the commission on them is given back. Payouts are released through Stripe 15 days after delivery and are held while a return is open.${st.truncated ? " This statement shows the first 5000 orders only." : ""}<br>This statement is a summary for the seller's records. It is not a VAT invoice.</p>
</main></body></html>`;
}
