import { num, obj } from './parse';

// Pricing decided by the owner for 2.16 (contract F), read from GET /admin/system. Both values come from env vars on
// Render (FREE_DELIVERY_THRESHOLD_CENTS, DEFAULT_COMMISSION_RATE); null = the API does not report them (older version).

/** Item subtotal from which delivery is free; 0 = free delivery is off. */
export function readFreeDeliveryThreshold(system: unknown): number | null {
  const s = obj(system);
  const p = obj(s.pricing);
  const fee = obj(p.deliveryFee);
  return num(p.freeDeliveryThresholdCents) ?? num(fee.freeDeliveryThresholdCents) ?? num(fee.freeThresholdCents)
    ?? num(obj(p.freeDelivery).thresholdCents) ?? num(s.freeDeliveryThresholdCents);
}

/** Commission rate (0–0.5) a new store gets when it is created. */
export function readDefaultCommission(system: unknown): number | null {
  const s = obj(system);
  const p = obj(s.pricing);
  return num(p.defaultCommissionRate) ?? num(obj(p.commission).defaultRate) ?? num(obj(s.commission).defaultRate)
    ?? num(s.defaultCommissionRate);
}

export const percent = (rate: number) => `${Math.round(rate * 1000) / 10} %`;
