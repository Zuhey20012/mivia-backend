import { DollarSign, Percent, Bell } from 'lucide-react';
import Layout from '../components/Layout';

export default function Settings() {
  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
        <p className="text-gray-400 text-sm mt-1">Configure platform-wide settings for Malvoya</p>
      </div>

      <div className="grid grid-cols-1 gap-6 max-w-2xl">
        {/* Commission Settings */}
        <div className="apple-card">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 bg-green-50 rounded-xl flex items-center justify-center">
              <Percent className="w-5 h-5 text-green-500" />
            </div>
            <div>
              <h2 className="font-semibold">Commission Rate</h2>
              <p className="text-xs text-gray-400">Malvoya's cut from each vendor sale</p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <input type="number" defaultValue={10} min={0} max={100} className="apple-input w-28" />
            <span className="text-gray-400 text-sm">% of each order subtotal</span>
          </div>
          <button className="apple-btn-primary mt-4">Save Commission Rate</button>
        </div>

        {/* Delivery Fee */}
        <div className="apple-card">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 bg-blue-50 rounded-xl flex items-center justify-center">
              <DollarSign className="w-5 h-5 text-blue-500" />
            </div>
            <div>
              <h2 className="font-semibold">Delivery Fee</h2>
              <p className="text-xs text-gray-400">Flat delivery fee charged to customers</p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-gray-400 text-sm">$</span>
            <input type="number" step="0.01" defaultValue={2.99} min={0} className="apple-input w-28" />
            <span className="text-gray-400 text-sm">per order</span>
          </div>
          <button className="apple-btn-primary mt-4">Save Delivery Fee</button>
        </div>

        {/* Admin Info */}
        <div className="apple-card">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 bg-purple-50 rounded-xl flex items-center justify-center">
              <Bell className="w-5 h-5 text-purple-500" />
            </div>
            <div>
              <h2 className="font-semibold">Platform Info</h2>
              <p className="text-xs text-gray-400">Current environment variables</p>
            </div>
          </div>
          <div className="flex flex-col gap-3 text-sm">
            {[
              { label: 'App Name',        value: 'Malvoya'         },
              { label: 'Backend',         value: 'localhost:4000'  },
              { label: 'Stripe',          value: 'sk_test_51To...  (connected)' },
              { label: 'Cloudinary',      value: 'dsoowear6 (connected)'       },
              { label: 'Environment',     value: 'Development'     },
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
