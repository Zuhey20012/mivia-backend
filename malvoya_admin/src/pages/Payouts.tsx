import { useEffect, useState } from 'react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Payout = {
  id: number;
  orderId: number;
  party: 'STORE' | 'COURIER';
  amountCents: number;
  status: 'WAITING_FOR_ACCOUNT' | 'SCHEDULED' | 'PAID' | 'CANCELLED' | 'FAILED';
  releaseAt: string;
  paidAt: string | null;
  failureReason: string | null;
  stripeTransferId: string | null;
  store: { name: string } | null;
  courier: { name: string } | null;
};

const BADGE: Record<Payout['status'], string> = {
  PAID: 'badge-green', SCHEDULED: 'badge-blue', WAITING_FOR_ACCOUNT: 'badge-yellow', CANCELLED: 'badge-gray', FAILED: 'badge-red',
};

const euro = (c: number) => new Intl.NumberFormat('fi-FI', { style: 'currency', currency: 'EUR' }).format(c / 100);

/** Money owed to stores and couriers. Stores are paid after the return window; couriers right away. */
export default function Payouts() {
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [filter, setFilter] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const r = await api.get(`/admin/payouts${filter ? `?status=${filter}` : ''}`);
      setPayouts(r.data.payouts);
      setError(null);
    } catch {
      setError('Could not load payouts.');
    }
  }

  useEffect(() => { load(); }, [filter]);

  async function retry(id: number) {
    try { await api.post(`/admin/payouts/${id}/retry`); await load(); }
    catch (e: any) { alert(e.response?.data?.error ?? 'Retry failed'); }
  }

  const total = (s: Payout['status']) => payouts.filter(p => p.status === s).reduce((n, p) => n + p.amountCents, 0);

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Payouts</h1>
        <p className="text-gray-400 text-sm mt-1">Stripe Connect transfers to stores (15 days after delivery) and couriers (after each delivery)</p>
      </div>
      <div className="grid grid-cols-4 gap-4 mb-6">
        {(['PAID', 'SCHEDULED', 'WAITING_FOR_ACCOUNT', 'FAILED'] as const).map(s => (
          <div key={s} className="apple-card text-center">
            <p className="text-2xl font-semibold">{euro(total(s))}</p>
            <p className="text-xs text-gray-400 mt-1">{s.replace(/_/g, ' ').toLowerCase()}</p>
          </div>
        ))}
      </div>
      <div className="flex gap-2 mb-4">
        {['', 'FAILED', 'WAITING_FOR_ACCOUNT', 'SCHEDULED', 'PAID', 'CANCELLED'].map(s => (
          <button key={s} className={s === filter ? 'apple-btn-primary text-xs px-3 py-1.5' : 'apple-btn-secondary text-xs px-3 py-1.5'} onClick={() => setFilter(s)}>{s || 'ALL'}</button>
        ))}
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}
      <div className="apple-card p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Order', 'To', 'Amount', 'Status', 'Release / paid', ''].map(h => <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>)}
            </tr>
          </thead>
          <tbody>
            {payouts.map(p => (
              <tr key={p.id} className="table-row">
                <td className="px-6 py-3">#{p.orderId}</td>
                <td className="px-6 py-3">{p.party === 'STORE' ? p.store?.name : p.courier?.name} <span className="text-gray-400 text-xs">({p.party.toLowerCase()})</span></td>
                <td className="px-6 py-3 font-medium">{euro(p.amountCents)}</td>
                <td className="px-6 py-3"><span className={BADGE[p.status]}>{p.status.replace(/_/g, ' ').toLowerCase()}</span>{p.failureReason && <p className="text-xs text-red-500 mt-1">{p.failureReason}</p>}</td>
                <td className="px-6 py-3 text-gray-500 text-xs">{new Date(p.paidAt ?? p.releaseAt).toLocaleString('fi-FI')}</td>
                <td className="px-6 py-3 text-right">{p.status === 'FAILED' && <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => retry(p.id)}>Retry</button>}</td>
              </tr>
            ))}
            {payouts.length === 0 && <tr><td className="px-6 py-6 text-gray-400" colSpan={6}>No payouts yet.</td></tr>}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
