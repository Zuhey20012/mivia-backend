import { useCallback, useEffect, useState } from 'react';
import { Gavel, RefreshCw, ExternalLink } from 'lucide-react';
import Layout from '../components/Layout';
import OrderDrawer from '../components/OrderDrawer';
import { ErrorBox } from '../components/Dialog';
import api from '../utils/api';
import { type Raw, num, str, obj, firstList, euro, fiDate, errorText, ShapeError } from '../utils/parse';

// Card disputes (chargebacks, 2.16, contract A2): Stripe's charge.dispute.created|closed webhook flags the order
// (Order.disputedAt/disputeStatus) and freezes the store's unpaid payouts for it. GET /admin/disputes lists them.
// Evidence is submitted on Stripe's dashboard; this page shows what is open and opens the order console.

type Dispute = {
  key: string;
  orderId: number | null;
  status: string;
  reason: string | null;
  amountCents: number | null;
  openedAt: string | null;
  closedAt: string | null;
  evidenceDueBy: string | null;
  stripeDisputeId: string | null;
  storeName: string | null;
  customerEmail: string | null;
};

const CLOSED = ['won', 'lost', 'closed', 'warning_closed', 'charge_refunded'];

function toDispute(r: Raw, i: number): Dispute {
  const order = obj(r.order);
  const store = obj(r.store ?? order.store);
  const customer = obj(r.customer ?? r.user ?? order.user);
  const orderId = num(r.orderId) ?? num(order.id) ?? (str(r.disputedAt) ? num(r.id) : null);
  return {
    key: str(r.stripeDisputeId) ?? str(r.disputeId) ?? `${orderId ?? 'x'}-${num(r.id) ?? i}`,
    orderId,
    status: str(r.status) ?? str(r.disputeStatus) ?? str(order.disputeStatus) ?? 'open',
    reason: str(r.reason) ?? str(r.disputeReason),
    amountCents: num(r.amountCents) ?? num(r.amount) ?? num(order.totalCents) ?? num(r.totalCents),
    openedAt: str(r.openedAt) ?? str(r.disputedAt) ?? str(order.disputedAt) ?? str(r.createdAt),
    closedAt: str(r.closedAt),
    evidenceDueBy: str(r.evidenceDueBy) ?? str(r.dueBy),
    stripeDisputeId: str(r.stripeDisputeId) ?? str(r.disputeId),
    storeName: str(store.name) ?? str(r.storeName),
    customerEmail: str(customer.email) ?? str(r.customerEmail),
  };
}

const isClosed = (d: Dispute) => !!d.closedAt || CLOSED.includes(d.status.toLowerCase());

const TH = ({ children }: { children?: React.ReactNode }) => (
  <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{children}</th>
);

export default function Disputes() {
  const [rows, setRows] = useState<Dispute[] | null>(null);
  const [error, setError] = useState('');
  const [openOrder, setOpenOrder] = useState<number | null>(null);

  const load = useCallback(() => api.get('/admin/disputes')
    .then((r) => {
      const data = obj(r.data);
      const list = firstList(data.disputes, data.orders, data.items, data.rows);
      if (!list) throw new ShapeError('The API answer has no dispute list.');
      setRows(list.map(toDispute));
      setError('');
    })
    .catch((e) => setError(errorText(e, 'Could not load the disputes.'))), []);

  useEffect(() => { load(); }, [load]);

  const sorted = [...(rows ?? [])].sort((a, b) => Number(isClosed(a)) - Number(isClosed(b))
    || new Date(b.openedAt ?? 0).getTime() - new Date(a.openedAt ?? 0).getTime());
  const openCount = sorted.filter((d) => !isClosed(d)).length;

  return (
    <Layout>
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2"><Gavel className="w-6 h-6" /> Card disputes</h1>
          <p className="text-gray-500 text-sm mt-1 max-w-3xl">
            A customer asked their bank to reverse a payment. The store's unpaid payout for that order is frozen until the dispute
            closes. Answer with evidence (delivery time, handover, chat) on Stripe's dashboard before the deadline.
          </p>
        </div>
        <button className="apple-btn-secondary text-xs px-3 py-1.5 shrink-0" onClick={() => load()}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>

      {error && <div className="mb-4"><ErrorBox>{error}{rows !== null && ' Showing the last loaded list.'}</ErrorBox></div>}

      <h2 className="font-semibold mb-3">{rows ? `${openCount} open · ${sorted.length - openCount} closed` : 'Disputes'}</h2>
      <div className="apple-card p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100"><TH>Opened</TH><TH>Order</TH><TH>Store</TH><TH>Customer</TH><TH>Amount</TH><TH>Reason</TH><TH>Status</TH><TH>Evidence due</TH><TH /></tr>
          </thead>
          <tbody>
            {rows === null && !error && <tr><td colSpan={9} className="px-6 py-6 text-gray-400">Loading…</td></tr>}
            {rows === null && error && <tr><td colSpan={9} className="px-6 py-6 text-gray-400">—</td></tr>}
            {rows && sorted.length === 0 && <tr><td colSpan={9} className="px-6 py-6 text-gray-400">No card disputes. Good.</td></tr>}
            {sorted.map((d) => (
              <tr key={d.key} className={`table-row align-top ${isClosed(d) ? 'opacity-60' : ''}`}>
                <td className="px-6 py-3 whitespace-nowrap">{fiDate(d.openedAt)}</td>
                <td className="px-6 py-3">{d.orderId !== null ? <button className="text-blue-600 font-mono" onClick={() => setOpenOrder(d.orderId)}>#{d.orderId}</button> : '—'}</td>
                <td className="px-6 py-3">{d.storeName ?? '—'}</td>
                <td className="px-6 py-3 text-xs">{d.customerEmail ?? '—'}</td>
                <td className="px-6 py-3 font-medium whitespace-nowrap">{euro(d.amountCents)}</td>
                <td className="px-6 py-3">{d.reason?.replace(/_/g, ' ') ?? '—'}</td>
                <td className="px-6 py-3">
                  <span className={d.status === 'won' ? 'badge-green' : d.status === 'lost' ? 'badge-red' : isClosed(d) ? 'badge-gray' : 'badge-orange'}>{d.status.replace(/_/g, ' ')}</span>
                  {d.closedAt && <p className="text-xs text-gray-400 mt-1">closed {fiDate(d.closedAt)}</p>}
                </td>
                <td className="px-6 py-3 whitespace-nowrap">{d.evidenceDueBy ? fiDate(d.evidenceDueBy) : '—'}</td>
                <td className="px-6 py-3 text-right whitespace-nowrap">
                  {d.stripeDisputeId && (
                    <a className="text-blue-600 text-xs inline-flex items-center gap-1" href={`https://dashboard.stripe.com/disputes/${encodeURIComponent(d.stripeDisputeId)}`}
                      target="_blank" rel="noreferrer noopener">Stripe <ExternalLink className="w-3 h-3" /></a>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {openOrder !== null && <OrderDrawer orderId={openOrder} onClose={() => setOpenOrder(null)} />}
    </Layout>
  );
}
