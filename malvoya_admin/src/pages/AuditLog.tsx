import { useEffect, useState } from 'react';
import { History, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import { ErrorBox } from '../components/Dialog';
import api from '../utils/api';
import { type Raw, num, str, obj, firstList, fiDate, errorText, ShapeError } from '../utils/parse';

// GET /admin/audit?before= (2.16, contract B10/C13): every admin action (bans, approvals, refunds, cancellations,
// commission, promo codes, switches, DAC7 views, …), newest first, paged with `nextBefore`.

type Entry = {
  id: number;
  createdAt: string | null;
  admin: string;
  action: string;
  entity: string | null;
  entityId: number | null;
  oldValue: unknown;
  newValue: unknown;
};

function toEntry(r: Raw): Entry {
  const admin = obj(r.admin ?? r.user);
  return {
    id: num(r.id) ?? 0,
    createdAt: str(r.createdAt) ?? str(r.at),
    admin: str(admin.email) ?? str(admin.name) ?? str(r.adminEmail) ?? str(r.adminName) ?? (num(r.adminId) !== null ? `Admin #${num(r.adminId)}` : '—'),
    action: str(r.action) ?? '—',
    entity: str(r.entity),
    entityId: num(r.entityId),
    oldValue: r.oldValue ?? null,
    newValue: r.newValue ?? null,
  };
}

const PAGE = 50;
type Page = { entries: Entry[]; nextBefore: string | number | null };

function fetchPage(before: string | number | null): Promise<Page> {
  const params: Record<string, string | number> = { limit: PAGE };
  if (before !== null) params.before = before;
  return api.get('/admin/audit', { params }).then((r) => {
    const data = obj(r.data);
    const list = firstList(data.entries, data.logs, data.audit, data.items, data.rows);
    if (!list) throw new ShapeError('The API answer has no audit list.');
    const entries = list.map(toEntry);
    const next = data.nextBefore;
    return {
      entries,
      // Without nextBefore in the answer, a full page means there may be more: continue from the oldest id
      nextBefore: typeof next === 'string' || typeof next === 'number' ? next
        : !('nextBefore' in data) && entries.length >= PAGE ? entries[entries.length - 1].id : null,
    };
  });
}

/** Compact one-line JSON; long values open in a details element. */
function Value({ v }: { v: unknown }) {
  if (v === null || v === undefined) return <span className="text-gray-300">—</span>;
  const text = typeof v === 'string' ? v : JSON.stringify(v);
  if (text.length <= 80) return <code className="text-xs break-all">{text}</code>;
  return (
    <details>
      <summary className="cursor-pointer text-xs text-gray-600 break-all">{text.slice(0, 80)}…</summary>
      <pre className="text-xs whitespace-pre-wrap break-all bg-gray-50 rounded-lg p-2 mt-1 max-h-64 overflow-auto">{JSON.stringify(v, null, 2)}</pre>
    </details>
  );
}

const TH = ({ children }: { children?: React.ReactNode }) => (
  <th className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{children}</th>
);

export default function AuditLog() {
  const [entries, setEntries] = useState<Entry[] | null>(null);
  const [nextBefore, setNextBefore] = useState<string | number | null>(null);
  const [error, setError] = useState('');
  const [loadingMore, setLoadingMore] = useState(false);
  const [reload, setReload] = useState(0);
  const [filter, setFilter] = useState('');

  useEffect(() => {
    let cancelled = false;
    fetchPage(null)
      .then((p) => { if (!cancelled) { setEntries(p.entries); setNextBefore(p.nextBefore); setError(''); } })
      .catch((e) => { if (!cancelled) setError(errorText(e, 'Could not load the audit log.')); });
    return () => { cancelled = true; };
  }, [reload]);

  const loadMore = async () => {
    if (nextBefore === null) return;
    setLoadingMore(true);
    try {
      const p = await fetchPage(nextBefore);
      setEntries((cur) => [...(cur ?? []), ...p.entries.filter((e) => !(cur ?? []).some((c) => c.id === e.id))]);
      setNextBefore(p.nextBefore);
      setError('');
    } catch (e) {
      setError(errorText(e, 'Could not load older entries.'));
    } finally {
      setLoadingMore(false);
    }
  };

  const f = filter.trim().toLowerCase();
  const shown = (entries ?? []).filter((e) => !f || e.action.toLowerCase().includes(f) || e.admin.toLowerCase().includes(f)
    || (e.entity ?? '').toLowerCase().includes(f) || String(e.entityId ?? '') === f.replace(/^#/, ''));

  return (
    <Layout>
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2"><History className="w-6 h-6" /> Audit log</h1>
          <p className="text-gray-500 text-sm mt-1 max-w-3xl">
            Every action an admin took that changes money, accounts, content or settings, newest first. Entries cannot be edited or deleted.
          </p>
        </div>
        <button className="apple-btn-secondary text-xs px-3 py-1.5 shrink-0" onClick={() => { setEntries(null); setError(''); setReload((n) => n + 1); }}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>

      <div className="apple-card mb-4">
        <input className="apple-input" placeholder="Filter the loaded entries by action, admin, entity or id (e.g. order.refund, Store, 42)"
          value={filter} onChange={(e) => setFilter(e.target.value)} />
      </div>

      {error && <div className="mb-4"><ErrorBox>{error}{entries !== null && ' Showing what was loaded before.'}</ErrorBox></div>}

      <div className="apple-card p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100"><TH>When</TH><TH>Admin</TH><TH>Action</TH><TH>Target</TH><TH>Before</TH><TH>After</TH></tr>
          </thead>
          <tbody>
            {entries === null && !error && <tr><td colSpan={6} className="px-6 py-6 text-gray-400">Loading…</td></tr>}
            {entries === null && error && <tr><td colSpan={6} className="px-6 py-6 text-gray-400">—</td></tr>}
            {entries && shown.length === 0 && <tr><td colSpan={6} className="px-6 py-6 text-gray-400">{f ? 'No loaded entry matches the filter.' : 'No admin actions recorded yet.'}</td></tr>}
            {shown.map((e) => (
              <tr key={e.id} className="table-row align-top">
                <td className="px-6 py-3 whitespace-nowrap">{fiDate(e.createdAt)}</td>
                <td className="px-6 py-3 text-xs">{e.admin}</td>
                <td className="px-6 py-3"><code className="text-xs bg-gray-50 rounded px-1.5 py-0.5">{e.action}</code></td>
                <td className="px-6 py-3 whitespace-nowrap">{e.entity ?? '—'}{e.entityId !== null ? ` #${e.entityId}` : ''}</td>
                <td className="px-6 py-3 max-w-xs"><Value v={e.oldValue} /></td>
                <td className="px-6 py-3 max-w-xs"><Value v={e.newValue} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {entries !== null && (
        <div className="flex items-center justify-between mt-4 text-sm text-gray-500">
          <span>{entries.length} entr{entries.length === 1 ? 'y' : 'ies'} loaded</span>
          {nextBefore !== null
            ? <button className="apple-btn-secondary" onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load older'}</button>
            : <span>That is everything.</span>}
        </div>
      )}
    </Layout>
  );
}
