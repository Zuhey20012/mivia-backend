import { useCallback, useEffect, useState } from 'react';
import { Search, ShoppingBag, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import OrderDrawer from '../components/OrderDrawer';
import { ErrorBox } from '../components/Dialog';
import api from '../utils/api';
import { type Raw, num, str, obj, arr, firstList, euro, errorText, ShapeError } from '../utils/parse';

// GET /admin/orders?q=&status=&before= (2.16, contract C13): newest first, paged with `nextBefore`.
// q matches the order number, the customer's email or the store's name. Clicking a row opens the order console.

interface Order {
  id: number; status: string; totalCents: number | null; paymentStatus: string;
  createdAt: string | null;
  fulfilment: 'DELIVERY' | 'PICKUP';
  scheduledStart: string | null; scheduledEnd: string | null;
  deliveryProblemAt: string | null; deliveryProblemReason: string | null; deliveryProblemNote: string | null;
  returnedToStoreAt: string | null; returnReceivedAt: string | null;
  cancelReason: string | null;
  disputedAt: string | null; disputeStatus: string | null;
  customer: { name: string; email: string };
  storeName: string;
  courierName: string | null;
  itemCount: number | null;
}

function toOrder(r: Raw): Order {
  const user = obj(r.user ?? r.customer);
  const store = obj(r.store);
  const courier = r.courier ? obj(r.courier) : null;
  const items = firstList(r.items);
  return {
    id: num(r.id) ?? 0,
    status: str(r.status) ?? '—',
    totalCents: num(r.totalCents),
    paymentStatus: str(r.paymentStatus) ?? '—',
    createdAt: str(r.createdAt),
    fulfilment: r.fulfilment === 'PICKUP' ? 'PICKUP' : 'DELIVERY',
    scheduledStart: str(r.scheduledStart), scheduledEnd: str(r.scheduledEnd),
    deliveryProblemAt: str(r.deliveryProblemAt), deliveryProblemReason: str(r.deliveryProblemReason), deliveryProblemNote: str(r.deliveryProblemNote),
    returnedToStoreAt: str(r.returnedToStoreAt), returnReceivedAt: str(r.returnReceivedAt),
    cancelReason: str(r.cancelReason),
    disputedAt: str(r.disputedAt), disputeStatus: str(r.disputeStatus),
    customer: { name: str(user.name) ?? str(r.customerName) ?? '—', email: str(user.email) ?? str(r.customerEmail) ?? '' },
    storeName: str(store.name) ?? str(r.storeName) ?? '—',
    courierName: courier ? str(courier.name) ?? str(obj(courier.user).name) ?? `#${num(courier.id) ?? '?'}` : null,
    itemCount: items ? items.reduce((s, i) => s + (num(i.quantity) ?? 1), 0) : num(r.itemCount),
  };
}

const PROBLEM_TEXT: Record<string, string> = {
  CUSTOMER_UNAVAILABLE: 'Courier cannot reach the customer',
  WRONG_ADDRESS: 'Courier cannot find the address',
  OTHER: 'Courier cannot deliver',
};

/** Finnish wall-clock time, e.g. "16.10. 17:00" */
const hel = (iso: string, withDay = true) => new Date(iso).toLocaleString('fi-FI', {
  timeZone: 'Europe/Helsinki', hour: '2-digit', minute: '2-digit', ...(withDay ? { day: 'numeric', month: 'numeric' } : {}),
});

/** The delivery window (scheduled slot), pickup, or "as soon as possible", plus any delivery problem. */
function DeliveryCell({ o }: { o: Order }) {
  return (
    <div>
      <p style={{ color:'#3C3C43' }}>
        {o.fulfilment === 'PICKUP' ? 'Pickup at the store'
          : o.scheduledStart && o.scheduledEnd ? `${hel(o.scheduledStart)}–${hel(o.scheduledEnd, false)}`
          : 'As soon as possible'}
      </p>
      {o.courierName && <p style={{ color:'#8E8E93',fontSize:'0.75rem' }}>Courier {o.courierName}</p>}
      {o.deliveryProblemAt && !o.returnedToStoreAt && (
        <p style={{ marginTop:'0.25rem' }}>
          <span className="badge-red">{PROBLEM_TEXT[o.deliveryProblemReason ?? 'OTHER'] ?? 'Delivery problem'}</span>
          <span style={{ color:'#8E8E93',fontSize:'0.75rem',display:'block' }}>since {hel(o.deliveryProblemAt)}{o.deliveryProblemNote ? ` · ${o.deliveryProblemNote}` : ''}</span>
        </p>
      )}
      {o.returnedToStoreAt && (
        <p style={{ color:'#8E8E93',fontSize:'0.75rem',marginTop:'0.25rem' }}>
          Taken back to the shop {hel(o.returnedToStoreAt)} · {o.returnReceivedAt ? `store got it ${hel(o.returnReceivedAt)}` : 'store has not confirmed yet'}
        </p>
      )}
    </div>
  );
}

const statusBadge: Record<string,string> = {
  PENDING:'badge-yellow', CONFIRMED:'badge-blue', PROCESSING:'badge-blue',
  SHIPPED:'badge-blue', DELIVERED:'badge-green', CANCELLED:'badge-red', REFUNDED:'badge-gray',
};

const PAGE = 50;
type Page = { orders: Order[]; nextBefore: string | number | null; serverSearch: boolean };

function fetchPage(q: string, status: string, before: string | number | null): Promise<Page> {
  const params: Record<string, string | number> = { limit: PAGE };
  if (q) params.q = q;
  // PROBLEM and DISPUTED are not order statuses: ask with a flag (ignored by an API without it) and filter here too
  if (status === 'PROBLEM') params.problem = 1;
  else if (status === 'DISPUTED') params.disputed = 1;
  else if (status !== 'ALL') params.status = status;
  if (before !== null) params.before = before;
  return api.get('/admin/orders', { params }).then((r) => {
    const data = obj(r.data);
    const list = firstList(data.orders, data.items, data.rows);
    if (!list) throw new ShapeError('The API answer has no order list.');
    const next = data.nextBefore;
    return {
      orders: arr(list).map(toOrder),
      nextBefore: typeof next === 'string' || typeof next === 'number' ? next : null,
      // An API from before 2.16 ignores q/status and has no nextBefore: then the page filters what it loaded
      serverSearch: 'nextBefore' in data,
    };
  });
}

function matches(o: Order, q: string, status: string): boolean {
  const s = q.trim().toLowerCase().replace(/^#/, '');
  const matchSearch = !s || String(o.id) === s || o.customer.name.toLowerCase().includes(s)
    || o.customer.email.toLowerCase().includes(s) || o.storeName.toLowerCase().includes(s);
  const matchStatus = status === 'ALL' || o.status === status
    || (status === 'PROBLEM' && !!o.deliveryProblemAt && !o.returnedToStoreAt)
    || (status === 'DISPUTED' && !!o.disputedAt);
  return matchSearch && matchStatus;
}

export default function Orders() {
  const [input, setInput] = useState('');
  const [query, setQuery] = useState({ q: '', status: 'ALL' });
  const [orders, setOrders] = useState<Order[] | null>(null);
  const [nextBefore, setNextBefore] = useState<string | number | null>(null);
  const [serverSearch, setServerSearch] = useState(true);
  const [error, setError] = useState('');
  const [loadingMore, setLoadingMore] = useState(false);
  const [reload, setReload] = useState(0);
  const [openId, setOpenId] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchPage(query.q, query.status, null)
      .then((p) => { if (!cancelled) { setOrders(p.orders); setNextBefore(p.nextBefore); setServerSearch(p.serverSearch); setError(''); } })
      .catch((e) => { if (!cancelled) { setError(errorText(e, 'Could not load the orders.')); } });
    return () => { cancelled = true; };
  }, [query, reload]);

  const refresh = useCallback(() => { setReload((n) => n + 1); }, []);

  const loadMore = async () => {
    if (nextBefore === null) return;
    setLoadingMore(true);
    try {
      const p = await fetchPage(query.q, query.status, nextBefore);
      setOrders((cur) => [...(cur ?? []), ...p.orders.filter((o) => !(cur ?? []).some((c) => c.id === o.id))]);
      setNextBefore(p.nextBefore);
      setError('');
    } catch (e) {
      setError(errorText(e, 'Could not load more orders.'));
    } finally {
      setLoadingMore(false);
    }
  };

  const apply = (q: string, status: string) => { setOrders(null); setError(''); setQuery({ q: q.trim(), status }); };

  const shown = (orders ?? []).filter((o) => serverSearch && query.status !== 'PROBLEM' && query.status !== 'DISPUTED' ? true : matches(o, query.q, query.status));
  const filtering = !!query.q || query.status !== 'ALL';

  return (
    <Layout>
      <div style={{ marginBottom:'2rem', display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div>
          <h1 style={{ fontSize:'1.5rem', fontWeight:600, letterSpacing:'-0.02em' }}>Orders</h1>
          <p style={{ color:'#8E8E93', fontSize:'0.875rem', marginTop:'0.25rem' }}>
            Newest first. Open an order to see everything about it and to cancel, refund or unassign the courier.
          </p>
        </div>
        <button onClick={refresh} style={{ display:'flex',alignItems:'center',gap:'0.375rem',color:'#0071E3',fontSize:'0.875rem',fontWeight:500,background:'none',border:'none',cursor:'pointer' }}>
          <RefreshCw style={{ width:'14px',height:'14px' }} /> Refresh
        </button>
      </div>

      <form className="apple-card" style={{ marginBottom:'1.5rem', display:'flex', gap:'1rem', flexWrap:'wrap' }}
        onSubmit={(e) => { e.preventDefault(); apply(input, query.status); }}>
        <div style={{ position:'relative', flex:1, minWidth:'200px' }}>
          <Search style={{ position:'absolute',left:'1rem',top:'50%',transform:'translateY(-50%)',width:'16px',height:'16px',color:'#8E8E93' }} />
          <input className="apple-input" style={{ paddingLeft:'2.75rem' }} placeholder="Order number, customer email or store name" value={input} onChange={e => setInput(e.target.value)} />
        </div>
        <select className="apple-input" style={{ width:'180px' }} value={query.status} onChange={e => apply(input, e.target.value)} aria-label="Status">
          <option value="ALL">All statuses</option>
          {Object.keys(statusBadge).map(s => <option key={s} value={s}>{s}</option>)}
          <option value="PROBLEM">Delivery problem</option>
          <option value="DISPUTED">Card dispute</option>
        </select>
        <button type="submit" className="apple-btn-primary">Search</button>
        {filtering && <button type="button" className="apple-btn-secondary" onClick={() => { setInput(''); apply('', 'ALL'); }}>Clear</button>}
      </form>

      {!serverSearch && filtering && (
        <p className="text-xs text-amber-600 mb-3">This API version does not search on the server: only the {orders?.length ?? 0} orders loaded are filtered.</p>
      )}
      {error && <div className="mb-4"><ErrorBox>{error}{orders !== null && ' Showing what was loaded before.'}</ErrorBox></div>}

      <div className="apple-card" style={{ padding:0,overflow:'auto' }}>
        {orders === null && !error ? (
          <div style={{ display:'flex',alignItems:'center',justifyContent:'center',padding:'4rem',color:'#8E8E93',gap:'0.5rem' }}>
            <RefreshCw style={{ width:'16px',height:'16px' }} /> Loading orders...
          </div>
        ) : orders === null ? (
          <div style={{ padding:'2rem',color:'#8E8E93',fontSize:'0.875rem' }}>No orders could be shown.</div>
        ) : shown.length === 0 ? (
          <div style={{ display:'flex',flexDirection:'column',alignItems:'center',padding:'4rem',color:'#C7C7CC' }}>
            <ShoppingBag style={{ width:'40px',height:'40px',marginBottom:'0.75rem' }} />
            <p style={{ fontSize:'0.875rem' }}>{filtering ? 'No orders match your search' : 'No orders yet. They will appear here when customers start buying.'}</p>
          </div>
        ) : (
          <table style={{ width:'100%',fontSize:'0.875rem',borderCollapse:'collapse' }}>
            <thead>
              <tr style={{ borderBottom:'1px solid #F5F5F7' }}>
                {['Order #','Customer','Vendor','Items','Delivery','Total','Payment','Status','Date'].map(h => (
                  <th key={h} style={{ textAlign:'left',padding:'1rem 1.5rem',fontSize:'0.6875rem',fontWeight:500,color:'#8E8E93',textTransform:'uppercase',letterSpacing:'0.05em' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {shown.map(o => (
                <tr key={o.id} className="table-row" style={{ cursor:'pointer' }} onClick={() => setOpenId(o.id)}
                  tabIndex={0} onKeyDown={(e) => { if (e.key === 'Enter') setOpenId(o.id); }}>
                  <td style={{ padding:'1rem 1.5rem',fontFamily:'monospace',fontWeight:500,color:'#0071E3' }}>#{o.id}</td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <p style={{ fontWeight:500 }}>{o.customer.name}</p>
                    <p style={{ color:'#8E8E93',fontSize:'0.75rem' }}>{o.customer.email}</p>
                  </td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{o.storeName}</td>
                  <td style={{ padding:'1rem 1.5rem',color:'#3C3C43' }}>{o.itemCount ?? '—'}</td>
                  <td style={{ padding:'1rem 1.5rem' }}><DeliveryCell o={o} /></td>
                  <td style={{ padding:'1rem 1.5rem',fontWeight:600,whiteSpace:'nowrap' }}>{euro(o.totalCents)}</td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <span className={o.paymentStatus === 'SUCCEEDED' ? 'badge-green' : o.paymentStatus === 'FAILED' ? 'badge-red' : 'badge-yellow'}>
                      {o.paymentStatus}
                    </span>
                    {o.disputedAt && <span className="badge-red" style={{ display:'flex',marginTop:'0.25rem',width:'fit-content' }}>dispute {o.disputeStatus ?? ''}</span>}
                  </td>
                  <td style={{ padding:'1rem 1.5rem' }}>
                    <span className={statusBadge[o.status] || 'badge-gray'}>{o.status}</span>
                    {o.status === 'CANCELLED' && o.cancelReason && <p style={{ color:'#8E8E93',fontSize:'0.75rem',marginTop:'0.25rem',maxWidth:'14rem' }}>{o.cancelReason}</p>}
                  </td>
                  <td style={{ padding:'1rem 1.5rem',color:'#8E8E93',fontSize:'0.75rem',whiteSpace:'nowrap' }}>
                    {o.createdAt ? new Date(o.createdAt).toLocaleDateString('fi-FI', { timeZone: 'Europe/Helsinki' }) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {orders !== null && (
        <div className="flex items-center justify-between mt-4 text-sm text-gray-500">
          <span>{shown.length} order{shown.length !== 1 ? 's' : ''} shown</span>
          {nextBefore !== null && (
            <button className="apple-btn-secondary" onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load more'}</button>
          )}
        </div>
      )}

      {openId !== null && <OrderDrawer orderId={openId} onClose={() => setOpenId(null)} onChanged={refresh} />}
    </Layout>
  );
}
