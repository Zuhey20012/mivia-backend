import { useEffect, useState } from 'react';
import { Search, Store, CheckCircle, XCircle, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

interface Vendor {
  id: number; name: string; category: string;
  email: string | null; isVerified: boolean;
  rating: number; commissionRate: number;
  owner: { name: string; email: string };
  _count: { products: number; orders: number };
  createdAt: string;
}

const categoryColors: Record<string, string> = {
  APPAREL: 'badge-blue', COSMETICS: 'badge-yellow',
  THRIFT: 'badge-gray', ECO_FRIENDLY: 'badge-green',
  ACCESSORIES: 'badge-blue', HOME_DECOR: 'badge-purple',
  HANDMADE: 'badge-orange', OTHER: 'badge-gray',
};

export default function Vendors() {
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [actionId, setActionId] = useState<number | null>(null);

  const load = async () => {
    setLoading(true);
    try { const r = await api.get('/admin/vendors'); setVendors(r.data.stores); }
    catch { /* silently fail */ }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const approve = async (id: number) => {
    setActionId(id);
    try { await api.patch(`/admin/vendors/${id}/approve`); await load(); }
    catch { alert('Failed to approve vendor.'); }
    finally { setActionId(null); }
  };

  const reject = async (id: number, name: string) => {
    if (!confirm(`Reject "${name}"? This cannot be undone.`)) return;
    setActionId(id);
    try { await api.delete(`/admin/vendors/${id}`); await load(); }
    catch { alert('Failed to reject vendor.'); }
    finally { setActionId(null); }
  };

  const filtered = vendors.filter(v =>
    v.name.toLowerCase().includes(search.toLowerCase()) ||
    (v.email || v.owner.email).toLowerCase().includes(search.toLowerCase())
  );

  return (
    <Layout>
      <div style={{ marginBottom:'2rem', display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div>
          <h1 style={{ fontSize:'1.5rem', fontWeight:600, letterSpacing:'-0.02em' }}>Vendors</h1>
          <p style={{ color:'#8E8E93', fontSize:'0.875rem', marginTop:'0.25rem' }}>
            {vendors.length} store{vendors.length !== 1 ? 's' : ''} · {vendors.filter(v=>!v.isVerified).length} pending approval
          </p>
        </div>
        <button onClick={load} style={{ display:'flex',alignItems:'center',gap:'0.375rem',color:'#0071E3',fontSize:'0.875rem',fontWeight:500,background:'none',border:'none',cursor:'pointer' }}>
          <RefreshCw style={{ width:'14px',height:'14px' }} /> Refresh
        </button>
      </div>

      {/* Search */}
      <div className="apple-card" style={{ marginBottom:'1.5rem' }}>
        <div style={{ position:'relative' }}>
          <Search style={{ position:'absolute',left:'1rem',top:'50%',transform:'translateY(-50%)',width:'16px',height:'16px',color:'#8E8E93' }} />
          <input className="apple-input" style={{ paddingLeft:'2.75rem' }} placeholder="Search vendors..." value={search} onChange={e => setSearch(e.target.value)} />
        </div>
      </div>

      {/* Table */}
      <div className="apple-card" style={{ padding:0, overflow:'hidden' }}>
        {loading ? (
          <div style={{ display:'flex',alignItems:'center',justifyContent:'center',padding:'4rem',color:'#8E8E93',gap:'0.5rem' }}>
            <RefreshCw style={{ width:'16px',height:'16px',animation:'spin 1s linear infinite' }} /> Loading vendors...
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ display:'flex',flexDirection:'column',alignItems:'center',padding:'4rem',color:'#C7C7CC' }}>
            <Store style={{ width:'40px',height:'40px',marginBottom:'0.75rem' }} />
            <p style={{ fontSize:'0.875rem' }}>{search ? 'No vendors match your search' : 'No vendors yet. Vendors will appear here when they sign up.'}</p>
          </div>
        ) : (
          <table style={{ width:'100%', fontSize:'0.875rem', borderCollapse:'collapse' }}>
            <thead>
              <tr style={{ borderBottom:'1px solid #F5F5F7' }}>
                {['Store','Owner','Category','Products','Orders','Status','Actions'].map(h => (
                  <th key={h} style={{ textAlign:'left',padding:'1rem 1.5rem',fontSize:'0.6875rem',fontWeight:500,color:'#8E8E93',textTransform:'uppercase',letterSpacing:'0.05em' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map(v => (
                <tr key={v.id} className="table-row">
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <p style={{ fontWeight:500 }}>{v.name}</p>
                    <p style={{ color:'#8E8E93',fontSize:'0.75rem' }}>{v.email || '—'}</p>
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <p style={{ color:'#3C3C43' }}>{v.owner.name}</p>
                    <p style={{ color:'#8E8E93',fontSize:'0.75rem' }}>{v.owner.email}</p>
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <span className={categoryColors[v.category] || 'badge-gray'}>{v.category.replace('_',' ')}</span>
                  </td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{v._count.products}</td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{v._count.orders}</td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    {v.isVerified
                      ? <span className="badge-green"><CheckCircle style={{width:'10px',height:'10px',marginRight:'4px'}} />Verified</span>
                      : <span className="badge-yellow">Pending</span>
                    }
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <div style={{ display:'flex',gap:'0.5rem',alignItems:'center' }}>
                      {!v.isVerified && (
                        <button className="apple-btn-primary" style={{ padding:'0.375rem 0.75rem',fontSize:'0.75rem' }}
                          onClick={() => approve(v.id)} disabled={actionId === v.id}>
                          {actionId === v.id ? '...' : 'Approve'}
                        </button>
                      )}
                      <button className="apple-btn-danger" style={{ padding:'0.375rem 0.625rem',fontSize:'0.75rem' }}
                        onClick={() => reject(v.id, v.name)} disabled={actionId === v.id}>
                        <XCircle style={{ width:'14px',height:'14px' }} />
                      </button>
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
