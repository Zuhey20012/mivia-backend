import { useState } from 'react';
import { Search, Truck, CheckCircle, XCircle, MapPin } from 'lucide-react';
import Layout from '../components/Layout';

const mockCouriers = [
  { id: 1, name: 'Ahmed Hassan',   phone: '+254 712 345678', email: 'ahmed@example.com',   active: true,  online: true,  deliveries: 142, rating: 4.9 },
  { id: 2, name: 'Fatima Yusuf',   phone: '+254 722 987654', email: 'fatima@example.com',  active: true,  online: false, deliveries: 87,  rating: 4.7 },
  { id: 3, name: 'James Mwangi',   phone: '+254 733 111222', email: 'james@example.com',   active: false, online: false, deliveries: 0,   rating: 0   },
];

export default function Couriers() {
  const [search, setSearch] = useState('');

  const filtered = mockCouriers.filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase()) ||
    c.email.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <Layout>
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Couriers</h1>
          <p className="text-gray-400 text-sm mt-1">Manage all delivery drivers on Malvoya</p>
        </div>
        <button className="apple-btn-primary flex items-center gap-2">
          <Truck className="w-4 h-4" /> Add Courier
        </button>
      </div>

      {/* Stats bar */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        {[
          { label: 'Total Couriers', value: mockCouriers.length, color: 'text-[#1D1D1F]' },
          { label: 'Online Now',     value: mockCouriers.filter(c => c.online).length, color: 'text-green-600' },
          { label: 'Pending Approval', value: mockCouriers.filter(c => !c.active).length, color: 'text-yellow-600' },
        ].map(({ label, value, color }) => (
          <div key={label} className="apple-card text-center">
            <p className={`text-3xl font-semibold ${color}`}>{value}</p>
            <p className="text-xs text-gray-400 mt-1">{label}</p>
          </div>
        ))}
      </div>

      {/* Search */}
      <div className="apple-card mb-6">
        <div className="relative">
          <Search className="absolute left-4 top-3 w-4 h-4 text-gray-400" />
          <input
            className="apple-input pl-10"
            placeholder="Search couriers..."
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
      </div>

      {/* Table */}
      <div className="apple-card p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">Courier</th>
              <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">Contact</th>
              <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">Deliveries</th>
              <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">Rating</th>
              <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">Status</th>
              <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map(c => (
              <tr key={c.id} className="table-row">
                <td className="px-6 py-4">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-sm font-medium">
                      {c.name.charAt(0)}
                    </div>
                    <div>
                      <p className="font-medium">{c.name}</p>
                      <p className="text-gray-400 text-xs flex items-center gap-1">
                        {c.online && <><MapPin className="w-3 h-3 text-green-500" /> Online</>}
                        {!c.online && 'Offline'}
                      </p>
                    </div>
                  </div>
                </td>
                <td className="px-6 py-4">
                  <p className="text-gray-700">{c.phone}</p>
                  <p className="text-gray-400 text-xs">{c.email}</p>
                </td>
                <td className="px-6 py-4 text-gray-600">{c.deliveries}</td>
                <td className="px-6 py-4 text-gray-600">{c.rating > 0 ? `⭐ ${c.rating}` : '—'}</td>
                <td className="px-6 py-4">
                  {c.active
                    ? <span className="badge-green"><CheckCircle className="w-3 h-3 mr-1" />Active</span>
                    : <span className="badge-yellow">Pending</span>
                  }
                </td>
                <td className="px-6 py-4">
                  <div className="flex items-center gap-2">
                    {!c.active && (
                      <button className="apple-btn-primary text-xs px-3 py-1.5">Approve</button>
                    )}
                    <button className="apple-btn-danger text-xs px-3 py-1.5">
                      <XCircle className="w-3 h-3" />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
