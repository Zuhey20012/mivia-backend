import { useEffect, useState } from 'react';
import {
  TrendingUp, ShoppingBag, Store, Truck,
  Users, Clock, CheckCircle, XCircle, RefreshCw
} from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

interface Stats {
  customers: number; vendors: number; couriers: number;
  totalOrders: number; activeOrders: number;
  pendingApprovals: number; revenueCents: number; waitlist?: number;
}

function fmt(cents: number) {
  return new Intl.NumberFormat('fi-FI', { style: 'currency', currency: 'EUR' }).format(cents / 100);
}

type Integration = { configured: boolean; mode?: 'live' | 'test' | 'off' };
const LABELS: Record<string, string> = {
  payments: 'Payments (Stripe)', paymentWebhook: 'Payment confirmations', email: 'Email',
  supportInbox: 'Support inbox', sms: 'SMS codes', pushNotifications: 'Push notifications',
  photosAndVideos: 'Photos and videos (Cloudinary)', googleSignIn: 'Google sign-in',
};

export default function Overview() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [integrations, setIntegrations] = useState<Record<string, Integration> | null>(null);
  const [ready, setReady] = useState<boolean | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const [res, sys] = await Promise.all([api.get('/admin/stats'), api.get('/admin/system')]);
      setStats(res.data.stats);
      setIntegrations(sys.data.integrations);
      setReady(sys.data.readyForOrders);
      setError('');
    } catch {
      setError('Failed to load stats. Make sure backend is running.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const cards = stats ? [
    { label: 'Total Revenue',     value: fmt(stats.revenueCents), sub: 'Paid orders', icon: TrendingUp, color: 'text-green-500',  bg: 'bg-green-50'  },
    { label: 'Active Orders',     value: String(stats.activeOrders), sub: 'In progress right now', icon: ShoppingBag, color: 'text-blue-500',   bg: 'bg-blue-50'   },
    { label: 'Stores',            value: String(stats.vendors), sub: 'Live and in review', icon: Store, color: 'text-purple-500', bg: 'bg-purple-50' },
    { label: 'Couriers',          value: String(stats.couriers), sub: 'Signed up', icon: Truck, color: 'text-orange-500', bg: 'bg-orange-50' },
    { label: 'Total Customers',   value: String(stats.customers), sub: 'Registered users', icon: Users, color: 'text-pink-500',   bg: 'bg-pink-50'   },
    { label: 'Pending Approvals', value: String(stats.pendingApprovals), sub: 'Need your review', icon: Clock, color: 'text-yellow-500', bg: 'bg-yellow-50' },
  ] : [];

  return (
    <Layout>
      <div className="flex justify-between items-end mb-8">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-900">Malvoya Command Center</h1>
          <p className="text-slate-500 mt-1">Real-time overview of your marketplace ecosystem.</p>
        </div>
        <button onClick={load} style={{ display:'flex',alignItems:'center',gap:'0.375rem',color:'#0071E3',fontSize:'0.875rem',fontWeight:500,background:'none',border:'none',cursor:'pointer' }}>
          <RefreshCw style={{ width:'14px',height:'14px' }} /> Refresh
        </button>
      </div>

      {error && (
        <div style={{ background:'#FFF1F0',color:'#EF4444',padding:'1rem',borderRadius:'0.75rem',marginBottom:'1.5rem',fontSize:'0.875rem' }}>
          ⚠️ {error}
        </div>
      )}

      {/* Stats Grid */}
      <div style={{ display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:'1rem', marginBottom:'2rem' }}>
        {loading
          ? Array(6).fill(0).map((_, i) => (
              <div key={i} className="apple-card" style={{ height:'100px', background:'#F5F5F7', animation:'pulse 1.5s infinite' }} />
            ))
          : cards.map(({ label, value, sub, icon: Icon, color, bg }) => (
              <div key={label} className="apple-card" style={{ display:'flex', alignItems:'flex-start', gap:'1rem' }}>
                <div style={{ width:'40px',height:'40px',borderRadius:'10px',display:'flex',alignItems:'center',justifyContent:'center',flexShrink:0 }} className={bg}>
                  <Icon style={{ width:'20px',height:'20px' }} className={color} />
                </div>
                <div>
                  <p style={{ fontSize:'0.75rem',color:'#8E8E93',fontWeight:500 }}>{label}</p>
                  <p style={{ fontSize:'1.75rem',fontWeight:600,letterSpacing:'-0.02em',margin:'2px 0' }}>{value}</p>
                  <p style={{ fontSize:'0.75rem',color:'#8E8E93' }}>{sub}</p>
                </div>
              </div>
            ))
        }
      </div>

      {/* Platform status, as reported by the API itself (details on the System page) */}
      <div className="apple-card">
        <div style={{ display:'flex',justifyContent:'space-between',alignItems:'baseline',marginBottom:'1.25rem' }}>
          <h2 style={{ fontWeight:600 }}>Platform status</h2>
          <a href="#/system" style={{ color:'#0071E3',fontSize:'0.875rem',fontWeight:500 }}>
            {ready === null ? 'Details' : ready ? 'Ready for real orders · details' : 'Not ready for real orders · see why'}
          </a>
        </div>
        <div style={{ display:'flex',flexDirection:'column',gap:'0' }}>
          {[
            { label: 'API and database', ok: !error && integrations !== null, text: error ? 'Unreachable' : 'Up' },
            ...Object.entries(integrations ?? {}).map(([k, v]) => ({
              label: LABELS[k] ?? k,
              ok: v.configured && v.mode !== 'test',
              text: v.mode === 'test' ? 'Test mode' : v.configured ? 'On' : 'Not set up',
            })),
          ].map(({ label, ok, text }) => (
            <div key={label} style={{ display:'flex',alignItems:'center',justifyContent:'space-between',padding:'0.625rem 0',borderBottom:'1px solid #F5F5F7' }}>
              <span style={{ fontSize:'0.875rem',color:'#3C3C43' }}>{label}</span>
              <span style={{ display:'flex',alignItems:'center',gap:'0.375rem',fontSize:'0.75rem',fontWeight:500,color: ok ? '#34C759' : '#B45309' }}>
                {ok ? <CheckCircle style={{width:'14px',height:'14px'}} /> : <XCircle style={{width:'14px',height:'14px'}} />}
                {text}
              </span>
            </div>
          ))}
        </div>
      </div>
    </Layout>
  );
}
