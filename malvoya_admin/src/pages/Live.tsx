import { useCallback, useEffect, useState } from 'react';
import { Radio, MessageSquare, X, RefreshCw } from 'lucide-react';
import { isAxiosError } from 'axios';
import Layout from '../components/Layout';
import api from '../utils/api';

// GET /admin/live (2.15): lives on air now + the last 50 ended, with report counts
type LiveRow = {
  id: number;
  title: string;
  status: 'LIVE' | 'ENDED';
  startedAt: string;
  endedAt: string | null;
  endedReason: string | null;
  viewers: number | null;
  viewerPeak: number;
  likeCount: number;
  reportCount: number;
  store: { id: number | null; name: string };
};

// GET /admin/live/:id/messages: every message, hidden ones included
type LiveMessage = { id: number; text: string; name: string; byStore: boolean; hidden: boolean; createdAt: string };

type Raw = Record<string, unknown>;

const REFRESH_MS = 20_000;

const errorText = (e: unknown, fallback: string): string =>
  (isAxiosError(e) && typeof e.response?.data?.error === 'string' && e.response.data.error) || fallback;

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const str = (v: unknown): string | null => (typeof v === 'string' && v ? v : null);
const arr = (v: unknown): Raw[] => (Array.isArray(v) ? (v as Raw[]) : []);

/** Reads one live, accepting the small naming differences the API may have (store object or storeName, _count, …). */
function toRow(r: Raw): LiveRow {
  const store = (r.store && typeof r.store === 'object' ? r.store : {}) as Raw;
  const count = (r._count && typeof r._count === 'object' ? r._count : {}) as Raw;
  return {
    id: num(r.id) ?? 0,
    title: str(r.title) ?? '',
    status: r.status === 'ENDED' || r.endedAt ? 'ENDED' : 'LIVE',
    startedAt: str(r.startedAt) ?? str(r.createdAt) ?? '',
    endedAt: str(r.endedAt),
    endedReason: str(r.endedReason),
    viewers: num(r.viewers) ?? num(r.viewerCount),
    viewerPeak: num(r.viewerPeak) ?? 0,
    likeCount: num(r.likeCount) ?? num(r.likes) ?? 0,
    reportCount: num(r.reportCount) ?? num(r.reports) ?? num(count.reports) ?? 0,
    store: { id: num(store.id) ?? num(r.storeId), name: str(store.name) ?? str(r.storeName) ?? `Store #${num(r.storeId) ?? '?'}` },
  };
}

/** Splits the answer into on air now and recently ended, whether it comes as two lists or one. */
function parseLives(data: Raw): { live: LiveRow[]; ended: LiveRow[] } {
  const liveList = [data.live, data.liveNow, data.active].find(Array.isArray);
  const endedList = [data.ended, data.recentlyEnded, data.recent].find(Array.isArray);
  if (liveList || endedList) {
    return { live: arr(liveList).map(toRow), ended: arr(endedList).map(toRow) };
  }
  const all = arr(data.lives).map(toRow);
  return { live: all.filter((l) => l.status === 'LIVE'), ended: all.filter((l) => l.status === 'ENDED') };
}

function toMessage(m: Raw): LiveMessage {
  const user = (m.user && typeof m.user === 'object' ? m.user : {}) as Raw;
  return {
    id: num(m.id) ?? 0,
    text: str(m.text) ?? '',
    name: str(m.name) ?? str(user.name) ?? (num(m.userId) !== null ? `User #${m.userId}` : 'Unknown'),
    byStore: m.byStore === true,
    hidden: m.hidden === true,
    createdAt: str(m.createdAt) ?? '',
  };
}

const fullDate = (iso: string | null) => (iso ? new Date(iso).toLocaleString('fi-FI') : '—');

function ago(iso: string, now: number): string {
  const t = new Date(iso).getTime();
  if (!Number.isFinite(t)) return '—';
  const min = Math.max(0, Math.round((now - t) / 60_000));
  if (min < 1) return 'just now';
  if (min < 60) return `${min} min ago`;
  const h = Math.floor(min / 60);
  return `${h} h ${min % 60} min ago`;
}

function duration(from: string, to: string | null): string {
  if (!to) return '—';
  const min = Math.max(0, Math.round((new Date(to).getTime() - new Date(from).getTime()) / 60_000));
  if (!Number.isFinite(min)) return '—';
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`;
}

const REASONS: Record<string, string> = {
  store: 'Ended by the store',
  timeout: 'Connection lost (no heartbeat)',
  max_duration: 'Reached the 4-hour limit',
};

function Overlay({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/30 flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label={title}
      onClick={onClose}>
      <div className="apple-card w-full max-w-lg max-h-[85vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-4 mb-3">
          <h2 className="font-semibold">{title}</h2>
          <button className="text-gray-400 hover:text-gray-600" onClick={onClose} aria-label="Close"><X className="w-5 h-5" /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

function EndDialog({ live, onClose, onEnded }: { live: LiveRow; onClose: () => void; onEnded: () => void }) {
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const text = reason.trim();
    if (text.length < 10) return setError('Write the reason in at least 10 characters: the store receives it as the statement of reasons.');
    setBusy(true);
    setError('');
    try {
      await api.post(`/admin/live/${live.id}/end`, { reason: text });
      onEnded();
    } catch (err) {
      setError(errorText(err, 'The live could not be ended. Please try again.'));
      setBusy(false);
    }
  };

  return (
    <Overlay title={`End “${live.title}”?`} onClose={busy ? () => undefined : onClose}>
      <form onSubmit={submit}>
        <p className="text-sm text-gray-600 mb-3">
          The stream of <span className="font-medium">{live.store.name}</span> stops for every viewer at once and cannot be
          resumed. The store is emailed this reason as a statement of reasons (DSA), and the action is recorded in the audit log.
        </p>
        <label className="text-sm block mb-3">
          <span className="block text-gray-500 mb-1">Reason *</span>
          <textarea className="apple-input w-full min-h-28" maxLength={500} value={reason} disabled={busy} autoFocus
            placeholder="Which rule the live broke and what was seen, e.g. “Counterfeit branded bags shown and offered for sale.”"
            onChange={(e) => setReason(e.target.value)} />
        </label>
        {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3 mb-3">{error}</div>}
        <div className="flex gap-2 justify-end">
          <button type="button" className="apple-btn-secondary" disabled={busy} onClick={onClose}>Cancel</button>
          <button type="submit" className="apple-btn-danger" disabled={busy || !reason.trim()}>{busy ? 'Ending…' : 'End live and email the store'}</button>
        </div>
      </form>
    </Overlay>
  );
}

function MessagesPanel({ live, onClose }: { live: LiveRow; onClose: () => void }) {
  const [messages, setMessages] = useState<LiveMessage[] | null>(null);
  const [error, setError] = useState('');
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let cancelled = false;
    api.get(`/admin/live/${live.id}/messages`)
      .then((r) => { if (!cancelled) { setMessages(arr(r.data.messages).map(toMessage)); setError(''); } })
      .catch((e) => { if (!cancelled) setError(errorText(e, 'Could not load the messages.')); });
    return () => { cancelled = true; };
  }, [live.id, reload]);

  return (
    <Overlay title={`Messages · ${live.title}`} onClose={onClose}>
      <div className="flex items-center justify-between mb-3">
        <p className="text-xs text-gray-500">{live.store.name} · read-only. Hidden messages were removed by the store or an admin.</p>
        <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => setReload((n) => n + 1)}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>
      <div className="overflow-y-auto flex-1 -mx-1 px-1">
        {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3">{error}</div>}
        {!error && messages === null && <p className="text-sm text-gray-400">Loading…</p>}
        {!error && messages?.length === 0 && <p className="text-sm text-gray-400">No messages in this live.</p>}
        <ul className="space-y-2">
          {!error && messages?.map((m) => (
            <li key={m.id} className={`rounded-xl px-3 py-2 text-sm ${m.hidden ? 'bg-red-50' : 'bg-gray-50'}`}>
              <div className="flex items-center gap-2 text-xs text-gray-500 mb-0.5">
                <span className="font-medium text-gray-700">{m.name}</span>
                {m.byStore && <span className="badge-purple">store</span>}
                {m.hidden && <span className="badge-red">hidden</span>}
                <span className="ml-auto">{fullDate(m.createdAt)}</span>
              </div>
              <p className={`break-words ${m.hidden ? 'text-gray-500 line-through' : ''}`}>{m.text}</p>
            </li>
          ))}
        </ul>
      </div>
    </Overlay>
  );
}

const TH = ({ children }: { children?: React.ReactNode }) => (
  <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{children}</th>
);

export default function Live() {
  const [data, setData] = useState<{ live: LiveRow[]; ended: LiveRow[] } | null>(null);
  const [loadError, setLoadError] = useState('');
  const [loadedAt, setLoadedAt] = useState<number>(() => Date.now());
  const [ending, setEnding] = useState<LiveRow | null>(null);
  const [reading, setReading] = useState<LiveRow | null>(null);
  const [notice, setNotice] = useState('');

  const load = useCallback(() => {
    return api.get('/admin/live')
      .then((r) => { setData(parseLives(r.data ?? {})); setLoadError(''); setLoadedAt(Date.now()); })
      .catch((e) => setLoadError(errorText(e, 'Could not load the lives.')));
  }, []);

  // First load, then every 20 s while the page is open (skipped while the tab is in the background)
  useEffect(() => {
    load();
    const timer = window.setInterval(() => { if (!document.hidden) load(); }, REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  const live = data?.live ?? [];
  const ended = data?.ended ?? [];

  return (
    <Layout>
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2"><Radio className="w-6 h-6" /> Live</h1>
          <p className="text-gray-500 text-sm mt-1 max-w-3xl">
            Stores streaming from their phone right now. Lives are not recorded, so check reported lives while they are on air.
            Ending a live stops it for everyone and emails the store your reason. Refreshes every 20 seconds.
          </p>
        </div>
        <button className="apple-btn-secondary text-xs px-3 py-1.5 shrink-0" onClick={() => load()}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>

      {notice && <div className="bg-green-50 text-green-700 text-sm rounded-xl px-4 py-3 mb-4">{notice}</div>}
      {loadError && data !== null && (
        <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3 mb-4">{loadError} Showing the last loaded list.</div>
      )}

      <h2 className="font-semibold mb-3 flex items-center gap-2">
        <span className="w-2 h-2 rounded-full bg-red-500" /> Live now {data && `(${live.length})`}
      </h2>
      <div className="apple-card p-0 overflow-x-auto mb-8">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              <TH>Store</TH><TH>Title</TH><TH>Started</TH><TH>Viewers</TH><TH>Likes</TH><TH>Reports</TH><TH />
            </tr>
          </thead>
          <tbody>
            {loadError && data === null && (
              <tr><td colSpan={7} className="px-6 py-6"><div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3">{loadError}</div></td></tr>
            )}
            {!loadError && data === null && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">Loading…</td></tr>}
            {data && live.length === 0 && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">No store is live right now.</td></tr>}
            {live.map((l) => (
              <tr key={l.id} className="table-row align-top">
                <td className="px-6 py-3 font-medium">{l.store.name}</td>
                <td className="px-6 py-3 max-w-xs break-words">{l.title}</td>
                <td className="px-6 py-3 whitespace-nowrap" title={fullDate(l.startedAt)}>{ago(l.startedAt, loadedAt)}</td>
                <td className="px-6 py-3">{l.viewers ?? '—'}<span className="text-xs text-gray-400"> · peak {l.viewerPeak}</span></td>
                <td className="px-6 py-3">{l.likeCount}</td>
                <td className="px-6 py-3">
                  <span className={l.reportCount > 0 ? 'badge-red' : 'badge-gray'}>{l.reportCount}</span>
                </td>
                <td className="px-6 py-3 text-right whitespace-nowrap">
                  <button className="apple-btn-secondary text-xs px-3 py-1.5 mr-2" onClick={() => setReading(l)}>
                    <MessageSquare className="w-3 h-3" /> Messages
                  </button>
                  <button className="apple-btn-danger text-xs px-3 py-1.5" onClick={() => { setNotice(''); setEnding(l); }}>End live</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="font-semibold mb-3">Recently ended {data && `(${ended.length})`}</h2>
      <div className="apple-card p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              <TH>Store</TH><TH>Title</TH><TH>Started</TH><TH>Duration</TH><TH>Peak viewers</TH><TH>Reports</TH><TH>Ended</TH><TH />
            </tr>
          </thead>
          <tbody>
            {!loadError && data === null && <tr><td colSpan={8} className="px-6 py-6 text-gray-400">Loading…</td></tr>}
            {loadError && data === null && <tr><td colSpan={8} className="px-6 py-6 text-gray-400">—</td></tr>}
            {data && ended.length === 0 && <tr><td colSpan={8} className="px-6 py-6 text-gray-400">No lives have ended yet.</td></tr>}
            {ended.map((l) => (
              <tr key={l.id} className="table-row align-top">
                <td className="px-6 py-3 font-medium">{l.store.name}</td>
                <td className="px-6 py-3 max-w-xs break-words">{l.title}</td>
                <td className="px-6 py-3 whitespace-nowrap">{fullDate(l.startedAt)}</td>
                <td className="px-6 py-3 whitespace-nowrap">{duration(l.startedAt, l.endedAt)}</td>
                <td className="px-6 py-3">{l.viewerPeak}</td>
                <td className="px-6 py-3">
                  <span className={l.reportCount > 0 ? 'badge-red' : 'badge-gray'}>{l.reportCount}</span>
                </td>
                <td className="px-6 py-3 text-xs max-w-xs break-words">
                  {l.endedReason
                    ? REASONS[l.endedReason] ?? <><span className="badge-orange mr-1">admin</span>{l.endedReason}</>
                    : '—'}
                </td>
                <td className="px-6 py-3 text-right whitespace-nowrap">
                  <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => setReading(l)}>
                    <MessageSquare className="w-3 h-3" /> Messages
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {ending && (
        <EndDialog live={ending} onClose={() => setEnding(null)}
          onEnded={() => { setNotice(`“${ending.title}” was ended and ${ending.store.name} was emailed the reason.`); setEnding(null); load(); }} />
      )}
      {reading && <MessagesPanel live={reading} onClose={() => setReading(null)} />}
    </Layout>
  );
}
