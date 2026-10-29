import { Prisma } from "@prisma/client";
import { prisma } from "./prisma";
import { publish, subscribe } from "./redis";
import { ApiError } from "./errors";
import { audit } from "./audit";

/**
 * Runtime switches (since 2.16.0): admins pause parts of the marketplace without a deploy (admin panel → Switches).
 * Stored in PlatformSetting as { on, message }, audited, cached 30 s per instance (dropped at once on every instance
 * with REDIS_URL). `on` means the switch is in its "paused"/"enabled" state as named: ordersPaused on = no new orders;
 * liveEnabled on = stores may go live.
 */
export const SWITCHES = {
  ordersPaused: { default: false, code: "ORDERS_PAUSED", label: "Pause all new orders",
    message: "Malvoya is not taking new orders right now. Please try again later." },
  deliveryPaused: { default: false, code: "DELIVERY_PAUSED", label: "Pause courier delivery (pickup still works)",
    message: "Delivery is paused right now. You can still choose Reserve & collect." },
  pickupPaused: { default: false, code: "PICKUP_PAUSED", label: "Pause Reserve & collect",
    message: "Reserve & collect is paused right now." },
  liveEnabled: { default: true, code: "LIVE_PAUSED", label: "Stores may go live",
    message: "Live shopping is paused right now." },
  dropsPostingEnabled: { default: true, code: "DROPS_PAUSED", label: "Stores may post new drops",
    message: "Posting new drops is paused right now." },
  signupsPaused: { default: false, code: "SIGNUPS_PAUSED", label: "Pause new accounts",
    message: "New sign-ups are paused right now. Please try again later." },
} as const;
export type SwitchKey = keyof typeof SWITCHES;
export const SWITCH_KEYS = Object.keys(SWITCHES) as SwitchKey[];

type SwitchValue = { on: boolean; message: string | null; updatedAt: Date | null; updatedById: number | null };

const TTL_MS = 30_000;
let cache: { at: number; values: Map<string, SwitchValue> } | null = null;
const CHANNEL = "settings-changed";
subscribe(CHANNEL, () => { cache = null; });

async function load() {
  if (cache && Date.now() - cache.at < TTL_MS) return cache.values;
  const rows = await prisma.platformSetting.findMany({ where: { key: { in: SWITCH_KEYS } } }).catch(() => null);
  const values = new Map<string, SwitchValue>();
  for (const r of rows ?? []) {
    const v = (r.value ?? {}) as { on?: unknown; message?: unknown };
    values.set(r.key, {
      on: typeof v.on === "boolean" ? v.on : SWITCHES[r.key as SwitchKey].default,
      message: typeof v.message === "string" && v.message.trim() ? v.message.trim() : null,
      updatedAt: r.updatedAt, updatedById: r.updatedById,
    });
  }
  if (rows) cache = { at: Date.now(), values };
  return values;
}

export async function switchValue(key: SwitchKey): Promise<SwitchValue> {
  return (await load()).get(key) ?? { on: SWITCHES[key].default, message: null, updatedAt: null, updatedById: null };
}

/** Every switch, for System, the admin Switches card and /app-config. */
export async function allSwitches() {
  const values = await load();
  return SWITCH_KEYS.map((key) => {
    const v = values.get(key);
    return {
      key, label: SWITCHES[key].label, default: SWITCHES[key].default,
      on: v?.on ?? SWITCHES[key].default,
      message: v?.message ?? SWITCHES[key].message,
      customMessage: v?.message ?? null,
      updatedAt: v?.updatedAt ?? null,
      updatedById: v?.updatedById ?? null,
    };
  });
}

/** True when this switch blocks the action (a "…Paused" switch that is on, or an "…Enabled" switch that is off). */
export async function blocked(key: SwitchKey): Promise<string | null> {
  const v = await switchValue(key);
  const blocks = key.endsWith("Enabled") ? !v.on : v.on;
  return blocks ? v.message ?? SWITCHES[key].message : null;
}

/** Throws 503 { code, error } when the switch blocks the action. */
export async function assertOpen(key: SwitchKey) {
  const message = await blocked(key);
  if (message) {
    const e = new ApiError(message, 503);
    e.extra = { code: SWITCHES[key].code };
    throw e;
  }
}

/** PATCH /admin/settings/:key — audited (old and new value). */
export async function setSwitch(adminId: number, key: SwitchKey, on: boolean, message: string | null) {
  const before = await switchValue(key);
  const value = { on, ...(message?.trim() ? { message: message.trim().slice(0, 300) } : {}) } as Prisma.InputJsonValue;
  await prisma.platformSetting.upsert({ where: { key }, create: { key, value, updatedById: adminId }, update: { value, updatedById: adminId } });
  cache = null;
  publish(CHANNEL, key);
  await audit(adminId, "setting.update", "PlatformSetting", 0, {
    oldValue: { key, on: before.on, message: before.message },
    newValue: { key, on, message: message?.trim() || null },
  });
  return (await allSwitches()).find((s) => s.key === key)!;
}
