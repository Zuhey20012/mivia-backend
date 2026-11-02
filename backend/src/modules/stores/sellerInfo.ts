import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { t } from "../../lib/i18n";

/**
 * Who the shopper buys from (since 2.17.0): the pre-contract information shown at checkout and on product and store
 * pages (Kuluttajansuojalaki 6:9, CRD Art. 6, DSA Art. 30, Omnibus Art. 6a).
 *  - business sellers: legal name (from the DAC7 details when given), Y-tunnus, address, phone and email;
 *  - private sellers: their city only (a person's home address and contact details are not published), and no
 *    statutory right of withdrawal.
 */
type SellerStore = {
  id: number; sellerType: "BUSINESS" | "PRIVATE"; businessId?: string | null; address?: string | null;
  phone?: string | null; email?: string | null;
};

/** "Mannerheimintie 1, 00100 Helsinki" → "Helsinki" (the last comma part without the postal code). */
export function cityOf(address: string | null | undefined): string | null {
  if (!address?.trim()) return null;
  const last = address.split(",").map((p) => p.trim()).filter(Boolean).pop() ?? "";
  const city = last.replace(/\b\d{5}\b/g, "").replace(/\bFinland\b|\bSuomi\b/gi, "").trim();
  return city || null;
}

export const RETURN_COST = {
  business: t("Returns: take the items back to the store, or agree another way with the store. The store tells you before you send anything whether you pay the return cost.",
    "Palautus: vie tuotteet takaisin kauppaan tai sovi muusta tavasta kaupan kanssa. Kauppa kertoo ennen lähettämistä, maksatko palautuskulut."),
  private: t("Private seller: no statutory right of withdrawal. Faulty or wrong items can still be reported in the app.",
    "Yksityinen myyjä: lakisääteistä peruuttamisoikeutta ei ole. Virheellisistä tai vääristä tuotteista voi silti ilmoittaa sovelluksessa."),
};

export async function sellerInfo(store: SellerStore) {
  const tax = await prisma.storeTaxInfo.findUnique({ where: { storeId: store.id }, select: { legalName: true, city: true } }).catch(() => null);
  return presentSeller(store, tax);
}

export function presentSeller(store: SellerStore, tax: { legalName: string; city: string } | null) {
  const business = store.sellerType === "BUSINESS";
  return {
    sellerType: store.sellerType,
    legalName: business ? tax?.legalName ?? null : null,
    businessId: business ? store.businessId ?? null : null,
    address: business ? store.address ?? null : null,
    phone: business ? store.phone ?? null : null,
    email: business ? store.email ?? null : null,
    city: business ? cityOf(store.address) : tax?.city ?? cityOf(store.address),
    freeDeliveryThresholdCents: env.freeDeliveryThresholdCents,
    withdrawal: business ? { days: env.returnWindowDays, formUrl: `${env.publicApiUrl}/legal/withdrawal-form` } : null,
    returnCost: business ? RETURN_COST.business : RETURN_COST.private,
  };
}
