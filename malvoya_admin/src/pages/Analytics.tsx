import { useEffect, useState } from 'react';
import { RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import DailyChart from '../components/DailyChart';
import api from '../utils/api';

type Daily = { date: string; ordersPaid: number; gmvCents: number; delivered: number; cancelled: number; netRevenueCents: number; newCustomers: number };
type Totals = {
  ordersPaid: number; gmvCents: number; delivered: number; cancelled: number; cancelledByReason: Record<string, number>;
  storeAcceptance: { rate: number | null; accepted: number; declined: number; timedOut: number; medianSecondsToAccept: number | null };
  onTimeDelivery: { rate: number | null; onTime: number; measured: number };
  medianDeliveryMinutes: number | null;
  returns: { orderRate: number | null; itemRate: number | null; ordersWithReturn: number; deliveredOrders: number; returnedItems: number; deliveredItems: number };
  refunds: { refundedCents: number; refundedOrders: number; cancellationsCents: number; returnsCents: number };
  revenue: { commissionCents: number; serviceFeeCents: number; smallOrderFeeCents: number; deliveryMarginCents: number; discountCents: number; netPlatformRevenueCents: number };
  customers: { newCustomers: number; signups: number; repeatWithin30Days: { cohort: number; repeaters: number; rate: number | null } };
  waitlist: number;
};
type Data = { range: { from: string; to: string; days: number }; totals: Totals; daily: Daily[] };

const euro = (c: number) => new Intl.NumberFormat('fi-FI', { style: 'currency', currency: 'EUR', maximumFractionDigits: Math.abs(c) >= 100_000 || c === 0 ? 0 : 2 }).format(c / 100);
const pct = (r: number | null) => (r === null ? '—' : `${(r * 100).toLocaleString('fi-FI', { maximumFractionDigits: 1 })} %`);
const count = (n: number) => n.toLocaleString('fi-FI');
const duration = (s: number | null) => (s === null ? '—' : s < 120 ? `${s} s` : `${Math.round(s / 60)} min`);

const REASONS: Record<string, string> = {
  store_timeout: 'Store did not answer in time', store_declined: 'Store declined', no_courier: 'No courier available',
  customer: 'Cancelled by the customer', pickup_not_collected: 'Pickup not collected', store_not_ready: 'Pickup never made ready',
  admin: 'Cancelled by Malvoya', other: 'Other',
};

// Finnish calendar date (the API counts days in Europe/Helsinki)
const helsinkiDate = (d: Date) => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Helsinki' }).format(d);
const daysAgo = (n: number) => helsinkiDate(new Date(Date.now() - n * 86_400_000));

function Tile({ label, value, sub, help }: { label: string; value: string; sub?: string; help: string }) {
  return (
    <div className="apple-card" style={{ display: 'flex', flexDirection: 'column', gap: '0.25rem' }}>
      <p style={{ fontSize: '0.75rem', color: '#8E8E93', fontWeight: 500 }}>{label}</p>
      <p style={{ fontSize: '1.625rem', fontWeight: 600, letterSpacing: '-0.02em' }}>{value}</p>
      {sub && <p style={{ fontSize: '0.75rem', color: '#3C3C43' }}>{sub}</p>}
      <p style={{ fontSize: '0.6875rem', color: '#8E8E93', lineHeight: 1.45, marginTop: '0.25rem' }}>{help}</p>
    </div>
  );
}

/** Owner analytics: what happened to orders, stores, couriers and customers over a range of days. */
export default function Analytics() {
  const [from, setFrom] = useState(daysAgo(27));
  const [to, setTo] = useState(daysAgo(0));
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function load(f = from, t = to) {
    setLoading(true);
    try {
      const r = await api.get('/admin/analytics', { params: { from: f, to: t } });
      setData(r.data);
      setError(null);
    } catch (e: unknown) {
      setError((e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Could not load analytics.');
    } finally { setLoading(false); }
  }

  useEffect(() => {
    let alive = true;
    api.get('/admin/analytics', { params: { from, to } })
      .then((r) => { if (alive) setData(r.data); })
      .catch(() => { if (alive) setError('Could not load analytics.'); });
    return () => { alive = false; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const preset = (days: number) => { const f = daysAgo(days - 1), t = daysAgo(0); setFrom(f); setTo(t); load(f, t); };
  const t = data?.totals;
  const series = (k: keyof Daily) => (data?.daily ?? []).map((d) => ({ date: d.date, value: d[k] as number }));
  const reasons = t ? Object.entries(t.cancelledByReason).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]) : [];
  const maxReason = Math.max(1, ...reasons.map(([, n]) => n));

  return (
    <Layout>
      <div style={{ marginBottom: '1.5rem', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: '1rem', flexWrap: 'wrap' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 600, letterSpacing: '-0.02em' }}>Analytics</h1>
          <p style={{ color: '#8E8E93', fontSize: '0.875rem', marginTop: '0.25rem' }}>
            Computed from real orders; days are Finnish calendar days. Courier hours online are not tracked.
          </p>
        </div>
        {/* Filters: one row above the charts */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
          {[7, 28, 90].map((d) => (
            <button key={d} className="apple-btn-secondary" style={{ padding: '0.375rem 0.75rem', fontSize: '0.8125rem' }} onClick={() => preset(d)}>{d} days</button>
          ))}
          <input type="date" className="apple-input" style={{ width: 'auto', padding: '0.375rem 0.5rem' }} value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
          <span style={{ color: '#8E8E93' }}>–</span>
          <input type="date" className="apple-input" style={{ width: 'auto', padding: '0.375rem 0.5rem' }} value={to} min={from} onChange={(e) => setTo(e.target.value)} aria-label="To" />
          <button className="apple-btn-primary" style={{ padding: '0.375rem 0.875rem', fontSize: '0.8125rem', display: 'flex', alignItems: 'center', gap: '0.375rem' }} onClick={() => load()} disabled={loading}>
            <RefreshCw style={{ width: '13px', height: '13px' }} /> {loading ? 'Loading…' : 'Show'}
          </button>
        </div>
      </div>

      {error && <div style={{ background: '#FFF1F0', color: '#B91C1C', padding: '1rem', borderRadius: '0.75rem', marginBottom: '1.5rem', fontSize: '0.875rem' }}>{error}</div>}

      {t && data && (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '1rem', marginBottom: '1.5rem' }}>
            <Tile label="Orders paid" value={count(t.ordersPaid)} sub={`${count(t.delivered)} delivered or collected`} help="Orders whose payment arrived in the range, whatever happened to them later." />
            <Tile label="GMV (items)" value={euro(t.gmvCents)} help="Item value of the paid orders at full price, before refunds. Fees, delivery and tips are not included." />
            <Tile label="Net platform revenue" value={euro(t.revenue.netPlatformRevenueCents)} sub={`Commission ${euro(t.revenue.commissionCents)} · delivery margin ${euro(t.revenue.deliveryMarginCents)}`} help="What Malvoya keeps: commission + service and small-order fees + delivery fee minus courier pay, minus promo discounts. Paid orders not refunded or cancelled, as on the Overview." />
            <Tile label="Store acceptance" value={pct(t.storeAcceptance.rate)} sub={`Median ${duration(t.storeAcceptance.medianSecondsToAccept)} to accept`} help={`Accepted ÷ (accepted + declined + not answered in time): ${t.storeAcceptance.accepted} / ${t.storeAcceptance.accepted + t.storeAcceptance.declined + t.storeAcceptance.timedOut}. Time is from payment to acceptance.`} />
            <Tile label="On-time delivery" value={pct(t.onTimeDelivery.rate)} sub={`${t.onTimeDelivery.onTime} of ${t.onTimeDelivery.measured} courier deliveries`} help="Delivered by the end of the promised window: the estimate + 10 min from payment, or the end of the booked slot. Deliveries without an estimate are left out." />
            <Tile label="Median delivery time" value={t.medianDeliveryMinutes === null ? '—' : `${t.medianDeliveryMinutes} min`} help="From payment to handover, for courier deliveries ordered for right away (scheduled slots excluded). Half the deliveries were faster." />
            <Tile label="Return rate" value={pct(t.returns.orderRate)} sub={`Items: ${pct(t.returns.itemRate)} (${t.returns.returnedItems} of ${t.returns.deliveredItems})`} help="Orders delivered in the range with at least one return that was not rejected; items counts the pieces. Recent orders may still be returned (14 days)." />
            <Tile label="Refunds" value={euro(t.refunds.refundedCents)} sub={`Cancellations ${euro(t.refunds.cancellationsCents)} · returns ${euro(t.refunds.returnsCents)}`} help={`Money given back on orders paid in the range (${t.refunds.refundedOrders} orders), incl. delivery fees.`} />
            <Tile label="New customers" value={count(t.customers.newCustomers)} sub={`${count(t.customers.signups)} customer sign-ups`} help="Customers whose first paid order (not cancelled) falls in the range. Sign-ups are new customer accounts, ordering or not." />
            <Tile label="Repeat within 30 days" value={pct(t.customers.repeatWithin30Days.rate)} sub={`${t.customers.repeatWithin30Days.repeaters} of ${t.customers.repeatWithin30Days.cohort} new customers`} help="Of the new customers in the range, the share who paid for another order within 30 days of their first. Customers from the last 30 days have not had the full 30 days yet." />
            <Tile label="Cancelled" value={count(t.cancelled)} help="Paid orders cancelled (and refunded) in the range; the reasons are below. Unpaid checkouts that lapse are not counted." />
            <Tile label="Waiting list" value={count(t.waitlist)} help="People waiting to hear when Malvoya opens near them (now, not for the range)." />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(420px, 1fr))', gap: '1rem', marginBottom: '1.5rem' }}>
            <DailyChart title="Orders paid per day" kind="line" points={series('ordersPaid')} format={count} note="Hover a day for its value." />
            <DailyChart title="GMV per day (items)" kind="bar" points={series('gmvCents')} format={euro} />
            <DailyChart title="Net platform revenue per day" kind="bar" points={series('netRevenueCents')} format={euro} note="Negative days (amber) mean courier pay or discounts exceeded fees and commission." />
            <DailyChart title="Delivered or collected per day" kind="line" points={series('delivered')} format={count} />
          </div>

          <div className="apple-card">
            <h3 style={{ fontWeight: 600, fontSize: '0.9375rem', marginBottom: '0.75rem' }}>Why paid orders were cancelled</h3>
            {reasons.length === 0 ? (
              <p style={{ fontSize: '0.875rem', color: '#8E8E93' }}>No paid order was cancelled in this range.</p>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                {reasons.map(([k, n]) => (
                  <div key={k} style={{ display: 'grid', gridTemplateColumns: '220px 1fr 48px', alignItems: 'center', gap: '0.75rem', fontSize: '0.8125rem' }} title={`${REASONS[k] ?? k}: ${n}`}>
                    <span style={{ color: '#3C3C43' }}>{REASONS[k] ?? k}</span>
                    <svg viewBox="0 0 100 10" preserveAspectRatio="none" height="10" width="100%" aria-hidden="true">
                      <rect x="0" y="0" width={(n / maxReason) * 100} height="10" rx="2" fill="#0071E3" />
                    </svg>
                    <span style={{ textAlign: 'right', fontWeight: 500 }}>{n}</span>
                  </div>
                ))}
              </div>
            )}
            <p style={{ fontSize: '0.75rem', color: '#8E8E93', marginTop: '0.75rem', lineHeight: 1.45 }}>
              Every one of these was refunded in full automatically. Many "did not answer in time" means stores need to pause orders when busy; many "no courier" means more couriers are needed at those hours.
            </p>
          </div>
        </>
      )}
    </Layout>
  );
}
