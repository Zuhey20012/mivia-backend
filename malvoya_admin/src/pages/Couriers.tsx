import { useEffect, useState } from 'react';
import { Search, CheckCircle, XCircle, MapPin } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Courier = {
  id: number;
  name: string;
  phone: string | null;
  email: string | null;
  isApproved: boolean;
  isActive: boolean;
  currentOrderId: number | null;
  createdAt: string;
  user: { id: number; email: string; isActive: boolean } | null;
  _count: { orders: number };
};

export default function Couriers() {
  const [couriers, setCouriers] = useState<Courier[]>([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const r = await api.get('/admin/couriers');
      setCouriers(r.data.couriers);
    } catch {
      setError('Could not load couriers.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { load(); }, []);

  async function approve(id: number) {
    // Approve only after checking ID, right to work in Finland and the signed courier agreement.
    if (!confirm('Have you verified this courier\'s identity, right to work and signed agreement?')) return;
    try { await api.patch(`/admin/couriers/${id}/approve`); await load(); }
    catch { alert('Approval failed'); }
  }

  async function suspend(id: number) {
    if (!confirm('Suspend this courier? They will stop receiving jobs immediately.')) return;
    try { await api.patch(`/admin/couriers/${id}/suspend`); await load(); }
    catch { alert('Suspend failed'); }
  }

  const q = search.toLowerCase();
  const filtered = couriers.filter(c =>
    c.name.toLowerCase().includes(q) || (c.email ?? c.user?.email ?? '').toLowerCase().includes(q)
  );

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Couriers</h1>
        <p className="text-gray-400 text-sm mt-1">Approve couriers after verifying identity and right to work</p>
      </div>

      <div className="grid grid-cols-3 gap-4 mb-6">
        {[
          { label: 'Total Couriers', value: couriers.length, color: 'text-[#1D1D1F]' },
          { label: 'Online Now', value: couriers.filter(c => c.isApproved && c.isActive).length, color: 'text-green-600' },
          { label: 'Pending Approval', value: couriers.filter(c => !c.isApproved).length, color: 'text-yellow-600' },
        ].map(({ label, value, color }) => (
          <div key={label} className="apple-card text-center">
            <p className={`text-3xl font-semibold ${color}`}>{value}</p>
            <p className="text-xs text-gray-400 mt-1">{label}</p>
          </div>
        ))}
      </div>

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

      <div className="apple-card p-0 overflow-hidden">
        {loading ? (
          <p className="p-6 text-gray-400 text-sm">Loading…</p>
        ) : error ? (
          <p className="p-6 text-red-500 text-sm">{error}</p>
        ) : filtered.length === 0 ? (
          <p className="p-6 text-gray-400 text-sm">No couriers yet.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-100">
                {['Courier', 'Contact', 'Deliveries', 'Status', 'Actions'].map(h => (
                  <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>
                ))}
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
                          {c.isApproved && c.isActive ? <><MapPin className="w-3 h-3 text-green-500" /> Online</> : 'Offline'}
                          {c.currentOrderId && <> · on order #{c.currentOrderId}</>}
                        </p>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <p className="text-gray-700">{c.phone ?? '—'}</p>
                    <p className="text-gray-400 text-xs">{c.email ?? c.user?.email ?? '—'}</p>
                  </td>
                  <td className="px-6 py-4 text-gray-600">{c._count.orders}</td>
                  <td className="px-6 py-4">
                    {c.isApproved
                      ? <span className="badge-green"><CheckCircle className="w-3 h-3 mr-1" />Approved</span>
                      : <span className="badge-yellow">Pending</span>}
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-2">
                      {!c.isApproved && (
                        <button className="apple-btn-primary text-xs px-3 py-1.5" onClick={() => approve(c.id)}>Approve</button>
                      )}
                      {c.isApproved && (
                        <button className="apple-btn-danger text-xs px-3 py-1.5" title="Suspend" onClick={() => suspend(c.id)}>
                          <XCircle className="w-3 h-3" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </Layout>
  );
}
