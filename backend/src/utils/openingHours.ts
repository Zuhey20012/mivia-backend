import { z } from "zod";

/**
 * Store opening hours, always in Finnish time (Europe/Helsinki, DST handled by Intl).
 * Shape: { mon: [["09:00","18:00"]], tue: [], ... }. A missing day or [] means closed that day;
 * a null/absent schedule means the store is always open. "22:00"–"02:00" runs past midnight.
 */
export const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
export type Day = (typeof DAYS)[number];
export type OpeningHours = Partial<Record<Day, [string, string][]>>;

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use HH:MM, e.g. 09:30");
export const openingHoursSchema = z
  .object(Object.fromEntries(DAYS.map((d) => [d, z.array(z.tuple([time, time])).max(3).optional()])) as Record<Day, z.ZodOptional<z.ZodArray<z.ZodTuple<[typeof time, typeof time]>>>>)
  .strict()
  .refine((h) => Object.values(h).every((ranges) => (ranges ?? []).every(([a, b]) => a !== b)), "Opening and closing time cannot be the same");

const TZ = "Europe/Helsinki";
const toMin = (hhmm: string) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));

/** Weekday (0 = mon) and minute of day in Helsinki for the given instant. */
function helsinkiClock(now: Date) {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  const day = DAYS.indexOf(get("weekday").toLowerCase().slice(0, 3) as Day);
  return { day, minute: Number(get("hour")) * 60 + Number(get("minute")) };
}

function isOpenAt(hours: OpeningHours, day: number, minute: number) {
  const today = hours[DAYS[day]] ?? [];
  const yesterday = hours[DAYS[(day + 6) % 7]] ?? [];
  // Today's ranges, and yesterday's ranges that run past midnight
  return (
    today.some(([a, b]) => (toMin(a) < toMin(b) ? minute >= toMin(a) && minute < toMin(b) : minute >= toMin(a))) ||
    yesterday.some(([a, b]) => toMin(a) > toMin(b) && minute < toMin(b))
  );
}

/** Next opening within a week, as "HH:MM" plus how many days ahead (0 = today). */
function nextOpening(hours: OpeningHours, day: number, minute: number): { day: Day; time: string; inDays: number } | null {
  for (let offset = 0; offset < 8; offset++) {
    const d = (day + offset) % 7;
    const starts = (hours[DAYS[d]] ?? []).map(([a]) => a).sort();
    const next = starts.find((a) => offset > 0 || toMin(a) > minute);
    if (next) return { day: DAYS[d], time: next, inDays: offset };
  }
  return null;
}

export type Availability = {
  openNow: boolean;
  /** "paused" (the store switched orders off), "closed" (outside opening hours) or null */
  closedReason: "paused" | "closed" | null;
  /** When a closed store opens next, e.g. { day: "tue", time: "10:00", inDays: 1 } */
  opensAt: { day: Day; time: string; inDays: number } | null;
};

export function storeAvailability(store: { acceptingOrders: boolean; openingHours: unknown }, now = new Date()): Availability {
  const parsed = store.openingHours ? openingHoursSchema.safeParse(store.openingHours) : null;
  const hours = parsed?.success ? (parsed.data as OpeningHours) : null;
  const { day, minute } = helsinkiClock(now);
  if (!store.acceptingOrders) return { openNow: false, closedReason: "paused", opensAt: null };
  if (!hours || isOpenAt(hours, day, minute)) return { openNow: true, closedReason: null, opensAt: null };
  return { openNow: false, closedReason: "closed", opensAt: nextOpening(hours, day, minute) };
}
