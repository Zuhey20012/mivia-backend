import { useEffect, useState } from 'react';
import { Search, ShoppingBag, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

interface Order {
  id: number; status: string; totalCents: number; paymentStatus: string;
  deliveryAddress: string | null; createdAt: string;
  user: { name: string; email: string };
  store: { name: string };
  items: { quantity: number; product: { name: string } }[];
}

const statusBadge: Record<string,string> = {
  PENDING:'badge-yellow', CONFIRMED:'badge-blue', PROCESSING:'badge-blue',
  SHIPPED:'badge-blue', DELIVERED:'badge-green', CANCELLED:'badge-red', REFUNDED:'badge-gray',
};

export default function Orders() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');

  const load = async () => {
    setLoading(true);
    try { const r = await api.get('/admin/orders'); setOrders(r.data.orders); }
    catch { /* silent */ }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const filtered = orders.filter(o => {
    const matchSearch = o.user.name.toLowerCase().includes(search.toLowerCase()) ||
                        o.store.name.toLowerCase().includes(search.toLowerCase());
    const matchStatus = statusFilter === 'ALL' || o.status === statusFilter;
    return matchSearch && matchStatus;
  });

  return (
    <Layout>
      <div style={{ marginBottom:'2rem', display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div>
          <h1 style={{ fontSize:'1.5rem', fontWeight:600, letterSpacing:'-0.02em' }}>Orders</h1>
          <p style={{ color:'#8E8E93', fontSize:'0.875rem', marginTop:'0.25rem' }}>
            {orders.length} total order{orders.length !== 1 ? 's' : ''}
          </p>
        </div>
        <button onClick={load} style={{ display:'flex',alignItems:'center',gap:'0.375rem',color:'#0071E3',fontSize:'0.875rem',fontWeight:500,background:'none',border:'none',cursor:'pointer' }}>
          <RefreshCw style={{ width:'14px',height:'14px' }} /> Refresh
        </button>
      </div>

      <div className="apple-card" style={{ marginBottom:'1.5rem', display:'flex', gap:'1rem', flexWrap:'wrap' }}>
        <div style={{ position:'relative', flex:1, minWidth:'200px' }}>
          <Search style={{ position:'absolute',left:'1rem',top:'50%',transform:'translateY(-50%)',width:'16px',height:'16px',color:'#8E8E93' }} />
          <input className="apple-input" style={{ paddingLeft:'2.75rem' }} placeholder="Search by customer or vendor..." value={search} onChange={e => setSearch(e.target.value)} />
        </div>
        <select className="apple-input" style={{ width:'160px' }} value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
          <option value="ALL">All Statuses</option>
          {Object.keys(statusBadge).map(s => <option key={s} value={s}>{s}</option>)}
        </select>
      </div>

      <div className="apple-card" style={{ padding:0,overflow:'hidden' }}>
        {loading ? (
          <div style={{ display:'flex',alignItems:'center',justifyContent:'center',padding:'4rem',color:'#8E8E93',gap:'0.5rem' }}>
            <RefreshCw style={{ width:'16px',height:'16px' }} /> Loading orders...
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ display:'flex',flexDirection:'column',alignItems:'center',padding:'4rem',color:'#C7C7CC' }}>
            <ShoppingBag style={{ width:'40px',height:'40px',marginBottom:'0.75rem' }} />
            <p style={{ fontSize:'0.875rem' }}>{search || statusFilter !== 'ALL' ? 'No orders match your filter' : 'No orders yet. They will appear here when customers start buying.'}</p>
          </div>
        ) : (
          <table style={{ width:'100%',fontSize:'0.875rem',borderCollapse:'collapse' }}>
            <thead>
              <tr style={{ borderBottom:'1px solid #F5F5F7' }}>
                {['Order #','Customer','Vendor','Items','Total','Payment','Status','Date'].map(h => (
                  <th key={h} style={{ textAlign:'left',padding:'1rem 1.5rem',fontSize:'0.6875rem',fontWeight:500,color:'#8E8E93',textTransform:'uppercase',letterSpacing:'0.05em' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map(o => (
                <tr key={o.id} className="table-row">
                  <td style={{ padding:'1rem 1.5rem',fontFamily:'monospace',fontWeight:500,color:'#8E8E93' }}>#{o.id}</td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <p style={{ fontWeight:500 }}>{o.user.name}</p>
                    <p style={{ color:'#8E8E93',fontSize:'0.75rem' }}>{o.user.email}</p>
                  </td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{o.store.name}</td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{o.items.reduce((s,i)=>s+i.quantity,0)}</td>
                  <td style={{ padding:'1rem 1.5rem',fontWeight:600 }}>${(o.totalCents/100).toFixed(2)}</td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <span className={o.paymentStatus === 'SUCCEEDED' ? 'badge-green' : o.paymentStatus === 'FAILED' ? 'badge-red' : 'badge-yellow'}>
                      {o.paymentStatus}
                    </span>
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <span className={statusBadge[o.status] || 'badge-gray'}>{o.status}</span>
                  </td>
                  <td style={{ padding:'1rem 1.5rem',color:'#8E8E93',fontSize:'0.75rem' }}>
                    {new Date(o.createdAt).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}
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
