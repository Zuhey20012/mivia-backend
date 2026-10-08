import { useEffect, useState } from 'react';
import { CheckCircle2, XCircle, AlertTriangle, RefreshCw, MapPin } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Integration = { configured: boolean; mode?: 'live' | 'test' | 'off' };
type Status = {
  version: string;
  region: string;
  startedAt: string;
  readyForOrders: boolean;
  blockers: string[];
  attention: string[];
  integrations: Record<string, Integration>;
  marketplace: Record<string, number>;
  ordersInFlight: { waitingForStore: number; waitingForCourier: number };
  timers: Record<string, number>;
  backgroundJobs: { name: string; lastRunAt: string | null }[];
};
type Demand = { totalWaiting: number; demand: { latitude: number; longitude: number; waiting: number; areas: string[] }[] };

const LABELS: Record<string, string> = {
  payments: 'Card payments (Stripe)',
  paymentWebhook: 'Payment confirmations (Stripe webhook)',
  email: 'Email (receipts, codes)',
  supportInbox: 'Support inbox',
  sms: 'SMS sign-in codes',
  pushNotifications: 'Push notifications',
  photosAndVideos: 'Photos and videos (Cloudinary)',
  googleSignIn: 'Google sign-in',
};
const MARKET: Record<string, string> = {
  liveStores: 'Live stores', storesOpenNow: 'Open right now', pendingStores: 'Stores waiting for approval',
  approvedCouriers: 'Approved couriers', onlineCouriers: 'Couriers online now', pendingCouriers: 'Couriers waiting for approval',
  waitlist: 'Customers waiting for a store nearby',
};
const TIMERS: Record<string, string> = {
  checkoutHold: 'Unpaid checkout releases its stock after',
  storeReminder: 'Store is reminded of a new order after',
  storeAccept: 'Unanswered order is refunded after',
  courierReoffer: 'Unclaimed job is offered again every',
  courierDelayNotice: 'Customer is told about a courier delay after',
  courierSearch: 'Order without a courier is refunded after',
};

function ago(iso: string | null) {
  if (!iso) return 'never';
  const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return `${s} s ago`;
  if (s < 5400) return `${Math.round(s / 60)} min ago`;
  return `${Math.round(s / 3600)} h ago`;
}

/** Can Malvoya take a real order right now, and does anything need a human? */
export default function System() {
  const [status, setStatus] = useState<Status | null>(null);
  const [demand, setDemand] = useState<Demand | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const [s, d] = await Promise.all([api.get('/admin/system'), api.get('/admin/launch-demand')]);
      setStatus(s.data);
      setDemand(d.data);
      setError(null);
    } catch {
      setError('Could not reach the API.');
    }
  }
  useEffect(() => { load(); const t = setInterval(load, 30_000); return () => clearInterval(t); }, []);

  return (
    <Layout>
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">System</h1>
          <p className="text-gray-400 text-sm mt-1">Live from the API{status ? ` · v${status.version} · ${status.region} · running since ${new Date(status.startedAt).toLocaleString('fi-FI')}` : ''}</p>
        </div>
        <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={load}><RefreshCw className="w-3 h-3 mr-1" />Refresh</button>
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}
      {!status && !error && <p className="text-gray-400 text-sm">Loading…</p>}
      {status && (
        <div className="space-y-6">
          <div className={`apple-card ${status.readyForOrders ? 'border-green-200' : 'border-amber-200'}`}>
            <div className="flex items-center gap-3">
              {status.readyForOrders
                ? <CheckCircle2 className="w-6 h-6 text-green-600" />
                : <AlertTriangle className="w-6 h-6 text-amber-500" />}
              <p className="font-semibold text-lg">{status.readyForOrders ? 'Ready to take real orders' : 'Not ready for real orders yet'}</p>
            </div>
            {status.blockers.length > 0 && (
              <ul className="mt-3 space-y-1 text-sm list-disc pl-6">
                {status.blockers.map(b => <li key={b}>{b}</li>)}
              </ul>
            )}
          </div>

          {status.attention.length > 0 && (
            <div className="apple-card">
              <p className="font-semibold mb-2">Needs your attention</p>
              <ul className="space-y-1 text-sm list-disc pl-6">{status.attention.map(a => <li key={a}>{a}</li>)}</ul>
            </div>
          )}

          <div className="grid md:grid-cols-2 gap-6">
            <div className="apple-card">
              <p className="font-semibold mb-3">Connections</p>
              <div className="space-y-2">
                {Object.entries(status.integrations).map(([k, v]) => (
                  <div key={k} className="flex items-center justify-between text-sm">
                    <span>{LABELS[k] ?? k}</span>
                    <span className="flex items-center gap-1">
                      {v.configured ? <CheckCircle2 className="w-4 h-4 text-green-600" /> : <XCircle className="w-4 h-4 text-gray-300" />}
                      {v.mode ? <span className={v.mode === 'live' ? 'text-green-600 font-medium' : 'text-amber-600 font-medium'}>{v.mode}</span> : (v.configured ? 'on' : 'off')}
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <div className="apple-card">
              <p className="font-semibold mb-3">Marketplace</p>
              <div className="space-y-2">
                {Object.entries(status.marketplace).map(([k, v]) => (
                  <div key={k} className="flex items-center justify-between text-sm"><span>{MARKET[k] ?? k}</span><span className="font-semibold">{v}</span></div>
                ))}
                <div className="flex items-center justify-between text-sm"><span>Paid orders waiting for a store</span><span className="font-semibold">{status.ordersInFlight.waitingForStore}</span></div>
                <div className="flex items-center justify-between text-sm"><span>Accepted orders waiting for a courier</span><span className="font-semibold">{status.ordersInFlight.waitingForCourier}</span></div>
              </div>
            </div>
            <div className="apple-card">
              <p className="font-semibold mb-1">Safety timers</p>
              <p className="text-gray-400 text-xs mb-3">Nobody waits forever: these run every minute and refund automatically.</p>
              <div className="space-y-2">
                {Object.entries(status.timers).map(([k, v]) => (
                  <div key={k} className="flex items-center justify-between text-sm"><span>{TIMERS[k] ?? k}</span><span className="font-semibold">{v} min</span></div>
                ))}
              </div>
            </div>
            <div className="apple-card">
              <p className="font-semibold mb-3">Background jobs</p>
              <div className="space-y-2">
                {status.backgroundJobs.map(j => (
                  <div key={j.name} className="flex items-center justify-between text-sm"><span>{j.name}</span><span className="text-gray-500">{ago(j.lastRunAt)}</span></div>
                ))}
                {status.backgroundJobs.length === 0 && <p className="text-gray-400 text-sm">No job has run yet.</p>}
              </div>
            </div>
          </div>

          <div className="apple-card">
            <p className="font-semibold mb-1">Where customers are waiting</p>
            <p className="text-gray-400 text-xs mb-3">People who tapped "Notify me" because no store delivers to them yet. Recruit stores and couriers here first.</p>
            {demand && demand.demand.length > 0 ? (
              <div className="space-y-2">
                {demand.demand.slice(0, 20).map(d => (
                  <div key={`${d.latitude},${d.longitude}`} className="flex items-center justify-between text-sm">
                    <span className="flex items-center gap-2"><MapPin className="w-4 h-4 text-gray-400" />{d.areas.length ? d.areas.join(' · ') : `${d.latitude}, ${d.longitude}`}</span>
                    <span className="font-semibold">{d.waiting}</span>
                  </div>
                ))}
              </div>
            ) : <p className="text-gray-400 text-sm">Nobody is on the waiting list yet.</p>}
          </div>
        </div>
      )}
    </Layout>
  );
}
