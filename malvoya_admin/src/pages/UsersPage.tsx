import { useEffect, useState } from 'react';
import { Search, Users, ShieldOff, Eye, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

interface User {
  id: number; name: string; email: string;
  role: string; phone: string | null; createdAt: string;
}

const roleBadge: Record<string,string> = {
  CUSTOMER:'badge-blue', VENDOR:'badge-purple',
  COURIER:'badge-orange', ADMIN:'badge-red',
};

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('ALL');
  const [banId, setBanId] = useState<number|null>(null);

  const load = async () => {
    setLoading(true);
    try { const r = await api.get('/admin/users'); setUsers(r.data.users); }
    catch { /* silent */ }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const ban = async (id: number, name: string) => {
    if (!confirm(`Remove user "${name}"? This cannot be undone.`)) return;
    setBanId(id);
    try { await api.delete(`/admin/users/${id}`); await load(); }
    catch { alert('Failed to remove user.'); }
    finally { setBanId(null); }
  };

  const filtered = users.filter(u => {
    const matchSearch = u.name.toLowerCase().includes(search.toLowerCase()) ||
                        u.email.toLowerCase().includes(search.toLowerCase());
    const matchRole = roleFilter === 'ALL' || u.role === roleFilter;
    return matchSearch && matchRole;
  });

  const counts = { ALL: users.length, CUSTOMER: 0, VENDOR: 0, COURIER: 0, ADMIN: 0 } as Record<string,number>;
  users.forEach(u => { if (counts[u.role] !== undefined) counts[u.role]++; });

  return (
    <Layout>
      <div style={{ marginBottom:'2rem', display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div>
          <h1 style={{ fontSize:'1.5rem', fontWeight:600, letterSpacing:'-0.02em' }}>Users</h1>
          <p style={{ color:'#8E8E93', fontSize:'0.875rem', marginTop:'0.25rem' }}>All registered Malvoya users</p>
        </div>
        <button onClick={load} style={{ display:'flex',alignItems:'center',gap:'0.375rem',color:'#0071E3',fontSize:'0.875rem',fontWeight:500,background:'none',border:'none',cursor:'pointer' }}>
          <RefreshCw style={{ width:'14px',height:'14px' }} /> Refresh
        </button>
      </div>

      {/* Role filter tabs */}
      <div style={{ display:'flex',gap:'0.5rem',marginBottom:'1.5rem',flexWrap:'wrap' }}>
        {['ALL','CUSTOMER','VENDOR','COURIER','ADMIN'].map(r => (
          <button key={r} onClick={() => setRoleFilter(r)}
            style={{
              padding:'0.5rem 1rem', borderRadius:'9999px', border:'none', cursor:'pointer',
              fontSize:'0.8125rem', fontWeight:500,
              background: roleFilter === r ? '#1D1D1F' : '#F5F5F7',
              color: roleFilter === r ? 'white' : '#3C3C43',
              transition:'all 0.15s',
            }}>
            {r} ({counts[r] ?? 0})
          </button>
        ))}
      </div>

      {/* Search */}
      <div className="apple-card" style={{ marginBottom:'1.5rem' }}>
        <div style={{ position:'relative' }}>
          <Search style={{ position:'absolute',left:'1rem',top:'50%',transform:'translateY(-50%)',width:'16px',height:'16px',color:'#8E8E93' }} />
          <input className="apple-input" style={{ paddingLeft:'2.75rem' }} placeholder="Search users by name or email..." value={search} onChange={e => setSearch(e.target.value)} />
        </div>
      </div>

      <div className="apple-card" style={{ padding:0,overflow:'hidden' }}>
        {loading ? (
          <div style={{ display:'flex',alignItems:'center',justifyContent:'center',padding:'4rem',color:'#8E8E93',gap:'0.5rem' }}>
            <RefreshCw style={{ width:'16px',height:'16px' }} /> Loading users...
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ display:'flex',flexDirection:'column',alignItems:'center',padding:'4rem',color:'#C7C7CC' }}>
            <Users style={{ width:'40px',height:'40px',marginBottom:'0.75rem' }} />
            <p style={{ fontSize:'0.875rem' }}>No users found</p>
          </div>
        ) : (
          <table style={{ width:'100%', fontSize:'0.875rem', borderCollapse:'collapse' }}>
            <thead>
              <tr style={{ borderBottom:'1px solid #F5F5F7' }}>
                {['User','Role','Phone','Joined','Actions'].map(h => (
                  <th key={h} style={{ textAlign:'left',padding:'1rem 1.5rem',fontSize:'0.6875rem',fontWeight:500,color:'#8E8E93',textTransform:'uppercase',letterSpacing:'0.05em' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map(u => (
                <tr key={u.id} className="table-row">
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <div style={{ display:'flex',alignItems:'center',gap:'0.75rem' }}>
                      <div style={{ width:'32px',height:'32px',borderRadius:'50%',background:'#F5F5F7',display:'flex',alignItems:'center',justifyContent:'center',fontWeight:600,fontSize:'0.875rem',flexShrink:0 }}>
                        {u.name.charAt(0).toUpperCase()}
                      </div>
                      <div>
                        <p style={{ fontWeight:500 }}>{u.name}</p>
                        <p style={{ color:'#8E8E93',fontSize:'0.75rem' }}>{u.email}</p>
                      </div>
                    </div>
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <span className={roleBadge[u.role] || 'badge-gray'}>{u.role}</span>
                  </td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{u.phone || '—'}</td>
                  <td style={{ padding:'1rem 1.5rem',color:'#8E8E93',fontSize:'0.75rem' }}>
                    {new Date(u.createdAt).toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' })}
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <div style={{ display:'flex',gap:'0.5rem' }}>
                      {u.role !== 'ADMIN' && (
                        <button className="apple-btn-danger" style={{ padding:'0.375rem 0.75rem',fontSize:'0.75rem',display:'flex',alignItems:'center',gap:'0.25rem' }}
                          onClick={() => ban(u.id, u.name)} disabled={banId === u.id}>
                          <ShieldOff style={{ width:'12px',height:'12px' }} />
                          {banId === u.id ? '...' : 'Remove'}
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
