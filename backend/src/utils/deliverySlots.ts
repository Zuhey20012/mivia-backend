import { env } from "../config/env";
import { storeAvailability } from "./openingHours";

/**
 * Scheduled delivery slots ("Tonight 17:00–19:00"). Slots are platform-wide (DELIVERY_SLOTS), in Finnish time
 * (Europe/Helsinki, DST handled by Intl), bookable for today or tomorrow when they start at least
 * `leadMinutes` from now and the store is open at the slot start.
 */
const TZ = "Europe/Helsinki";
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export type SlotInput = { date: string; start: string; end: string };
export type Slot = SlotInput & { startAt: Date; endAt: Date; label: { en: string; fi: string } };

const partsFmt = new Intl.DateTimeFormat("en-GB", {
  timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
});

function helsinkiFields(at: Date) {
  const p = partsFmt.formatToParts(at);
  const g = (t: string) => p.find((x) => x.type === t)?.value ?? "00";
  return { y: g("year"), m: g("month"), d: g("day"), h: g("hour"), mi: g("minute"), s: g("second") };
}

/** "YYYY-MM-DD" and "HH:MM" of an instant in Helsinki. */
export function helsinkiParts(at: Date) {
  const f = helsinkiFields(at);
  return { date: `${f.y}-${f.m}-${f.d}`, time: `${f.h}:${f.mi}` };
}

/** Helsinki UTC offset (ms) at an instant. */
function offsetMs(at: Date) {
  const f = helsinkiFields(at);
  const asUtc = Date.UTC(Number(f.y), Number(f.m) - 1, Number(f.d), Number(f.h), Number(f.mi), Number(f.s));
  return asUtc - Math.floor(at.getTime() / 1000) * 1000;
}

/** The instant of a Helsinki wall-clock time, e.g. ("2026-10-15", "17:00") → 2026-10-15T14:00:00Z. */
export function helsinkiInstant(date: string, hhmm: string) {
  const [y, m, d] = date.split("-").map(Number);
  const [h, mi] = hhmm.split(":").map(Number);
  const guess = Date.UTC(y, m - 1, d, h, mi);
  let t = guess - offsetMs(new Date(guess));
  t = guess - offsetMs(new Date(t)); // second pass settles DST changes
  return new Date(t);
}

/** "YYYY-MM-DD" plus n calendar days. */
export function addDays(date: string, n: number) {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** A real calendar date in YYYY-MM-DD form. */
export function isValidDate(date: string) {
  if (!DATE_RE.test(date)) return false;
  const [y, m, d] = date.split("-").map(Number);
  const back = new Date(Date.UTC(y, m - 1, d));
  return back.getUTCFullYear() === y && back.getUTCMonth() === m - 1 && back.getUTCDate() === d;
}

const fiTime = (hhmm: string) => hhmm.replace(":", ".");

function slotLabel(date: string, start: string, end: string, now: Date) {
  const today = helsinkiParts(now).date;
  const span = { en: `${start}–${end}`, fi: `${fiTime(start)}–${fiTime(end)}` };
  if (date === today) {
    return start >= "17:00"
      ? { en: `Tonight ${span.en}`, fi: `Tänä iltana ${span.fi}` }
      : { en: `Today ${span.en}`, fi: `Tänään ${span.fi}` };
  }
  if (date === addDays(today, 1)) return { en: `Tomorrow ${span.en}`, fi: `Huomenna ${span.fi}` };
  const [, m, d] = date.split("-").map(Number);
  return { en: `${d}/${m} ${span.en}`, fi: `${d}.${m}. ${span.fi}` };
}

/** "17:00–19:00" (today), "tomorrow 17:00–19:00" — for pushes and emails about an order's window. */
export function windowText(startAt: Date, endAt: Date, now = new Date()) {
  const s = helsinkiParts(startAt);
  const e = helsinkiParts(endAt);
  return slotLabel(s.date, s.time, e.time, now);
}

type SlotStore = { openingHours: unknown };

/** Whether the store's opening hours (pause switch ignored) have it open at that instant. */
function openAt(store: SlotStore, at: Date) {
  return storeAvailability({ acceptingOrders: true, openingHours: store.openingHours }, at).openNow;
}

/** Slots a customer can book from this store right now (today and tomorrow). */
export function availableSlots(store: SlotStore, now = new Date()): Slot[] {
  const cfg = env.scheduledDelivery;
  const today = helsinkiParts(now).date;
  const earliest = now.getTime() + cfg.leadMinutes * 60_000;
  const out: Slot[] = [];
  for (const date of [today, addDays(today, 1)]) {
    for (const s of cfg.slots) {
      const startAt = helsinkiInstant(date, s.start);
      if (startAt.getTime() < earliest || !openAt(store, startAt)) continue;
      out.push({ date, start: s.start, end: s.end, startAt, endAt: helsinkiInstant(date, s.end), label: slotLabel(date, s.start, s.end, now) });
    }
  }
  return out;
}

/**
 * Checks a slot the customer picked. Returns the slot, or a user-readable reason with the HTTP status
 * (400 = not a slot Malvoya offers, 409 = no longer bookable / store closed then).
 */
export function checkSlot(store: SlotStore, input: SlotInput, now = new Date()): { slot: Slot } | { error: string; status: number } {
  const cfg = env.scheduledDelivery;
  if (!isValidDate(input.date) || !cfg.slots.some((s) => s.start === input.start && s.end === input.end)) {
    return { error: "This delivery time is not offered. Pick one of the times shown.", status: 400 };
  }
  const today = helsinkiParts(now).date;
  if (input.date !== today && input.date !== addDays(today, 1)) {
    return { error: "Deliveries can be scheduled for today or tomorrow.", status: 400 };
  }
  const startAt = helsinkiInstant(input.date, input.start);
  if (startAt.getTime() < now.getTime() + cfg.leadMinutes * 60_000) {
    return { error: `This delivery time is too soon. Pick a time that starts at least ${cfg.leadMinutes} minutes from now.`, status: 409 };
  }
  if (!openAt(store, startAt)) {
    return { error: "The store is closed at that time. Pick another delivery time.", status: 409 };
  }
  return {
    slot: { ...input, startAt, endAt: helsinkiInstant(input.date, input.end), label: slotLabel(input.date, input.start, input.end, now) },
  };
}

/** When couriers are first offered a scheduled job: slot start − the store's prep time − the buffer. */
export function dispatchAt(scheduledStart: Date, prepMinutes: number) {
  return new Date(scheduledStart.getTime() - (prepMinutes + env.scheduledDelivery.dispatchBufferMinutes) * 60_000);
}

/**
 * Scheduled orders become jobs only from slot start − prep time − 15 min. Prep time is at most 120 min, so
 * anything starting later than this is certainly not open to couriers yet (keeps lists and batches small).
 */
export function scheduledDispatchHorizon(now = Date.now()) {
  return new Date(now + (120 + env.scheduledDelivery.dispatchBufferMinutes) * 60_000);
}

/** Whether a scheduled order is still too early to be offered to couriers. */
export function beforeDispatch(o: { scheduledStart: Date | null }, prepMinutes: number, now = Date.now()) {
  return !!o.scheduledStart && now < dispatchAt(o.scheduledStart, prepMinutes).getTime();
}

/** Delivery fee for a scheduled slot: the normal fee less the platform's scheduled-delivery discount, never below 0. */
export function scheduledFee(deliveryFeeCents: number) {
  return Math.max(0, deliveryFeeCents - env.scheduledDelivery.discountCents);
}
