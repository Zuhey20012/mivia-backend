import { isAxiosError } from 'axios';

// Small readers for API answers. The pages parse defensively: a missing or renamed field shows "—",
// and a failed request shows its error, never a silently empty list.

export type Raw = Record<string, unknown>;

export const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
export const str = (v: unknown): string | null => (typeof v === 'string' && v ? v : null);
export const arr = (v: unknown): Raw[] => (Array.isArray(v) ? (v as Raw[]) : []);
export const obj = (v: unknown): Raw => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Raw) : {});
export const bool = (v: unknown): boolean | null => (typeof v === 'boolean' ? v : null);

/** The first value that is an array, or null when none is (so "no list in the answer" is not mistaken for "empty"). */
export const firstList = (...values: unknown[]): Raw[] | null => {
  const found = values.find(Array.isArray);
  return found ? (found as Raw[]) : null;
};

/** Thrown by a page when the answer does not have the expected shape; its message is shown as is. */
export class ShapeError extends Error {
  constructor(message: string) { super(message); this.name = 'ShapeError'; }
}

/** The API's own message (safe to show, see lib/errors.ts) or a fallback. */
export const errorText = (e: unknown, fallback: string): string => {
  if (e instanceof ShapeError) return e.message;
  if (isAxiosError(e)) {
    const msg = e.response?.data?.error;
    if (typeof msg === 'string' && msg) return msg;
    if (e.response?.status === 404) return `${fallback} (the API does not offer this yet: 404)`;
    if (!e.response) return `${fallback} (the API could not be reached)`;
  }
  return fallback;
};

export const euro = (cents: number | null | undefined): string =>
  typeof cents === 'number' && Number.isFinite(cents) ? `${(cents / 100).toFixed(2).replace('.', ',')} €` : '—';

/** Finnish date and time, e.g. "29.10.2026 klo 14.05". */
export const fiDate = (iso: string | null | undefined): string => {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isFinite(d.getTime()) ? d.toLocaleString('fi-FI', { timeZone: 'Europe/Helsinki' }) : '—';
};

/** Parses "12,50" or "12.50" euros to cents; null when it is not a positive amount with at most two decimals. */
export const parseEuroToCents = (text: string): number | null => {
  const t = text.trim().replace(/\s|€/g, '').replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return null;
  const cents = Math.round(Number(t) * 100);
  return cents > 0 ? cents : null;
};
