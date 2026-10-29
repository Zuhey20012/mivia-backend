import { type Raw, str, obj, bool, ShapeError } from './parse';

// Runtime switches (2.16, contract C16), shared by the Switches page and the System summary.

export type SwitchKey = 'ordersPaused' | 'deliveryPaused' | 'pickupPaused' | 'liveEnabled' | 'dropsPostingEnabled' | 'signupsPaused';
export type Message = { en: string; fi: string } | string;
// message = the admin's own text ('' = none); defaultMessage = the API's built-in text, used while message is empty
export type Switch = { key: SwitchKey; value: boolean; message: Message; defaultMessage: string | null; updatedAt: string | null; updatedBy: string | null };

/** `stopsWhen`: the value at which something is switched off for users. */
export const SWITCHES: { key: SwitchKey; title: string; on: string; off: string; stopsWhen: boolean; help: string; danger?: boolean }[] = [
  { key: 'ordersPaused', title: 'Ordering', on: 'Customers can order', off: 'Ordering is paused', stopsWhen: true, danger: true,
    help: 'Pausing stops every new checkout (delivery and pickup). Orders already paid continue normally.' },
  { key: 'deliveryPaused', title: 'Home delivery', on: 'Delivery can be ordered', off: 'Delivery is paused', stopsWhen: true, danger: true,
    help: 'Pausing stops new delivery orders only; Reserve & collect still works. Use it when no couriers are available.' },
  { key: 'pickupPaused', title: 'Reserve & collect', on: 'Pickup can be ordered', off: 'Pickup is paused', stopsWhen: true,
    help: 'Pausing stops new pickup orders only.' },
  { key: 'liveEnabled', title: 'Live video', on: 'Stores can go live', off: 'Lives are off', stopsWhen: false,
    help: 'Turning it off stops new lives from starting. End a running live on the Live page.' },
  { key: 'dropsPostingEnabled', title: 'Posting drops', on: 'Stores can post drops', off: 'Posting drops is off', stopsWhen: false,
    help: 'Turning it off stops new drops; existing drops stay visible.' },
  { key: 'signupsPaused', title: 'New accounts', on: 'People can sign up', off: 'Sign-ups are paused', stopsWhen: true,
    help: 'Pausing refuses new accounts (all apps); existing accounts can still sign in.' },
];

const readMessage = (v: unknown): Message => {
  if (typeof v === 'string') return v;
  const o = obj(v);
  if (typeof o.en === 'string' || typeof o.fi === 'string') return { en: str(o.en) ?? '', fi: str(o.fi) ?? '' };
  return '';
};

/** Accepts a map {key: {value|on|enabled, message}} or {key: boolean}, a list [{key, value, message}], or flat fields. */
export function parseSwitches(data: Raw): Switch[] {
  const container = data.switches ?? data.settings ?? data.platformSettings;
  const byKey: Record<string, Raw> = {};
  if (Array.isArray(container)) {
    for (const row of container as Raw[]) { const k = str(row.key); if (k) byKey[k] = row; }
  } else if (container && typeof container === 'object') {
    for (const [k, v] of Object.entries(container as Raw)) byKey[k] = typeof v === 'boolean' ? { value: v } : obj(v);
  } else {
    for (const s of SWITCHES) if (typeof data[s.key] === 'boolean') byKey[s.key] = { value: data[s.key], message: data[`${s.key}Message`] };
  }
  const found = SWITCHES.filter((s) => s.key in byKey);
  if (found.length === 0) throw new ShapeError('The API answer has no switches.');
  return found.map((s) => {
    const row = byKey[s.key];
    const value = obj(row.value);
    const flag = bool(row.value) ?? bool(row.on) ?? bool(row.enabled) ?? bool(value.on) ?? bool(value.enabled) ?? bool(value.value) ?? !s.stopsWhen;
    const by = obj(row.updatedBy);
    // Backend 2.16 (lib/settings.ts#allSwitches): { key, on, message (in effect), customMessage (admin's own | null) }
    const hasCustom = 'customMessage' in row;
    return {
      key: s.key,
      value: flag,
      message: readMessage(hasCustom ? row.customMessage : row.message ?? value.message),
      defaultMessage: hasCustom ? str(row.message) : null,
      updatedAt: str(row.updatedAt),
      updatedBy: str(row.updatedBy) ?? str(by.email) ?? str(by.name) ?? (typeof row.updatedById === 'number' ? `admin #${row.updatedById}` : null),
    };
  });
}

