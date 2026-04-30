import { useEffect, useState } from 'react';
import { CheckCircle, XCircle, Store, Truck, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

interface Vendor {
  id: number; name: string; email: string | null;
  category: string; isVerified: boolean;
  owner: { name: string; email: string };
  createdAt: string;
}

export default function Approvals() {
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionId, setActionId] = useState<number|null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const r = await api.get('/admin/vendors');
      setVendors(r.data.stores.filter((v: Vendor) => !v.isVerified));
    } catch { /* silent */ }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const approve = async (id: number) => {
    setActionId(id);
    try { await api.patch(`/admin/vendors/${id}/approve`); await load(); }
    catch { alert('Failed to approve.'); }
    finally { setActionId(null); }
  };

  const reject = async (id: number, name: string) => {
    if (!confirm(`Reject and remove "${name}"?`)) return;
    setActionId(id);
    try { await api.delete(`/admin/vendors/${id}`); await load(); }
    catch { alert('Failed to reject.'); }
    finally { setActionId(null); }
  };

  return (
    <Layout>
      <div style={{ marginBottom:'2rem', display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div>
          <h1 style={{ fontSize:'1.5rem', fontWeight:600, letterSpacing:'-0.02em' }}>Pending Approvals</h1>
          <p style={{ color:'#8E8E93', fontSize:'0.875rem', marginTop:'0.25rem' }}>
            {loading ? 'Loading...' : vendors.length > 0
              ? `${vendors.length} application${vendors.length !== 1 ? 's' : ''} waiting for your review`
              : 'All caught up! No pending approvals.'
            }
          </p>
        </div>
        <button onClick={load} style={{ display:'flex',alignItems:'center',gap:'0.375rem',color:'#0071E3',fontSize:'0.875rem',fontWeight:500,background:'none',border:'none',cursor:'pointer' }}>
          <RefreshCw style={{ width:'14px',height:'14px' }} /> Refresh
        </button>
      </div>

      {loading ? (
        <div className="apple-card" style={{ display:'flex',alignItems:'center',justifyContent:'center',padding:'4rem',color:'#8E8E93',gap:'0.5rem' }}>
          <RefreshCw style={{ width:'16px',height:'16px' }} /> Loading approvals...
        </div>
      ) : vendors.length === 0 ? (
        <div className="apple-card" style={{ display:'flex',flexDirection:'column',alignItems:'center',padding:'5rem',color:'#C7C7CC' }}>
          <CheckCircle style={{ width:'56px',height:'56px',marginBottom:'1rem',color:'#34C759' }} />
          <p style={{ fontSize:'1.125rem',fontWeight:500,color:'#3C3C43' }}>All caught up!</p>
          <p style={{ fontSize:'0.875rem',marginTop:'0.375rem' }}>No pending vendor or courier applications at this time.</p>
        </div>
      ) : (
        <div style={{ display:'flex',flexDirection:'column',gap:'1rem' }}>
          {vendors.map(v => (
            <div key={v.id} className="apple-card" style={{ display:'flex',alignItems:'center',justifyContent:'space-between',gap:'1rem' }}>
              <div style={{ display:'flex',alignItems:'center',gap:'1rem' }}>
                <div style={{ width:'48px',height:'48px',background:'#FAF5FF',borderRadius:'12px',display:'flex',alignItems:'center',justifyContent:'center',flexShrink:0 }}>
                  <Store style={{ width:'22px',height:'22px',color:'#7C3AED' }} />
                </div>
                <div>
                  <p style={{ fontWeight:600,fontSize:'1rem' }}>{v.name}</p>
                  <p style={{ color:'#8E8E93',fontSize:'0.8125rem' }}>
                    By {v.owner.name} · {v.owner.email}
                  </p>
                  <p style={{ color:'#8E8E93',fontSize:'0.75rem',marginTop:'0.25rem' }}>
                    Category: {v.category.replace('_',' ')} · Applied {new Date(v.createdAt).toLocaleDateString('en-US', {month:'short',day:'numeric',year:'numeric'})}
                  </p>
                </div>
              </div>
              <div style={{ display:'flex',gap:'0.75rem',flexShrink:0 }}>
                <button className="apple-btn-primary"
                  style={{ display:'flex',alignItems:'center',gap:'0.375rem' }}
                  onClick={() => approve(v.id)}
                  disabled={actionId === v.id}>
                  <CheckCircle style={{ width:'16px',height:'16px' }} />
                  {actionId === v.id ? 'Approving...' : 'Approve'}
                </button>
                <button className="apple-btn-danger"
                  style={{ display:'flex',alignItems:'center',gap:'0.375rem' }}
                  onClick={() => reject(v.id, v.name)}
                  disabled={actionId === v.id}>
                  <XCircle style={{ width:'16px',height:'16px' }} />
                  {actionId === v.id ? 'Rejecting...' : 'Reject'}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </Layout>
  );
}
