import { env, CourierPayConfig } from "../config/env";

/**
 * Courier pay per job, explainable line by line (EU Platform Work Directive 2024/2831: people working
 * through a platform must be told how their pay is set). It is separate from the delivery fee the customer
 * pays (utils/pricing.ts#deliveryFeeForDistance); the difference is Malvoya's delivery margin, which may
 * be negative.
 *
 *   formula:   max(base + route km × per km, minimum)      shop → customer, known before accepting
 *              + (ride km to the shop − free km) × per km  courier's position when accepting → shop
 *              + (minutes at the shop − free) × per min    "arrived at shop" → pickup, capped
 *              + tip (100 %)
 *              route/ride km = straight line × road factor, rounded to 0.1 km
 *   fee_share: delivery fee × share + tip (the pre-2.7 rule, kept as a switch)
 *
 * Every amount is integer cents (EUR).
 */

export type CourierPayMode = "formula" | "fee_share";
type Text = { en: string; fi: string };

export type CourierPay = {
  mode: CourierPayMode;
  baseCents: number;
  distanceKm: number | null; // shop → customer route km (null when the address had no coordinates)
  perKmCents: number;
  distanceCents: number;
  minimumCents: number; // guaranteed minimum for base + distance (0 = none)
  topUpCents: number; // added to reach the minimum
  approachKm: number | null; // ride to the shop in route km (null = not known yet)
  approachCents: number;
  waitMinutes: number;
  waitCents: number;
  tipCents: number;
  totalCents: number; // = Order.courierFeeCents
  formula: string; // the rule in one English sentence (= summary.en)
  summary: Text; // the rule in one sentence, en/fi, from the env values
  explanation: Text; // this job's numbers in one line, en/fi
  waitPolicy: Text; // how waiting at the shop is paid
  /** The rates in force when the job was priced. Ride-to-shop and waiting pay always use these, so a
   *  later change of settings never changes a job the courier has already been offered or accepted. */
  rates?: CourierPayConfig;
};

const moneyEn = (c: number) => `${(c / 100).toFixed(2)} €`;
const moneyFi = (c: number) => `${(c / 100).toFixed(2).replace(".", ",")} €`;
const kmEn = (k: number) => String(Math.round(k * 10) / 10);
const kmFi = (k: number) => kmEn(k).replace(".", ",");

/** Straight-line km → route km used for pay (× road factor, rounded to 0.1 km). */
export function routeKm(straightKm: number | null | undefined, cfg: CourierPayConfig = env.courierPay): number | null {
  if (straightKm === null || straightKm === undefined || !Number.isFinite(straightKm) || straightKm < 0) return null;
  return Math.round(straightKm * cfg.roadFactor * 10) / 10;
}

/** Waiting pay for whole minutes at the shop beyond the free ones, capped. */
export function waitPayFor(waitMinutes: number, cfg: CourierPayConfig = env.courierPay) {
  const paidMinutes = Math.max(0, Math.floor(waitMinutes) - cfg.waitFreeMinutes);
  return Math.min(paidMinutes * cfg.waitPerMinCents, cfg.waitMaxCents);
}

/** Pay for the ride to the shop (route km) beyond the free km. */
export function approachPayFor(approachKm: number | null, cfg: CourierPayConfig = env.courierPay) {
  if (approachKm === null) return 0;
  return Math.round(Math.max(0, approachKm - cfg.approachFreeKm) * cfg.approachPerKmCents);
}

/** The pay rule in one sentence, built from the current settings. */
export function payRuleSummary(cfg: CourierPayConfig = env.courierPay, mode: CourierPayMode = cfg.mode): Text {
  if (mode === "fee_share") {
    const pct = Math.round(cfg.feeShare * 100);
    return {
      en: `Every delivery pays ${pct} % of the delivery fee the customer pays, and you keep 100 % of tips.`,
      fi: `Jokaisesta toimituksesta saat ${pct} % asiakkaan maksamasta toimitusmaksusta, ja juomarahat ovat 100 % sinun.`,
    };
  }
  const en = [`Every delivery pays ${moneyEn(cfg.baseCents)} plus ${moneyEn(cfg.perKmCents)} per km from shop to customer`];
  const fi = [`Jokainen toimitus maksaa ${moneyFi(cfg.baseCents)} sekä ${moneyFi(cfg.perKmCents)} jokaiselta kilometriltä liikkeestä asiakkaalle`];
  if (cfg.minCents > 0) { en[0] += ` (at least ${moneyEn(cfg.minCents)})`; fi[0] += ` (vähintään ${moneyFi(cfg.minCents)})`; }
  if (cfg.approachPerKmCents > 0) {
    en.push(`plus ${moneyEn(cfg.approachPerKmCents)}/km for the ride to the shop beyond ${kmEn(cfg.approachFreeKm)} km`);
    fi.push(`${moneyFi(cfg.approachPerKmCents)}/km ajosta liikkeeseen ${kmFi(cfg.approachFreeKm)} km:n ylittävältä osalta`);
  }
  if (cfg.waitPerMinCents > 0 && cfg.waitMaxCents > 0) {
    en.push(`plus ${moneyEn(cfg.waitPerMinCents)}/min for waiting at the shop after ${cfg.waitFreeMinutes} minutes`);
    fi.push(`${moneyFi(cfg.waitPerMinCents)}/min odotuksesta liikkeessä ${cfg.waitFreeMinutes} minuutin jälkeen`);
  }
  return {
    en: `${en.join(", ")}, and you keep 100 % of tips.`,
    fi: `${fi[0]}${fi.length > 1 ? `, lisäksi ${fi.slice(1).join(" sekä ")}` : ""}. Juomarahat ovat 100 % sinun.`,
  };
}

function waitPolicyFor(mode: CourierPayMode, cfg: CourierPayConfig): Text {
  if (mode === "fee_share" || cfg.waitPerMinCents === 0 || cfg.waitMaxCents === 0) {
    return { en: "Waiting at the shop is not paid separately.", fi: "Odotusta liikkeessä ei makseta erikseen." };
  }
  return {
    en: `Waiting at the shop: the first ${cfg.waitFreeMinutes} min are included, then ${moneyEn(cfg.waitPerMinCents)}/min, ` +
      `max ${moneyEn(cfg.waitMaxCents)}. Tap "Arrived at shop" when you get there; it is added at pickup.`,
    fi: `Odotus liikkeessä: ensimmäiset ${cfg.waitFreeMinutes} min sisältyvät, sen jälkeen ${moneyFi(cfg.waitPerMinCents)}/min, ` +
      `enintään ${moneyFi(cfg.waitMaxCents)}. Paina "Saavuin liikkeeseen" kun olet perillä; odotus lisätään noudettaessa.`,
  };
}

type Parts = Omit<CourierPay, "explanation" | "formula" | "summary" | "waitPolicy" | "totalCents">;

function explain(p: Parts & { totalCents: number }): Text {
  const en: string[] = [];
  const fi: string[] = [];
  if (p.mode === "fee_share") {
    en.push(`${moneyEn(p.baseCents)} share of the delivery fee`);
    fi.push(`${moneyFi(p.baseCents)} osuus toimitusmaksusta`);
  } else {
    en.push(`${moneyEn(p.baseCents)} base`);
    fi.push(`${moneyFi(p.baseCents)} perusmaksu`);
    if (p.distanceKm === null) {
      en.push("distance unknown");
      fi.push("matka tuntematon");
    } else {
      en.push(`${kmEn(p.distanceKm)} km × ${moneyEn(p.perKmCents)}/km = ${moneyEn(p.distanceCents)}`);
      fi.push(`${kmFi(p.distanceKm)} km × ${moneyFi(p.perKmCents)}/km = ${moneyFi(p.distanceCents)}`);
    }
    if (p.topUpCents > 0) {
      en.push(`${moneyEn(p.topUpCents)} to reach the ${moneyEn(p.minimumCents)} minimum`);
      fi.push(`${moneyFi(p.topUpCents)} korotus ${moneyFi(p.minimumCents)} vähimmäispalkkioon`);
    }
    if (p.approachCents > 0 && p.approachKm !== null) {
      en.push(`ride to shop ${kmEn(p.approachKm)} km = ${moneyEn(p.approachCents)}`);
      fi.push(`ajo liikkeeseen ${kmFi(p.approachKm)} km = ${moneyFi(p.approachCents)}`);
    }
  }
  if (p.waitCents > 0) {
    en.push(`waiting ${p.waitMinutes} min = ${moneyEn(p.waitCents)}`);
    fi.push(`odotus ${p.waitMinutes} min = ${moneyFi(p.waitCents)}`);
  }
  if (p.tipCents > 0) {
    en.push(`tip ${moneyEn(p.tipCents)}`);
    fi.push(`juomaraha ${moneyFi(p.tipCents)}`);
  }
  return { en: `${en.join(" + ")} = ${moneyEn(p.totalCents)}`, fi: `${fi.join(" + ")} = ${moneyFi(p.totalCents)}` };
}

function finish(p: Parts, cfg: CourierPayConfig): CourierPay {
  const totalCents = p.baseCents + p.distanceCents + p.topUpCents + p.approachCents + p.waitCents + p.tipCents;
  const summary = payRuleSummary(cfg, p.mode);
  return { ...p, totalCents, formula: summary.en, summary, explanation: explain({ ...p, totalCents }), waitPolicy: waitPolicyFor(p.mode, cfg) };
}

/**
 * Pay for one job. `straightKm` is the shop → customer straight-line distance (as used for the customer's
 * delivery fee). The ride to the shop is known when a courier accepts, the waiting time at pickup.
 */
export function calcCourierPay(input: {
  straightKm: number | null;
  deliveryFeeCents: number;
  tipCents?: number;
  approachStraightKm?: number | null;
  waitMinutes?: number;
  config?: CourierPayConfig;
}): CourierPay {
  const cfg = input.config ?? env.courierPay;
  const tipCents = input.tipCents ?? 0;
  const distanceKm = routeKm(input.straightKm, cfg);

  if (cfg.mode === "fee_share") {
    return finish({
      mode: "fee_share", baseCents: Math.round(input.deliveryFeeCents * cfg.feeShare), distanceKm, perKmCents: 0,
      distanceCents: 0, minimumCents: 0, topUpCents: 0, approachKm: null, approachCents: 0, waitMinutes: 0, waitCents: 0, tipCents,
      rates: cfg,
    }, cfg);
  }

  const distanceCents = distanceKm === null ? 0 : Math.round(distanceKm * cfg.perKmCents);
  const topUpCents = Math.max(0, cfg.minCents - (cfg.baseCents + distanceCents));
  const approachKm = routeKm(input.approachStraightKm, cfg);
  const waitMinutes = Math.max(0, Math.floor(input.waitMinutes ?? 0));
  return finish({
    mode: "formula", baseCents: cfg.baseCents, distanceKm, perKmCents: cfg.perKmCents, distanceCents,
    minimumCents: cfg.minCents, topUpCents, approachKm, approachCents: approachPayFor(approachKm, cfg),
    waitMinutes, waitCents: waitPayFor(waitMinutes, cfg), tipCents,
    rates: cfg,
  }, cfg);
}

function strip(pay: CourierPay): Parts {
  const { explanation, formula, summary, waitPolicy, totalCents, ...rest } = pay;
  // Breakdowns stored before approach pay existed have no approach fields
  return { ...rest, approachKm: rest.approachKm ?? null, approachCents: rest.approachCents ?? 0 };
}

/** Adds the ride to the shop (courier's position → shop, straight-line km) when a courier accepts (formula mode). */
export function withApproach(pay: CourierPay, approachStraightKm: number | null, cfg: CourierPayConfig = env.courierPay): CourierPay {
  if (pay.mode !== "formula") return pay;
  const rates = pay.rates ?? cfg; // the job's own rates, not today's settings
  const approachKm = routeKm(approachStraightKm, rates);
  return finish({ ...strip(pay), approachKm, approachCents: approachPayFor(approachKm, rates) }, rates);
}

/** Adds the waiting time measured at pickup (formula mode). */
export function withWaiting(pay: CourierPay, waitMinutes: number, cfg: CourierPayConfig = env.courierPay): CourierPay {
  if (pay.mode !== "formula") return pay;
  const rates = pay.rates ?? cfg; // the job's own rates, not today's settings
  const minutes = Math.max(0, Math.floor(waitMinutes));
  return finish({ ...strip(pay), waitMinutes: minutes, waitCents: waitPayFor(minutes, rates) }, rates);
}

type OrderPayFields = {
  courierPay?: unknown;
  courierFeeCents: number;
  tipCents: number;
  deliveryFeeCents: number;
};

function isCourierPay(v: unknown): v is CourierPay {
  return !!v && typeof v === "object" && typeof (v as CourierPay).totalCents === "number" && !!(v as CourierPay).explanation;
}

/**
 * The pay breakdown of an order. Orders made before 2.7 (or inserted without one) get a breakdown
 * derived from their stored courierFeeCents, so the number shown is always the number paid.
 */
export function courierPayOf(order: OrderPayFields): CourierPay {
  if (isCourierPay(order.courierPay) && order.courierPay.totalCents === order.courierFeeCents) {
    const stored = order.courierPay;
    return { ...stored, approachKm: stored.approachKm ?? null, approachCents: stored.approachCents ?? 0 };
  }
  const base = Math.max(0, order.courierFeeCents - order.tipCents);
  const tipEn = order.tipCents ? ` + tip ${moneyEn(order.tipCents)}` : "";
  const tipFi = order.tipCents ? ` + juomaraha ${moneyFi(order.tipCents)}` : "";
  const summary = {
    en: "This job has a fixed fee, and you keep 100 % of tips.",
    fi: "Tällä toimituksella on kiinteä palkkio, ja juomarahat ovat 100 % sinun.",
  };
  return {
    mode: "fee_share", baseCents: base, distanceKm: null, perKmCents: 0, distanceCents: 0, minimumCents: 0, topUpCents: 0,
    approachKm: null, approachCents: 0, waitMinutes: 0, waitCents: 0, tipCents: order.tipCents, totalCents: order.courierFeeCents,
    formula: summary.en,
    summary,
    explanation: {
      en: `${moneyEn(base)} fixed fee${tipEn} = ${moneyEn(order.courierFeeCents)}`,
      fi: `${moneyFi(base)} kiinteä palkkio${tipFi} = ${moneyFi(order.courierFeeCents)}`,
    },
    waitPolicy: waitPolicyFor("fee_share", env.courierPay),
  };
}

/**
 * What couriers see (offers, job list, own orders). `approachStraightKm` (this courier's distance to the shop)
 * gives an estimate of the ride-to-shop pay on a job nobody has accepted yet.
 */
export function presentCourierPay(order: OrderPayFields, opts: { approachStraightKm?: number | null } = {}) {
  let p = courierPayOf(order);
  if (p.mode === "formula" && p.approachKm === null && opts.approachStraightKm != null) p = withApproach(p, opts.approachStraightKm);
  return {
    mode: p.mode,
    baseCents: p.baseCents,
    distanceKm: p.distanceKm,
    perKmCents: p.perKmCents,
    distanceCents: p.distanceCents,
    minimumCents: p.minimumCents,
    topUpCents: p.topUpCents,
    approachKm: p.approachKm,
    approachCents: p.approachCents,
    waitMinutes: p.waitMinutes,
    waitCents: p.waitCents,
    tipCents: p.tipCents,
    totalCents: p.totalCents,
    formula: p.formula,
    summary: p.summary,
    explanation: p.explanation,
    waitPolicy: p.waitPolicy,
  };
}
