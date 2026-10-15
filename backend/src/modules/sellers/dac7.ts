import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { decryptField } from "../../lib/fieldCrypto";
import { helsinkiInstant, helsinkiParts } from "../../utils/deliverySlots";
import { settle, settlementSelect } from "./settlement";
import { taxInfoMissing, taxRowSelect, tinAad } from "./taxInfo";

/**
 * DAC7 report (Council Directive (EU) 2021/514, Annex V) for one calendar year, per seller:
 *  - identity: legal name, business ID / VAT number (business) or date of birth / TIN (private), address, country;
 *  - number of relevant activities: orders delivered or collected in the year that were not fully refunded;
 *  - consideration per quarter: what the seller was paid or credited, net of Malvoya's commission (the
 *    directive's definition), i.e. sales − refunds − commission (settlement.ts);
 *  - fees and commissions withheld per quarter.
 * `exempt`: the directive's de-minimis for sellers of goods (fewer than 30 sales and at most 2 000 € of
 * consideration in the year). Such sellers are not reported, but their data is still kept.
 * Quarters and the year are in Finnish time, by the delivery date.
 */
const DE_MINIMIS_SALES = 30;
const DE_MINIMIS_CENTS = 200_000;

type Quarters = { q1: number; q2: number; q3: number; q4: number; total: number };
const zero = (): Quarters => ({ q1: 0, q2: 0, q3: 0, q4: 0, total: 0 });

export function parseYear(raw: unknown) {
  const year = raw === undefined || raw === "" ? new Date().getUTCFullYear() - 1 : Number(raw);
  if (!Number.isInteger(year) || year < 2023 || year > 2100) throw new ApiError("Use a year such as 2026", 400);
  return year;
}

export async function dac7Report(year: number) {
  const from = helsinkiInstant(`${year}-01-01`, "00:00");
  const to = helsinkiInstant(`${year + 1}-01-01`, "00:00");
  const perStore = new Map<number, { sales: number; consideration: Quarters; fees: Quarters; itemsCents: number }>();
  // The year's orders in pages of 2000, so memory stays bounded however big the year gets
  let cursor = 0;
  for (;;) {
    const page = await prisma.order.findMany({
      where: { id: { gt: cursor }, deliveredAt: { gte: from, lt: to }, status: { in: ["DELIVERED", "REFUNDED"] } },
      select: settlementSelect,
      orderBy: { id: "asc" },
      take: 2000,
    });
    if (!page.length) break;
    cursor = page[page.length - 1].id;
    for (const o of page) addOrder(o);
  }

  function addOrder(o: Parameters<typeof settle>[0]) {
    const s = settle(o);
    if (s.fullyRefunded) return;
    const q = (`q${Math.floor((Number(helsinkiParts(o.deliveredAt!).date.slice(5, 7)) - 1) / 3) + 1}`) as "q1" | "q2" | "q3" | "q4";
    const row = perStore.get(o.storeId) ?? { sales: 0, consideration: zero(), fees: zero(), itemsCents: 0 };
    const consideration = s.itemsCents - s.refundsCents - s.commissionCents;
    row.sales += 1;
    row.itemsCents += s.itemsCents - s.refundsCents;
    row.consideration[q] += consideration;
    row.consideration.total += consideration;
    row.fees[q] += s.commissionCents;
    row.fees.total += s.commissionCents;
    perStore.set(o.storeId, row);
  }

  // Sellers with sales in the year, plus every live store (to show whose data is still missing)
  const stores = await prisma.store.findMany({
    where: { OR: [{ id: { in: [...perStore.keys()] } }, { isVerified: true }] },
    select: { id: true, name: true, sellerType: true, businessId: true, isVerified: true, taxInfo: { select: { ...taxRowSelect, updatedAt: true } } },
    orderBy: { id: "asc" },
  });

  const sellers = [];
  const missingTaxData = [];
  for (const st of stores) {
    const missing = taxInfoMissing(st, st.taxInfo);
    const activity = perStore.get(st.id);
    if (missing.length) missingTaxData.push({ storeId: st.id, storeName: st.name, sellerType: st.sellerType, hasSales: !!activity, missing });
    if (!activity) continue;
    const info = st.taxInfo;
    const tin = info?.tinEncrypted ? decryptField(info.tinEncrypted, tinAad(st.id)) : null;
    sellers.push({
      storeId: st.id,
      storeName: st.name,
      sellerType: st.sellerType,
      identity: {
        legalName: info?.legalName ?? null,
        businessId: st.sellerType === "BUSINESS" ? st.businessId : null,
        vatNumber: info?.vatNumber ?? null,
        dateOfBirth: info?.dateOfBirth ? info.dateOfBirth.toISOString().slice(0, 10) : null,
        tin, // decrypted here only (admin)
        tinUnreadable: !!info?.tinEncrypted && tin === null, // saved, but the key cannot read it
        address: info ? { line: info.addressLine, postalCode: info.postalCode, city: info.city, country: info.country } : null,
        updatedAt: info?.updatedAt ?? null,
      },
      taxInfoComplete: missing.length === 0,
      missing,
      sales: activity.sales,
      salesValueCents: activity.itemsCents, // items kept by customers, before commission (for information)
      considerationCents: activity.consideration,
      feesCents: activity.fees,
      exempt: activity.sales < DE_MINIMIS_SALES && activity.consideration.total <= DE_MINIMIS_CENTS,
    });
  }

  return {
    year,
    period: { from, to },
    deMinimis: { salesBelow: DE_MINIMIS_SALES, considerationAtMostCents: DE_MINIMIS_CENTS },
    dueBy: `${year + 1}-01-31`,
    sellers,
    reportable: sellers.filter((s) => !s.exempt).length,
    missingTaxData,
  };
}

/** Spreadsheet programs run cells starting with = + - @ (or tab/CR) as formulas: prefix them with ' . */
export function csvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "number") return String(value);
  let s = String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\r\n;]/.test(s) || s !== s.trim() ? `"${s.replace(/"/g, '""')}"` : s;
}

export async function dac7Csv(year: number) {
  const r = await dac7Report(year);
  const header = [
    "year", "store_id", "store_name", "seller_type", "legal_name", "business_id", "vat_number", "date_of_birth", "tin",
    "address_line", "postal_code", "city", "country", "sales",
    "consideration_q1_cents", "consideration_q2_cents", "consideration_q3_cents", "consideration_q4_cents", "consideration_total_cents",
    "fees_q1_cents", "fees_q2_cents", "fees_q3_cents", "fees_q4_cents", "fees_total_cents",
    "exempt", "tax_info_complete", "missing",
  ];
  const lines = r.sellers.map((s) => [
    year, s.storeId, s.storeName, s.sellerType, s.identity.legalName, s.identity.businessId, s.identity.vatNumber, s.identity.dateOfBirth,
    s.identity.tin, s.identity.address?.line, s.identity.address?.postalCode, s.identity.address?.city, s.identity.address?.country, s.sales,
    s.considerationCents.q1, s.considerationCents.q2, s.considerationCents.q3, s.considerationCents.q4, s.considerationCents.total,
    s.feesCents.q1, s.feesCents.q2, s.feesCents.q3, s.feesCents.q4, s.feesCents.total,
    s.exempt ? "yes" : "no", s.taxInfoComplete ? "yes" : "no", s.missing.join(" "),
  ].map(csvCell).join(","));
  return [header.join(","), ...lines].join("\r\n") + "\r\n";
}
