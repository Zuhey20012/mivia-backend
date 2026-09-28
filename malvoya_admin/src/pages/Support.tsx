import { useEffect, useState } from 'react';
import { Mail } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Request = {
  id: number;
  email: string;
  app: string;
  topic: string;
  message: string;
  orderId: number | null;
  status: 'OPEN' | 'ANSWERED' | 'CLOSED';
  createdAt: string;
};

/** Messages from the three apps. Reply by email, then mark them answered. */
export default function Support() {
  const [requests, setRequests] = useState<Request[]>([]);
  const [status, setStatus] = useState<Request['status']>('OPEN');
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const r = await api.get(`/admin/support?status=${status}`);
      setRequests(r.data.requests);
      setError(null);
    } catch {
      setError('Could not load support requests.');
    }
  }

  useEffect(() => { load(); }, [status]);

  async function mark(id: number, next: Request['status']) {
    try { await api.patch(`/admin/support/${id}`, { status: next }); await load(); }
    catch { alert('Update failed'); }
  }

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Support</h1>
        <p className="text-gray-400 text-sm mt-1">Requests from customers, stores and couriers. Everyone was told you reply by email.</p>
      </div>
      <div className="flex gap-2 mb-4">
        {(['OPEN', 'ANSWERED', 'CLOSED'] as const).map(s => (
          <button key={s} className={s === status ? 'apple-btn-primary text-xs px-3 py-1.5' : 'apple-btn-secondary text-xs px-3 py-1.5'} onClick={() => setStatus(s)}>{s}</button>
        ))}
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}
      <div className="space-y-4">
        {requests.map(r => (
          <div key={r.id} className="apple-card">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="font-semibold">#{r.id} · {r.topic}</p>
                <p className="text-gray-400 text-xs">{r.app} app · {r.email}{r.orderId ? ` · order #${r.orderId}` : ''} · {new Date(r.createdAt).toLocaleString('fi-FI')}</p>
              </div>
              <div className="flex gap-2 shrink-0">
                <a className="apple-btn-secondary text-xs px-3 py-1.5" href={`mailto:${r.email}?subject=${encodeURIComponent(`Re: Malvoya #${r.id} ${r.topic}`)}`}><Mail className="w-3 h-3 mr-1" />Reply</a>
                {r.status !== 'ANSWERED' && <button className="apple-btn-primary text-xs px-3 py-1.5" onClick={() => mark(r.id, 'ANSWERED')}>Answered</button>}
                {r.status !== 'CLOSED' && <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => mark(r.id, 'CLOSED')}>Close</button>}
              </div>
            </div>
            <p className="text-sm mt-3 whitespace-pre-wrap">{r.message}</p>
          </div>
        ))}
        {requests.length === 0 && <p className="text-gray-400 text-sm">No {status.toLowerCase()} requests.</p>}
      </div>
    </Layout>
  );
}
