import { COURIER_PAY as P } from "../config/site";
import type { Lang } from "../i18n/routes";

/** Same rules as backend/src/utils/courierPay.ts (formula mode), for the worked examples on the courier page. */

export const routeKm = (straightKm: number) => Math.round(straightKm * P.roadFactor * 10) / 10;

export function examplePay(straightKm: number, approachStraightKm: number, waitMinutes: number) {
  const distanceKm = routeKm(straightKm);
  const distanceCents = Math.round(distanceKm * P.perKmCents);
  const topUpCents = Math.max(0, P.minCents - (P.baseCents + distanceCents));
  const approachKm = routeKm(approachStraightKm);
  const maxApproach = routeKm(P.approachMaxKm);
  const approachCents = Math.round(Math.max(0, Math.min(approachKm, maxApproach) - P.approachFreeKm) * P.approachPerKmCents);
  const paidMinutes = Math.max(0, Math.floor(waitMinutes) - P.waitFreeMinutes);
  const waitCents = Math.min(paidMinutes * P.waitPerMinCents, P.waitMaxCents);
  const totalCents = P.baseCents + distanceCents + topUpCents + approachCents + waitCents;
  return { distanceKm, distanceCents, topUpCents, approachKm, approachCents, waitMinutes, waitCents, totalCents };
}

export function euros(cents: number, lang: Lang): string {
  const s = (cents / 100).toFixed(2);
  // The apps write "4.50 €" in English and "4,50 €" in Finnish
  return lang === "fi" ? `${s.replace(".", ",")} €` : `${s} €`;
}

export function km(value: number, lang: Lang): string {
  const s = String(Math.round(value * 10) / 10);
  return `${lang === "fi" ? s.replace(".", ",") : s} km`;
}

export const maxWaitPaidMinutes = Math.floor(P.waitMaxCents / P.waitPerMinCents);
