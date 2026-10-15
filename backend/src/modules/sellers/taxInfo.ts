import { z } from "zod";
import { Prisma, SellerType } from "@prisma/client";
import { prisma } from "../../lib/prisma";
import { ApiError } from "../../lib/errors";
import { decryptField, encryptField, encryptionConfigured } from "../../lib/fieldCrypto";
import { isValidDate } from "../../utils/deliverySlots";

/**
 * DAC7 seller data (Council Directive (EU) 2021/514): what a platform must collect from each seller and report
 * to the Finnish Tax Administration once a year, by 31 January. Only what DAC7 requires is collected:
 *  - business sellers: legal name, business ID (Store.businessId, the Y-tunnus), VAT number if they have one,
 *    registered address and country;
 *  - private sellers: legal name, date of birth, tax identification number (TIN; for Finns the henkilötunnus)
 *    and primary address with country.
 * The TIN is encrypted at rest (lib/fieldCrypto.ts) and shown to its owner masked; only the admin DAC7 report
 * decrypts it. The data is kept 10 years after the reporting year, also when the account is deleted.
 */

/** The row ties the ciphertext to its store, so a TIN copied to another row does not decrypt. */
export const tinAad = (storeId: number) => `store:${storeId}:tin`;

const HETU_RE = /^(\d{2})(\d{2})(\d{2})([-+ABCDEFUVWXY])(\d{3})([0-9A-Y])$/;
const HETU_CHECK = "0123456789ABCDEFHJKLMNPRSTUVWXY";
const CENTURY: Record<string, number> = { "+": 1800, "-": 1900, U: 1900, V: 1900, W: 1900, X: 1900, Y: 1900, A: 2000, B: 2000, C: 2000, D: 2000, E: 2000, F: 2000 };

/** A valid Finnish henkilötunnus (incl. the 2023 century signs and the check character): its date of birth, else null. */
export function hetuBirthDate(hetu: string): string | null {
  const m = HETU_RE.exec(hetu);
  if (!m) return null;
  const [, dd, mm, yy, sign, num, check] = m;
  const n = Number(num);
  if (n < 2 || n > 899) return null; // 900–999 are temporary numbers, not tax IDs
  if (HETU_CHECK[Number(`${dd}${mm}${yy}${num}`) % 31] !== check) return null;
  const date = `${CENTURY[sign] + Number(yy)}-${mm}-${dd}`;
  return isValidDate(date) ? date : null;
}

/** What the owner sees of their TIN: the last characters only, e.g. "•••••-308T". */
export function maskTin(tin: string) {
  return HETU_RE.test(tin) ? `•••••${tin.slice(-5)}` : `•••••${tin.slice(-4)}`;
}

const today = () => new Date().toISOString().slice(0, 10);
function ageOn(dateOfBirth: string, on = today()) {
  const [y, m, d] = dateOfBirth.split("-").map(Number);
  const [ty, tm, td] = on.split("-").map(Number);
  return ty - y - (tm < m || (tm === m && td < d) ? 1 : 0);
}

const text = (min: number, max: number) => z.string().trim().min(min).max(max);

export const taxInfoSchema = z.object({
  legalName:   text(2, 200),
  addressLine: text(3, 200),
  postalCode:  text(2, 12),
  city:        text(1, 100),
  country:     z.string().trim().toUpperCase().regex(/^[A-Z]{2}$/, "Use a two-letter country code, e.g. FI").default("FI"),
  // Private sellers
  dateOfBirth: z.string().trim().optional(),
  tin:         z.string().trim().toUpperCase().max(30).optional(),
  // Business sellers (optional)
  vatNumber:   z.string().trim().toUpperCase().max(20).nullable().optional(),
}).strict();
export type TaxInfoInput = z.infer<typeof taxInfoSchema>;

type TaxRow = {
  legalName: string; dateOfBirth: Date | null; tinEncrypted: string | null; vatNumber: string | null;
  addressLine: string; postalCode: string; city: string; country: string;
};
type TaxStore = { sellerType: SellerType; businessId: string | null };

/** Which DAC7 fields are still missing for this store (empty = complete). */
export function taxInfoMissing(store: TaxStore, info: TaxRow | null | undefined): string[] {
  const missing: string[] = [];
  if (!info?.legalName) missing.push("legalName");
  if (store.sellerType === "BUSINESS") {
    if (!store.businessId) missing.push("businessId");
  } else {
    if (!info?.dateOfBirth) missing.push("dateOfBirth");
    if (!info?.tinEncrypted) missing.push("tin");
  }
  if (!info?.addressLine || !info.postalCode || !info.city) missing.push("address");
  if (!info?.country) missing.push("country");
  return missing;
}

export const taxInfoComplete = (store: TaxStore, info: TaxRow | null | undefined) => taxInfoMissing(store, info).length === 0;

/** Every column but the ciphertext's content: used where only "is a TIN saved?" matters. */
export const taxRowSelect = {
  legalName: true, dateOfBirth: true, tinEncrypted: true, vatNumber: true, addressLine: true, postalCode: true, city: true, country: true,
} satisfies Prisma.StoreTaxInfoSelect;

async function ownStore(ownerId: number) {
  const store = await prisma.store.findUnique({
    where: { ownerId },
    select: { id: true, sellerType: true, businessId: true, taxInfo: true },
  });
  if (!store) throw new ApiError("Create your store first", 409);
  return store;
}

function present(store: { id: number; sellerType: SellerType; businessId: string | null }, info: (TaxRow & { updatedAt: Date }) | null) {
  const missing = taxInfoMissing(store, info);
  let tinMasked: string | null = null;
  if (info?.tinEncrypted) {
    const tin = decryptField(info.tinEncrypted, tinAad(store.id));
    tinMasked = tin ? maskTin(tin) : "•••••"; // saved, but the server cannot read it right now
  }
  return {
    taxInfo: info
      ? {
          sellerType: store.sellerType,
          legalName: info.legalName,
          businessId: store.businessId,
          vatNumber: info.vatNumber,
          dateOfBirth: info.dateOfBirth ? info.dateOfBirth.toISOString().slice(0, 10) : null,
          tinMasked,
          addressLine: info.addressLine,
          postalCode: info.postalCode,
          city: info.city,
          country: info.country,
          updatedAt: info.updatedAt,
        }
      : null,
    sellerType: store.sellerType,
    taxInfoComplete: missing.length === 0,
    missing,
    // Without DATA_ENCRYPTION_KEY a tax ID cannot be saved (the app can say so before the seller types it)
    canSaveTin: encryptionConfigured(),
  };
}

export async function getMyTaxInfo(ownerId: number) {
  const store = await ownStore(ownerId);
  return present(store, store.taxInfo);
}

export async function putMyTaxInfo(ownerId: number, input: TaxInfoInput) {
  const store = await ownStore(ownerId);
  const fi = input.country === "FI";
  if (fi && !/^\d{5}$/.test(input.postalCode)) throw new ApiError("A Finnish postal code has 5 digits", 400);

  let dateOfBirth: Date | null = null;
  let tinEncrypted: string | null = null;
  let vatNumber: string | null = null;

  if (store.sellerType === "PRIVATE") {
    const dob = input.dateOfBirth ?? "";
    if (!isValidDate(dob)) throw new ApiError("Enter your date of birth as YYYY-MM-DD", 400);
    if (dob < "1900-01-01" || ageOn(dob) < 18) throw new ApiError("Sellers must be at least 18 years old", 400);
    dateOfBirth = new Date(`${dob}T00:00:00Z`);

    if (input.tin) {
      const tin = input.tin.replace(/\s+/g, "");
      if (fi) {
        const born = hetuBirthDate(tin);
        if (!born) throw new ApiError("This is not a valid Finnish personal identity code (henkilötunnus)", 400);
        if (born !== dob) throw new ApiError("The personal identity code does not match the date of birth", 400);
      } else if (!/^[A-Z0-9./-]{4,30}$/.test(tin)) {
        throw new ApiError("Enter the tax identification number of your country of residence", 400);
      }
      if (!encryptionConfigured()) {
        throw new ApiError("Tax IDs cannot be saved right now because secure storage is not set up on the server. Please try again later.", 503);
      }
      tinEncrypted = encryptField(tin, tinAad(store.id));
    } else if (store.taxInfo?.tinEncrypted) {
      tinEncrypted = store.taxInfo.tinEncrypted; // keep the saved one
    } else {
      throw new ApiError("Enter your tax identification number (henkilötunnus for Finnish residents)", 400);
    }
  } else {
    if (!store.businessId) {
      throw new ApiError("Add your business ID (Y-tunnus) to the store first", 409);
    }
    if (input.vatNumber) {
      const vat = input.vatNumber.replace(/[\s.-]+/g, "");
      if (fi) {
        if (vat !== `FI${store.businessId.replace("-", "")}`) {
          throw new ApiError(`A Finnish VAT number is FI followed by the Y-tunnus without the dash (FI${store.businessId.replace("-", "")})`, 400);
        }
      } else if (!/^[A-Z]{2}[A-Z0-9]{2,13}$/.test(vat)) {
        throw new ApiError("Enter the VAT number with its country prefix, e.g. SE123456789001", 400);
      }
      vatNumber = vat;
    }
  }

  const data = {
    legalName: input.legalName, addressLine: input.addressLine, postalCode: input.postalCode, city: input.city,
    country: input.country, dateOfBirth, tinEncrypted, vatNumber,
  };
  const saved = await prisma.storeTaxInfo.upsert({
    where: { storeId: store.id },
    create: { storeId: store.id, ...data },
    update: data,
  });
  return present(store, saved);
}
