import pino from "pino";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";

const logger = pino({ name: "business-check" });

/**
 * Automatic merchant check (since 2.11.0). A business seller's Y-tunnus is checked for format and check digit, then
 * looked up in the Finnish Patent and Registration Office's free open data (YTJ, avoindata.prh.fi, API v3
 * GET /opendata-ytj-api/v3/companies?businessId=…). The result pre-fills the admin's decision in Vendors; it never
 * approves a store. Private sellers have no Y-tunnus and skip it.
 *
 * Requests go only to the fixed host avoindata.prh.fi over https, with a 5 s timeout and a 12-hour cache per
 * Y-tunnus. PRH_API_TEST_HOST ("host:port", plain http) is for the e2e mock only and ignored in production.
 */
export type BusinessCheckStatus = "matched" | "name_mismatch" | "not_found" | "inactive" | "unavailable";

const PRH_HOST = "avoindata.prh.fi";
const PRH_PATH = "/opendata-ytj-api/v3/companies";
const TIMEOUT_MS = 5_000;
const CACHE_MS = 12 * 60 * 60_000;
const MAX_CACHE = 2_000;

/** Y-tunnus: 7 digits, a dash and a check digit (weights 7 9 10 5 8 4 2, mod 11; remainder 1 is never issued). */
export function isValidYTunnus(value: string) {
  const m = /^(\d{7})-(\d)$/.exec(value.trim());
  if (!m) return false;
  const weights = [7, 9, 10, 5, 8, 4, 2];
  const sum = m[1].split("").reduce((s, d, i) => s + Number(d) * weights[i], 0);
  const rem = sum % 11;
  if (rem === 1) return false;
  return Number(m[2]) === (rem === 0 ? 0 : 11 - rem);
}

function prhBase() {
  const test = env.isProduction ? "" : (process.env.PRH_API_TEST_HOST || "").trim().toLowerCase();
  return /^[a-z0-9.-]+:\d{2,5}$/.test(test) ? `http://${test}` : `https://${PRH_HOST}`;
}

type PrhName = { name?: string; type?: string; endDate?: string | null; version?: number | string };
type PrhCompany = {
  businessId?: { value?: string; registrationDate?: string };
  names?: PrhName[];
  status?: string | number;
  tradeRegisterStatus?: string | number;
  registrationDate?: string;
  endDate?: string | null;
};
type Lookup = { found: false } | { found: true; company: PrhCompany } | { unavailable: true };

const cache = new Map<string, { at: number; result: Lookup }>();

async function lookup(businessId: string): Promise<Lookup> {
  const hit = cache.get(businessId);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.result;
  let result: Lookup;
  try {
    const res = await fetch(`${prhBase()}${PRH_PATH}?businessId=${encodeURIComponent(businessId)}`, {
      headers: { Accept: "application/json" },
      redirect: "error",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.status === 404) result = { found: false };
    else if (!res.ok) result = { unavailable: true };
    else {
      const text = await res.text();
      if (text.length > 1_000_000) throw new Error("response too large");
      const body = JSON.parse(text) as { totalResults?: number; companies?: PrhCompany[] };
      const company = (body.companies ?? []).find((c) => c.businessId?.value === businessId);
      result = company ? { found: true, company } : { found: false };
    }
  } catch (e: any) {
    logger.warn({ err: e?.message }, "PRH lookup failed");
    result = { unavailable: true };
  }
  // Only real answers are cached; an outage is retried next time
  if (!("unavailable" in result)) {
    if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value!);
    cache.set(businessId, { at: Date.now(), result });
  }
  return result;
}

/** Lower case, accents folded, punctuation and company-form words (oy, oyj, ab, ky, ay, tmi, ltd …) removed. */
export function normaliseName(name: string) {
  return name
    .toLowerCase()
    .normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9 ]+/g, " ")
    .split(/\s+/)
    .filter((w) => w && !["oy", "oyj", "ab", "abp", "ky", "ay", "tmi", "ltd", "osk", "ry", "kommandiittiyhtio", "osakeyhtio", "toiminimi", "avoin", "yhtio"].includes(w))
    .join(" ");
}

function namesMatch(candidates: string[], registered: string[]) {
  const reg = registered.map(normaliseName).filter(Boolean);
  return candidates.map(normaliseName).filter((c) => c.length >= 2).some((c) =>
    reg.some((r) => r === c || (c.length >= 4 && r.includes(c)) || (r.length >= 4 && c.includes(r))));
}

const lastPart = (v: unknown) => String(v ?? "").split("_").pop();

/** Evaluates one PRH answer against the names the store gave (store name, and the DAC7 legal name when given). */
export function evaluate(result: Lookup, storeNames: string[]): { status: BusinessCheckStatus; registeredName: string | null; registeredAt: Date | null } {
  if ("unavailable" in result) return { status: "unavailable", registeredName: null, registeredAt: null };
  if (!result.found) return { status: "not_found", registeredName: null, registeredAt: null };
  const c = result.company;
  const current = (c.names ?? []).filter((n) => n.name && !n.endDate && (n.version === undefined || String(n.version) === "1"));
  const main = current.find((n) => String(n.type) === "1") ?? current[0] ?? (c.names ?? [])[0];
  const registeredName = main?.name ?? null;
  const date = c.registrationDate ?? c.businessId?.registrationDate;
  const registeredAt = date && /^\d{4}-\d{2}-\d{2}$/.test(date) ? new Date(`${date}T00:00:00Z`) : null;
  // Ceased or removed from the register, or the business ID was invalidated (YTJ code lists STATUS3 and REK_KDI)
  const inactive = !!c.endDate || String(c.status ?? "") === "5" || ["2", "4"].includes(lastPart(c.tradeRegisterStatus) ?? "");
  if (inactive) return { status: "inactive", registeredName, registeredAt };
  const allNames = current.length ? current.map((n) => n.name!) : registeredName ? [registeredName] : [];
  return { status: namesMatch(storeNames, allNames) ? "matched" : "name_mismatch", registeredName, registeredAt };
}

/** Runs the check for a store and stores the result on it. Private sellers and stores without a Y-tunnus are skipped. */
export async function runBusinessCheck(storeId: number) {
  const store = await prisma.store.findUnique({
    where: { id: storeId },
    select: { id: true, name: true, ownerId: true, sellerType: true, businessId: true, taxInfo: { select: { legalName: true } } },
  });
  if (!store || store.sellerType !== "BUSINESS" || !store.businessId || !isValidYTunnus(store.businessId)) return null;
  const result = await lookup(store.businessId);
  const verdict = evaluate(result, [store.name, ...(store.taxInfo?.legalName ? [store.taxInfo.legalName] : [])]);
  const checkedAt = new Date();
  await prisma.store.update({
    where: { id: store.id },
    data: {
      businessCheckStatus: verdict.status,
      businessRegisteredName: verdict.registeredName,
      businessRegisteredAt: verdict.registeredAt,
      businessCheckedAt: checkedAt,
    },
  });
  const { checkReadyForApproval } = await import("../onboarding/onboarding");
  await checkReadyForApproval(store.ownerId, "VENDOR").catch(() => {});
  return { ...verdict, checkedAt, businessId: store.businessId };
}

/** The check as the admin panel and the store app show it. */
export function businessCheckOf(s: { sellerType: string; businessId: string | null; businessCheckStatus: string | null; businessRegisteredName: string | null; businessRegisteredAt: Date | null; businessCheckedAt: Date | null }) {
  if (s.sellerType !== "BUSINESS") return { required: false, verificationStatus: null, registeredName: null, registeredAt: null, checkedAt: null, businessId: null };
  return {
    required: true,
    businessId: s.businessId,
    verificationStatus: s.businessCheckStatus as BusinessCheckStatus | null,
    registeredName: s.businessRegisteredName,
    registeredAt: s.businessRegisteredAt,
    checkedAt: s.businessCheckedAt,
  };
}
