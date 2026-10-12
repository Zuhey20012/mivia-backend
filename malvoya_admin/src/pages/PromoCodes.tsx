import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import Layout from '../components/Layout';
import api from '../utils/api';

type PromoCode = {
  id: number;
  code: string;
  description: string;
  kind: 'PERCENT' | 'AMOUNT';
  value: number;
  maxDiscountCents: number | null;
  minSubtotalCents: number;
  firstOrderOnly: boolean;
  maxRedemptions: number | null;
  perUserLimit: number;
  startsAt: string | null;
  endsAt: string | null;
  active: boolean;
  createdAt: string;
  redemptionCount: number;
  discountGivenCents: number;
};

const euro = (c: number) => new Intl.NumberFormat('fi-FI', { style: 'currency', currency: 'EUR' }).format(c / 100);
const day = (iso: string) => new Date(iso).toLocaleDateString('fi-FI');
/** "12,50" or "12.50" euros → 1250 cents; empty → null */
const toCents = (v: string) => {
  const n = Number(v.replace(',', '.').trim());
  return v.trim() === '' || !Number.isFinite(n) ? null : Math.round(n * 100);
};

/** The API's user-readable error, if there is one */
const apiError = (err: unknown, fallback: string) =>
  (err as { response?: { data?: { error?: string } } })?.response?.data?.error ?? fallback;

const EMPTY = {
  code: '', description: '', kind: 'PERCENT' as 'PERCENT' | 'AMOUNT', value: '',
  maxDiscount: '', minSubtotal: '', firstOrderOnly: false, maxRedemptions: '', perUserLimit: '1', startsAt: '', endsAt: '',
};

function status(p: PromoCode) {
  const now = Date.now();
  if (!p.active) return { text: 'off', badge: 'badge-gray' };
  if (p.endsAt && new Date(p.endsAt).getTime() <= now) return { text: 'ended', badge: 'badge-gray' };
  if (p.startsAt && new Date(p.startsAt).getTime() > now) return { text: 'scheduled', badge: 'badge-blue' };
  if (p.maxRedemptions !== null && p.redemptionCount >= p.maxRedemptions) return { text: 'used up', badge: 'badge-yellow' };
  return { text: 'live', badge: 'badge-green' };
}

/** Platform-funded discounts: Malvoya pays the discount, store and courier pay are unchanged. */
export default function PromoCodes() {
  const [codes, setCodes] = useState<PromoCode[]>([]);
  const [form, setForm] = useState(EMPTY);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function load() {
    try {
      const r = await api.get('/admin/promo-codes');
      setCodes(r.data.promoCodes);
      setError(null);
    } catch {
      setError('Could not load promo codes.');
    }
  }

  useEffect(() => { load(); }, []);

  async function create(e: FormEvent) {
    e.preventDefault();
    const value = form.kind === 'PERCENT' ? Number(form.value) : toCents(form.value);
    if (!value || value < 1) { setError(form.kind === 'PERCENT' ? 'Enter a percentage (1–100).' : 'Enter the discount in euros.'); return; }
    setSaving(true);
    try {
      await api.post('/admin/promo-codes', {
        code: form.code.trim(),
        description: form.description.trim(),
        kind: form.kind,
        value,
        maxDiscountCents: form.kind === 'PERCENT' ? toCents(form.maxDiscount) : null,
        minSubtotalCents: toCents(form.minSubtotal) ?? 0,
        firstOrderOnly: form.firstOrderOnly,
        maxRedemptions: form.maxRedemptions.trim() ? Number(form.maxRedemptions) : null,
        perUserLimit: Number(form.perUserLimit) || 1,
        startsAt: form.startsAt ? new Date(form.startsAt).toISOString() : null,
        endsAt: form.endsAt ? new Date(form.endsAt).toISOString() : null,
      });
      setForm(EMPTY);
      await load();
    } catch (err) {
      setError(apiError(err, 'Could not create the code.'));
    } finally {
      setSaving(false);
    }
  }

  async function update(p: PromoCode, data: { active?: boolean; endsAt?: string | null }) {
    try { await api.patch(`/admin/promo-codes/${p.id}`, data); await load(); }
    catch (err) { alert(apiError(err, 'Could not change the code')); }
  }

  function changeEnd(p: PromoCode) {
    const current = p.endsAt ? p.endsAt.slice(0, 10) : '';
    const v = window.prompt('New end date (YYYY-MM-DD, empty = no end date)', current);
    if (v === null) return;
    if (v.trim() && Number.isNaN(new Date(`${v.trim()}T23:59:59`).getTime())) { alert('Use the format YYYY-MM-DD'); return; }
    update(p, { endsAt: v.trim() ? new Date(`${v.trim()}T23:59:59`).toISOString() : null });
  }

  const set = (k: keyof typeof EMPTY) => (e: { target: { value: string } }) => setForm({ ...form, [k]: e.target.value });
  const label = 'block text-xs font-medium text-gray-500 mb-1';

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Promo codes</h1>
        <p className="text-gray-400 text-sm mt-1">Discounts paid by Malvoya. Stores and couriers are paid in full. A code counts as used once the order is paid, and is given back if the order is cancelled before delivery.</p>
      </div>

      <form onSubmit={create} className="apple-card mb-6">
        <h2 className="font-semibold mb-4">New code</h2>
        <div className="grid grid-cols-4 gap-4">
          <div>
            <label className={label}>Code</label>
            <input className="apple-input" required minLength={3} maxLength={32} pattern="[A-Za-z0-9_\-]+" placeholder="WELCOME5" value={form.code} onChange={set('code')} />
          </div>
          <div className="col-span-3">
            <label className={label}>Description (shown to customers)</label>
            <input className="apple-input" required minLength={3} maxLength={200} placeholder="5 € off your first order" value={form.description} onChange={set('description')} />
          </div>
          <div>
            <label className={label}>Type</label>
            <select className="apple-input" value={form.kind} onChange={set('kind')}>
              <option value="PERCENT">Percent of items</option>
              <option value="AMOUNT">Amount in euros</option>
            </select>
          </div>
          <div>
            <label className={label}>{form.kind === 'PERCENT' ? 'Percent (1–100)' : 'Discount (€)'}</label>
            <input className="apple-input" required inputMode="decimal" value={form.value} onChange={set('value')} />
          </div>
          <div>
            <label className={label}>Max discount (€, optional)</label>
            <input className="apple-input" inputMode="decimal" disabled={form.kind !== 'PERCENT'} value={form.maxDiscount} onChange={set('maxDiscount')} />
          </div>
          <div>
            <label className={label}>Minimum items total (€)</label>
            <input className="apple-input" inputMode="decimal" placeholder="0" value={form.minSubtotal} onChange={set('minSubtotal')} />
          </div>
          <div>
            <label className={label}>Total uses (empty = no limit)</label>
            <input className="apple-input" inputMode="numeric" value={form.maxRedemptions} onChange={set('maxRedemptions')} />
          </div>
          <div>
            <label className={label}>Uses per customer</label>
            <input className="apple-input" inputMode="numeric" value={form.perUserLimit} onChange={set('perUserLimit')} />
          </div>
          <div>
            <label className={label}>Starts (optional)</label>
            <input className="apple-input" type="datetime-local" value={form.startsAt} onChange={set('startsAt')} />
          </div>
          <div>
            <label className={label}>Ends (optional)</label>
            <input className="apple-input" type="datetime-local" value={form.endsAt} onChange={set('endsAt')} />
          </div>
        </div>
        <div className="flex items-center justify-between mt-4">
          <label className="flex items-center gap-2 text-sm text-gray-600">
            <input type="checkbox" checked={form.firstOrderOnly} onChange={(e) => setForm({ ...form, firstOrderOnly: e.target.checked })} />
            First order only (customers without an earlier paid order)
          </label>
          <button type="submit" className="apple-btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Create code'}</button>
        </div>
      </form>

      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}

      <div className="apple-card p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Code', 'Discount', 'Rules', 'Valid', 'Used', 'Status', ''].map(h => <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>)}
            </tr>
          </thead>
          <tbody>
            {codes.map(p => {
              const s = status(p);
              return (
                <tr key={p.id} className="table-row align-top">
                  <td className="px-6 py-3"><p className="font-medium font-mono">{p.code}</p><p className="text-xs text-gray-400">{p.description}</p></td>
                  <td className="px-6 py-3 font-medium">
                    {p.kind === 'PERCENT' ? `${p.value} %` : euro(p.value)}
                    {p.maxDiscountCents !== null && <p className="text-xs text-gray-400">max {euro(p.maxDiscountCents)}</p>}
                  </td>
                  <td className="px-6 py-3 text-xs text-gray-500">
                    {p.minSubtotalCents > 0 && <p>from {euro(p.minSubtotalCents)}</p>}
                    {p.firstOrderOnly && <p>first order only</p>}
                    <p>{p.perUserLimit}× per customer</p>
                  </td>
                  <td className="px-6 py-3 text-xs text-gray-500">
                    {p.startsAt && <p>from {day(p.startsAt)}</p>}
                    <p>{p.endsAt ? `until ${day(p.endsAt)}` : 'no end date'}</p>
                  </td>
                  <td className="px-6 py-3">
                    {p.redemptionCount}{p.maxRedemptions !== null && ` / ${p.maxRedemptions}`}
                    <p className="text-xs text-gray-400">{euro(p.discountGivenCents)} given</p>
                  </td>
                  <td className="px-6 py-3"><span className={s.badge}>{s.text}</span></td>
                  <td className="px-6 py-3 text-right whitespace-nowrap">
                    <button className="apple-btn-secondary text-xs px-3 py-1.5 mr-2" onClick={() => changeEnd(p)}>End date</button>
                    {p.active
                      ? <button className="apple-btn-danger text-xs px-3 py-1.5" onClick={() => update(p, { active: false })}>Deactivate</button>
                      : <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => update(p, { active: true })}>Activate</button>}
                  </td>
                </tr>
              );
            })}
            {codes.length === 0 && <tr><td className="px-6 py-6 text-gray-400" colSpan={7}>No promo codes yet.</td></tr>}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
