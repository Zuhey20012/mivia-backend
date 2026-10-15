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
  ordersInFlight: { waitingForStore: number; waitingForCourier: number; waitingForPickup?: number };
  pickup?: { reminderHours: number; holdHours: number };
  referrals?: Referrals;
  appLinks?: { fingerprints: number; url: string };
  timers: Record<string, number>;
  apps?: Record<string, { minBuild: number; maintenance: { active: boolean; message: string | null } }>;
  backgroundJobs: { name: string; lastRunAt: string | null }[];
  pricing?: Pricing;
};
type PayExample = {
  straightKm: number; routeKm: number | null; customerFeeCents: number; courierPayCents: number; marginCents: number;
  explanation: { en: string; fi: string };
};
type Pricing = {
  serviceFeePercent: number; serviceFeeMinCents: number; serviceFeeMaxCents: number;
  smallOrderThresholdCents: number; smallOrderFeeCents: number; minChargeCents: number;
  deliveryFee?: { baseCents: number; baseKm: number; perKmCents: number; maxCents: number; unknownDistanceCents: number };
  courierPay?: {
    mode: "formula" | "fee_share"; baseCents: number; perKmCents: number; minCents: number; roadFactor: number;
    approachFreeKm: number; approachPerKmCents: number; waitFreeMinutes: number; waitPerMinCents: number; waitMaxCents: number;
    feeShare: number; summary: { en: string; fi: string };
    waitExample: { minutes: number; cents: number };
    approachExample: { straightKm: number; routeKm: number | null; cents: number };
    examples: PayExample[];
  };
};
type Referrals = {
  enabled: boolean; discountCents: number; rewardCents: number; referrals: number; rewarded: number; discountGivenCents: number;
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

const euro = (cents: number) => `${(cents / 100).toFixed(2).replace(".", ",")} €`;

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
                {status.ordersInFlight.waitingForPickup !== undefined && (
                  <div className="flex items-center justify-between text-sm"><span>Pickup orders ready, not collected yet</span><span className="font-semibold">{status.ordersInFlight.waitingForPickup}</span></div>
                )}
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
            {status.apps && (
              <div className="apple-card">
                <p className="font-semibold mb-1">App versions and maintenance</p>
                <p className="text-gray-400 text-xs mb-3">Set MIN_BUILD_CUSTOMER / MIN_BUILD_STORE / MIN_BUILD_COURIER on Render to make older builds ask for an update, and MAINTENANCE_MESSAGE to pause all apps with a message.</p>
                <div className="space-y-2">
                  {Object.entries(status.apps).map(([app, c]) => (
                    <div key={app} className="flex items-center justify-between text-sm">
                      <span className="capitalize">{app} app</span>
                      <span className="text-gray-500">{c.minBuild > 0 ? `builds below ${c.minBuild} must update` : 'all builds allowed'}</span>
                    </div>
                  ))}
                  <div className="flex items-center justify-between text-sm">
                    <span>Maintenance</span>
                    <span className={Object.values(status.apps)[0]?.maintenance.active ? 'text-amber-600 font-medium' : 'text-gray-500'}>
                      {Object.values(status.apps)[0]?.maintenance.active ? `on: “${Object.values(status.apps)[0]?.maintenance.message}”` : 'off'}
                    </span>
                  </div>
                </div>
              </div>
            )}
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

          {(status.referrals || status.pickup) && (
            <div className="grid md:grid-cols-2 gap-6">
              {status.referrals && <ReferralCard r={status.referrals} />}
              {status.pickup && (
                <div className="apple-card">
                  <p className="font-semibold mb-1">Reserve &amp; collect</p>
                  <p className="text-gray-400 text-xs mb-3">Counted from when the store marks a pickup order ready (PICKUP_REMINDER_HOURS / PICKUP_HOLD_HOURS on Render).</p>
                  <div className="space-y-2 text-sm">
                    <div className="flex items-center justify-between"><span>Customer is reminded after</span><span className="font-semibold">{status.pickup.reminderHours} h</span></div>
                    <div className="flex items-center justify-between"><span>Not collected: cancelled and refunded after</span><span className="font-semibold">{status.pickup.holdHours} h</span></div>
                    {status.appLinks && (
                      <div className="flex items-center justify-between">
                        <span>Android app links (ANDROID_APP_SHA256)</span>
                        <span className={status.appLinks.fingerprints ? 'text-green-600 font-medium' : 'text-gray-500'}>{status.appLinks.fingerprints ? `${status.appLinks.fingerprints} certificate(s)` : 'off'}</span>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}

          {status.pricing?.courierPay && (
            <CourierPayCard pricing={status.pricing} />
          )}

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

/** Referral settings (env vars) and how often invites were used. */
function ReferralCard({ r }: { r: Referrals }) {
  const rows: [string, string][] = [
    ['New customer gets (first order)', euro(r.discountCents)],
    ['Referrer gets (one-time code)', r.rewardCents > 0 ? euro(r.rewardCents) : 'nothing'],
    ['Friends who ordered with an invite', String(r.referrals)],
    ['Rewards issued', String(r.rewarded)],
    ['Invite discounts given', euro(r.discountGivenCents)],
  ];
  return (
    <div className="apple-card">
      <p className="font-semibold mb-1">Invite a friend (referrals)</p>
      <p className="text-gray-400 text-xs mb-3">
        Set REFERRAL_DISCOUNT_CENTS (0 = off) and REFERRAL_REWARD_CENTS on Render. Both are paid by Malvoya, like promo codes.
      </p>
      <div className="space-y-2 text-sm">
        <div className="flex items-center justify-between"><span>Status</span><span className={r.enabled ? 'text-green-600 font-medium' : 'text-gray-500'}>{r.enabled ? 'on' : 'off'}</span></div>
        {rows.map(([k, v]) => (
          <div key={k} className="flex items-center justify-between"><span>{k}</span><span className="font-semibold">{v}</span></div>
        ))}
      </div>
    </div>
  );
}

/** Courier pay settings and the delivery margin (customer delivery fee − courier pay, tips excluded) on example jobs. */
function CourierPayCard({ pricing }: { pricing: Pricing }) {
  const pay = pricing.courierPay!;
  const fee = pricing.deliveryFee;
  const rows: [string, string][] = pay.mode === "formula"
    ? [
        ["Base per delivery (pickup + drop-off)", euro(pay.baseCents)],
        ["Per km, shop → customer", `${euro(pay.perKmCents)} × straight line × ${pay.roadFactor}`],
        ["Minimum (base + distance)", euro(pay.minCents)],
        ["Ride to the shop", `${euro(pay.approachPerKmCents)}/km beyond ${pay.approachFreeKm} km`],
        ["Waiting at the shop", `${euro(pay.waitPerMinCents)}/min after ${pay.waitFreeMinutes} min, max ${euro(pay.waitMaxCents)}`],
        ["Tips", "100 % to the courier"],
      ]
    : [["Share of the customer delivery fee", `${Math.round(pay.feeShare * 100)} %`], ["Tips", "100 % to the courier"]];
  return (
    <div className="apple-card">
      <p className="font-semibold mb-1">Delivery fees and courier pay</p>
      <p className="text-gray-400 text-xs mb-3">
        Courier pay is set separately from what the customer pays (COURIER_PAY_* and DELIVERY_FEE_* on Render).
        Couriers see this rule and the breakdown of every job before they accept.
      </p>
      <p className="text-sm mb-1">{pay.summary.en}</p>
      <p className="text-sm text-gray-500 mb-4">{pay.summary.fi}</p>
      <div className="grid md:grid-cols-2 gap-6">
        <div className="space-y-2">
          <p className="text-xs uppercase tracking-wide text-gray-400">Courier pay ({pay.mode === "formula" ? "formula" : "share of the fee"})</p>
          {rows.map(([k, v]) => (
            <div key={k} className="flex items-center justify-between text-sm gap-4"><span>{k}</span><span className="font-semibold text-right">{v}</span></div>
          ))}
        </div>
        {fee && (
          <div className="space-y-2">
            <p className="text-xs uppercase tracking-wide text-gray-400">Customer delivery fee</p>
            <div className="flex items-center justify-between text-sm"><span>First {fee.baseKm} km</span><span className="font-semibold">{euro(fee.baseCents)}</span></div>
            <div className="flex items-center justify-between text-sm"><span>Each further km</span><span className="font-semibold">{euro(fee.perKmCents)}</span></div>
            <div className="flex items-center justify-between text-sm"><span>Maximum</span><span className="font-semibold">{fee.maxCents > 0 ? euro(fee.maxCents) : "no cap"}</span></div>
            <div className="flex items-center justify-between text-sm"><span>Address without coordinates</span><span className="font-semibold">{euro(fee.unknownDistanceCents)}</span></div>
          </div>
        )}
      </div>
      <div className="mt-5 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-gray-400 text-xs uppercase tracking-wide">
              <th className="py-2 pr-4 font-medium">Example job</th>
              <th className="py-2 pr-4 font-medium text-right">Customer pays</th>
              <th className="py-2 pr-4 font-medium text-right">Courier gets</th>
              <th className="py-2 font-medium text-right">Malvoya keeps</th>
            </tr>
          </thead>
          <tbody>
            {pay.examples.map((e) => (
              <tr key={e.straightKm} className="border-t border-gray-100" title={e.explanation.en}>
                <td className="py-2 pr-4">{e.straightKm} km straight line{e.routeKm !== null ? ` (${e.routeKm} km route)` : ""}</td>
                <td className="py-2 pr-4 text-right">{euro(e.customerFeeCents)}</td>
                <td className="py-2 pr-4 text-right">{euro(e.courierPayCents)}</td>
                <td className={`py-2 text-right font-semibold ${e.marginCents < 0 ? "text-red-600" : "text-green-600"}`}>{euro(e.marginCents)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="text-gray-400 text-xs mt-2">
          Without tips, waiting or ride-to-shop pay. A courier kept {pay.waitExample.minutes} min at the shop gets {euro(pay.waitExample.cents)} more;
          a ride of {pay.approachExample.routeKm ?? "?"} km to the shop adds {euro(pay.approachExample.cents)}. A negative margin means Malvoya pays the difference.
        </p>
      </div>
    </div>
  );
}
