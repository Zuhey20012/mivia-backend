import { useCallback, useEffect, useState } from 'react';
import { HeartPulse, RefreshCw, MapPin, Phone } from 'lucide-react';
import Layout from '../components/Layout';
import OrderDrawer from '../components/OrderDrawer';
import { Overlay, ErrorBox, NoticeBox } from '../components/Dialog';
import api from '../utils/api';
import { type Raw, num, str, obj, firstList, fiDate, errorText, ShapeError } from '../utils/parse';

// Courier safety (2.16, contract C14): POST /courier/incident from the courier app's Help button.
// GET /admin/incidents lists them (open first); POST /admin/incidents/:id/resolve closes one.
// Admins are pushed and emailed the moment one is reported; System lists open ones under attention.

type Incident = {
  id: number;
  type: string;
  note: string | null;
  orderId: number | null;
  lat: number | null;
  lng: number | null;
  createdAt: string | null;
  resolvedAt: string | null;
  resolvedBy: string | null;
  resolutionNote: string | null;
  courier: { id: number | null; name: string; phone: string | null };
};

const TYPES: Record<string, { label: string; badge: string }> = {
  ACCIDENT: { label: 'Accident', badge: 'badge-red' },
  THREAT: { label: 'Threat or violence', badge: 'badge-red' },
  DAMAGED: { label: 'Goods damaged', badge: 'badge-orange' },
  THEFT: { label: 'Theft', badge: 'badge-red' },
  OTHER: { label: 'Other', badge: 'badge-gray' },
};

function toIncident(r: Raw): Incident {
  const courier = obj(r.courier);
  const user = obj(courier.user);
  const resolver = obj(r.resolvedBy);
  const status = str(r.status);
  return {
    id: num(r.id) ?? 0,
    type: str(r.type) ?? 'OTHER',
    note: str(r.note),
    orderId: num(r.orderId) ?? num(obj(r.order).id),
    lat: num(r.lat) ?? num(r.latitude),
    lng: num(r.lng) ?? num(r.longitude),
    createdAt: str(r.createdAt),
    resolvedAt: str(r.resolvedAt) ?? (status === 'RESOLVED' ? str(r.updatedAt) ?? '' : null),
    resolvedBy: str(r.resolvedBy) ?? str(resolver.name) ?? str(resolver.email) ?? str(r.resolvedByName),
    resolutionNote: str(r.resolutionNote) ?? str(r.resolveNote),
    courier: {
      id: num(courier.id) ?? num(r.courierId),
      name: str(courier.name) ?? str(user.name) ?? str(r.courierName) ?? `Courier #${num(r.courierId) ?? '?'}`,
      phone: str(courier.phone) ?? str(user.phone) ?? str(r.courierPhone),
    },
  };
}

const osm = (lat: number, lng: number) => `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=17/${lat}/${lng}`;

function ResolveDialog({ incident, onClose, onDone }: { incident: Incident; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      await api.post(`/admin/incidents/${incident.id}/resolve`, note.trim() ? { note: note.trim() } : {});
      onDone();
    } catch (err) {
      setError(errorText(err, 'The incident could not be marked resolved.'));
      setBusy(false);
    }
  };

  return (
    <Overlay title={`Resolve incident #${incident.id}?`} onClose={busy ? () => undefined : onClose}>
      <form onSubmit={submit}>
        <p className="text-sm text-gray-600 mb-3">
          Mark it resolved only after you have spoken with <b>{incident.courier.name}</b> and the courier is safe. The courier app shows
          the new status, and it leaves System → attention. Recorded in the audit log.
        </p>
        <label className="text-sm block mb-3">
          <span className="block text-gray-500 mb-1">What was done (optional)</span>
          <textarea className="apple-input w-full min-h-20" maxLength={500} value={note} disabled={busy} autoFocus
            placeholder="e.g. “Called the courier, no injuries; order reassigned.”" onChange={(e) => setNote(e.target.value)} />
        </label>
        {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
        <div className="flex gap-2 justify-end">
          <button type="button" className="apple-btn-secondary" disabled={busy} onClick={onClose}>Back</button>
          <button type="submit" className="apple-btn-primary" disabled={busy}>{busy ? 'Saving…' : 'Yes, mark resolved'}</button>
        </div>
      </form>
    </Overlay>
  );
}

const TH = ({ children }: { children?: React.ReactNode }) => (
  <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{children}</th>
);

export default function Incidents() {
  const [rows, setRows] = useState<Incident[] | null>(null);
  const [error, setError] = useState('');
  const [resolving, setResolving] = useState<Incident | null>(null);
  const [notice, setNotice] = useState('');
  const [openOrder, setOpenOrder] = useState<number | null>(null);
  const [showResolved, setShowResolved] = useState(false);

  const load = useCallback(() => api.get('/admin/incidents')
    .then((r) => {
      const data = obj(r.data);
      const list = firstList(data.incidents, data.items, data.rows);
      if (!list) throw new ShapeError('The API answer has no incident list.');
      setRows(list.map(toIncident));
      setError('');
    })
    .catch((e) => setError(errorText(e, 'Could not load the incidents.'))), []);

  // First load, then every 30 s while the page is open: an incident can be someone in danger
  useEffect(() => {
    load();
    const t = window.setInterval(() => { if (!document.hidden) load(); }, 30_000);
    return () => window.clearInterval(t);
  }, [load]);

  const open = (rows ?? []).filter((i) => !i.resolvedAt);
  const resolved = (rows ?? []).filter((i) => i.resolvedAt);
  const list = showResolved ? [...open, ...resolved] : open;

  return (
    <Layout>
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2"><HeartPulse className="w-6 h-6" /> Courier incidents</h1>
          <p className="text-gray-500 text-sm mt-1 max-w-3xl">
            Reported from the courier app's Help button (accident, threat, damaged goods, theft). Call the courier first; the app already
            offered them 112. Refreshes every 30 seconds.
          </p>
        </div>
        <button className="apple-btn-secondary text-xs px-3 py-1.5 shrink-0" onClick={() => load()}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>

      {notice && <div className="mb-4"><NoticeBox>{notice}</NoticeBox></div>}
      {error && <div className="mb-4"><ErrorBox>{error}{rows !== null && ' Showing the last loaded list.'}</ErrorBox></div>}

      <div className="flex items-center justify-between mb-3">
        <h2 className="font-semibold">Open {rows && `(${open.length})`}</h2>
        <label className="text-sm text-gray-500 flex items-center gap-2">
          <input type="checkbox" checked={showResolved} onChange={(e) => setShowResolved(e.target.checked)} /> Show resolved ({resolved.length})
        </label>
      </div>
      <div className="apple-card p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100"><TH>Reported</TH><TH>Type</TH><TH>Courier</TH><TH>What happened</TH><TH>Order</TH><TH>Where</TH><TH /></tr>
          </thead>
          <tbody>
            {rows === null && !error && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">Loading…</td></tr>}
            {rows === null && error && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">—</td></tr>}
            {rows && list.length === 0 && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">{showResolved ? 'No incidents have been reported.' : 'No open incidents.'}</td></tr>}
            {list.map((i) => (
              <tr key={i.id} className={`table-row align-top ${i.resolvedAt ? 'opacity-60' : ''}`}>
                <td className="px-6 py-3 whitespace-nowrap">{fiDate(i.createdAt)}</td>
                <td className="px-6 py-3"><span className={TYPES[i.type]?.badge ?? 'badge-gray'}>{TYPES[i.type]?.label ?? i.type}</span></td>
                <td className="px-6 py-3">
                  <p className="font-medium">{i.courier.name}</p>
                  {i.courier.phone && <a className="text-blue-600 text-xs inline-flex items-center gap-1" href={`tel:${i.courier.phone}`}><Phone className="w-3 h-3" />{i.courier.phone}</a>}
                </td>
                <td className="px-6 py-3 max-w-xs break-words">{i.note ?? <span className="text-gray-400">No note</span>}
                  {i.resolvedAt && (
                    <p className="text-xs text-gray-500 mt-1">Resolved {fiDate(i.resolvedAt)}{i.resolvedBy ? ` by ${i.resolvedBy}` : ''}{i.resolutionNote ? ` · ${i.resolutionNote}` : ''}</p>
                  )}
                </td>
                <td className="px-6 py-3">
                  {i.orderId !== null ? <button className="text-blue-600 font-mono" onClick={() => setOpenOrder(i.orderId)}>#{i.orderId}</button> : '—'}
                </td>
                <td className="px-6 py-3 whitespace-nowrap">
                  {i.lat !== null && i.lng !== null
                    ? <a className="text-blue-600 inline-flex items-center gap-1" href={osm(i.lat, i.lng)} target="_blank" rel="noreferrer noopener"><MapPin className="w-3 h-3" />Map</a>
                    : '—'}
                </td>
                <td className="px-6 py-3 text-right whitespace-nowrap">
                  {!i.resolvedAt && <button className="apple-btn-primary text-xs px-3 py-1.5" onClick={() => { setNotice(''); setResolving(i); }}>Resolve</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {resolving && (
        <ResolveDialog incident={resolving} onClose={() => setResolving(null)}
          onDone={() => { setNotice(`Incident #${resolving.id} was marked resolved.`); setResolving(null); load(); }} />
      )}
      {openOrder !== null && <OrderDrawer orderId={openOrder} onClose={() => setOpenOrder(null)} />}
    </Layout>
  );
}
