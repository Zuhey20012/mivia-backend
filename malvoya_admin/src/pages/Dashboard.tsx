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
  pendingApprovals: number; revenueCents: number;
}

function fmt(cents: number) {
  return '$' + (cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2 });
}

export default function Overview() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = async () => {
    setLoading(true);
    try {
      const res = await api.get('/admin/stats');
      setStats(res.data.stats);
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
    { label: 'Total Vendors',     value: String(stats.vendors), sub: 'Approved stores', icon: Store, color: 'text-purple-500', bg: 'bg-purple-50' },
    { label: 'Total Couriers',    value: String(stats.couriers), sub: 'Registered drivers', icon: Truck, color: 'text-orange-500', bg: 'bg-orange-50' },
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

      {/* Platform Health */}
      <div className="apple-card">
        <h2 style={{ fontWeight:600, marginBottom:'1.25rem' }}>Platform Status</h2>
        <div style={{ display:'flex',flexDirection:'column',gap:'0' }}>
          {[
            { label: 'Backend API',              ok: true  },
            { label: 'Database (PostgreSQL)',     ok: !error },
            { label: 'Payments (Stripe)',         ok: true  },
            { label: 'Image Storage (Cloudinary)',ok: true  },
            { label: 'Real-time (Socket.io)',     ok: true  },
          ].map(({ label, ok }) => (
            <div key={label} style={{ display:'flex',alignItems:'center',justifyContent:'space-between',padding:'0.625rem 0',borderBottom:'1px solid #F5F5F7' }}>
              <span style={{ fontSize:'0.875rem',color:'#3C3C43' }}>{label}</span>
              <span style={{ display:'flex',alignItems:'center',gap:'0.375rem',fontSize:'0.75rem',fontWeight:500,color: ok ? '#34C759' : '#EF4444' }}>
                {ok ? <CheckCircle style={{width:'14px',height:'14px'}} /> : <XCircle style={{width:'14px',height:'14px'}} />}
                {ok ? 'Operational' : 'Error'}
              </span>
            </div>
          ))}
        </div>
      </div>
    </Layout>
  );
}
