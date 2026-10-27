import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Euro, Percent, Bell } from 'lucide-react';
import { isAxiosError } from 'axios';
import Layout from '../components/Layout';
import api from '../utils/api';

// The fee part of GET /admin/system (read-only here: fees are env vars on Render, commission is set per store)
type Pricing = {
  serviceFeePercent: number; serviceFeeMinCents: number; serviceFeeMaxCents: number;
  smallOrderThresholdCents: number; smallOrderFeeCents: number; minChargeCents: number;
  deliveryFee?: { baseCents: number; baseKm: number; perKmCents: number; maxCents: number; unknownDistanceCents: number };
};

const euro = (cents: number) => `${(cents / 100).toFixed(2).replace('.', ',')} €`;

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4 py-2 border-b border-gray-50 last:border-0">
      <span className="text-gray-500">{label}</span>
      <span className="font-medium text-gray-800 text-right">{value}</span>
    </div>
  );
}

export default function Settings() {
  const [pricing, setPricing] = useState<Pricing | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get('/admin/system')
      .then((r) => setPricing(r.data.pricing ?? null))
      .catch((e) => setError((isAxiosError(e) && e.response?.data?.error) || 'Could not load the current fees.'));
  }, []);

  const fee = pricing?.deliveryFee;
  const serviceFee = !pricing || pricing.serviceFeePercent === 0
    ? 'Off'
    : `${pricing.serviceFeePercent} % of the items`
      + (pricing.serviceFeeMinCents ? `, at least ${euro(pricing.serviceFeeMinCents)}` : '')
      + (pricing.serviceFeeMaxCents ? `, at most ${euro(pricing.serviceFeeMaxCents)}` : '');
  const smallOrder = !pricing || pricing.smallOrderFeeCents === 0 || pricing.smallOrderThresholdCents === 0
    ? 'Off'
    : `${euro(pricing.smallOrderFeeCents)} when the items cost less than ${euro(pricing.smallOrderThresholdCents)}`;

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
        <p className="text-gray-400 text-sm mt-1">What customers and stores are charged right now</p>
      </div>

      <div className="grid grid-cols-1 gap-6 max-w-2xl">
        {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3">{error}</div>}

        {/* Commission: set per store */}
        <div className="apple-card">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 bg-green-50 rounded-xl flex items-center justify-center">
              <Percent className="w-5 h-5 text-green-500" />
            </div>
            <div>
              <h2 className="font-semibold">Commission</h2>
              <p className="text-xs text-gray-400">Malvoya's share of each store's item sales</p>
            </div>
          </div>
          <p className="text-sm text-gray-600">
            Every store starts at 0 %: stores keep 100 % of their item sales (paid out through Stripe 15 days after delivery,
            less refunds). When you want to charge one, set its rate on <Link to="/vendors" className="text-blue-600 hover:underline">Vendors</Link>.
            A rate applies to new orders only, is recorded in the store's commission history, and needs the seller terms
            updated on Legal at least 15 days before (they say there is no commission).
          </p>
        </div>

        {/* Customer fees: env vars on Render */}
        <div className="apple-card">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 bg-blue-50 rounded-xl flex items-center justify-center">
              <Euro className="w-5 h-5 text-blue-500" />
            </div>
            <div>
              <h2 className="font-semibold">Customer fees</h2>
              <p className="text-xs text-gray-400">In force on the API now, VAT included</p>
            </div>
          </div>
          {pricing ? (
            <div className="flex flex-col text-sm mb-4">
              {fee && <Row label="Delivery fee" value={`${euro(fee.baseCents)} for the first ${fee.baseKm} km, then ${euro(fee.perKmCents)}/km, at most ${euro(fee.maxCents)}`} />}
              {fee && <Row label="Delivery fee when the distance is unknown" value={euro(fee.unknownDistanceCents)} />}
              <Row label="Service fee" value={serviceFee} />
              <Row label="Small-order fee" value={smallOrder} />
              <Row label="Smallest card charge" value={euro(pricing.minChargeCents)} />
            </div>
          ) : !error && <p className="text-sm text-gray-400 mb-4">Loading…</p>}
          <p className="text-xs text-gray-400">
            These are changed with the <code>DELIVERY_FEE_*</code>, <code>SERVICE_FEE_*</code> and <code>SMALL_ORDER_*</code> settings
            on Render (the API restarts with the new values). Courier pay and the delivery margin are on{' '}
            <Link to="/system" className="text-blue-600 hover:underline">System</Link>.
          </p>
        </div>

        {/* Admin Info */}
        <div className="apple-card">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 bg-purple-50 rounded-xl flex items-center justify-center">
              <Bell className="w-5 h-5 text-purple-500" />
            </div>
            <div>
              <h2 className="font-semibold">Platform Info</h2>
              <p className="text-xs text-gray-400">Build-time configuration of this admin panel</p>
            </div>
          </div>
          <div className="flex flex-col gap-3 text-sm">
            {[
              { label: 'App Name',    value: 'Malvoya' },
              { label: 'API',         value: (import.meta.env.VITE_API_URL as string) || 'http://localhost:4000/api/v1' },
              { label: 'Environment', value: import.meta.env.MODE },
            ].map(({ label, value }) => (
              <div key={label} className="flex justify-between py-2 border-b border-gray-50 last:border-0">
                <span className="text-gray-500">{label}</span>
                <span className="font-medium font-mono text-xs text-gray-700">{value}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Layout>
  );
}
