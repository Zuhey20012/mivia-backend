import { useEffect, useState } from 'react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Issue = { field: string; code: string; message: { en: string; fi: string } };
type Claim = { field: string; term: string; blocking: boolean; message: { en: string; fi: string } };
type Report = {
  id: number; reason: string; details: string | null; status: string; createdAt: string; dueBy: string; overdue: boolean;
  reporter: { signedIn: boolean; userId: number | null; email: string | null };
  resolution: string | null; resolutionNote: string | null; resolvedAt: string | null;
  product: { id: number; name: string; isAvailable: boolean; lockedReason: string | null; store: { id: number; name: string }; claims: Claim[] };
};
type Compliance = {
  id: number; name: string; categorySlug: string | null; template: string | null; isAvailable: boolean;
  claims: Claim[]; publishCheck: { ready: boolean; missing: Issue[]; warnings: Issue[] };
  safety: { manufacturer: { name: string } | null; responsiblePerson: { name: string } | null; productModel: string | null; gtin: string | null };
  store: { id: number; name: string; sellerType: string };
};

const apiError = (err: unknown, fallback: string) =>
  (err as { response?: { data?: { error?: string } } })?.response?.data?.error ?? fallback;
const when = (iso: string) => new Date(iso).toLocaleString('fi-FI');

/**
 * "Report this product" notices (DSA Art. 16). Product-safety notices are decided within three working days
 * (GPSR Art. 22(8)). Removing a listing locks it and sends the store a statement of reasons; the reporter hears the outcome.
 */
export default function ProductReports() {
  const [status, setStatus] = useState<'OPEN' | 'ACTIONED' | 'DISMISSED'>('OPEN');
  const [rows, setRows] = useState<Report[]>([]);
  const [open, setOpen] = useState<Compliance | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const r = await api.get(`/admin/product-reports?status=${status}`);
      setRows(r.data.reports);
      setError(null);
    } catch {
      setError('Could not load reports.');
    }
  }
  useEffect(() => { load(); }, [status]); // eslint-disable-line react-hooks/exhaustive-deps

  async function resolve(r: Report, action: 'dismiss' | 'remove_listing') {
    const note = window.prompt(action === 'remove_listing'
      ? 'Statement of reasons for the store (why the listing is removed):'
      : 'Why is the listing kept? (sent to the reporter)');
    if (!note || note.trim().length < 5) return;
    try { await api.post(`/admin/product-reports/${r.id}/resolve`, { action, note }); await load(); }
    catch (err) { alert(apiError(err, 'Could not save the decision')); }
  }

  async function showProduct(id: number) {
    try { setOpen((await api.get(`/admin/products/${id}`)).data.product); }
    catch (err) { alert(apiError(err, 'Could not load the product')); }
  }

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Product reports</h1>
        <p className="text-gray-400 text-sm mt-1">Reports from shoppers (unsafe, counterfeit, illegal, misleading, other). Decide product-safety reports within three working days.</p>
      </div>
      <div className="flex gap-2 mb-4">
        {(['OPEN', 'ACTIONED', 'DISMISSED'] as const).map((s) => (
          <button key={s} className={status === s ? 'apple-btn-primary' : 'apple-btn-secondary'} onClick={() => setStatus(s)}>{s.toLowerCase()}</button>
        ))}
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}
      <div className="apple-card p-0 overflow-hidden mb-6">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Product', 'Reason', 'Reporter', 'Received / due', 'Claims checker', ''].map((h) => <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>)}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td className="px-6 py-6 text-gray-400" colSpan={6}>Nothing here.</td></tr>}
            {rows.map((r) => (
              <tr key={r.id} className="table-row align-top">
                <td className="px-6 py-3">
                  <button className="font-medium text-blue-600 text-left" onClick={() => showProduct(r.product.id)}>{r.product.name}</button>
                  <p className="text-xs text-gray-400">{r.product.store.name} · {r.product.isAvailable ? 'visible' : r.product.lockedReason ? `locked (${r.product.lockedReason.toLowerCase()})` : 'hidden'}</p>
                </td>
                <td className="px-6 py-3"><span className={r.reason === 'unsafe' ? 'badge-red' : 'badge-yellow'}>{r.reason}</span>{r.details && <p className="text-xs text-gray-500 mt-1 max-w-xs">{r.details}</p>}</td>
                <td className="px-6 py-3 text-xs text-gray-500">{r.reporter.signedIn ? `user #${r.reporter.userId}` : r.reporter.email ?? 'anonymous'}</td>
                <td className="px-6 py-3 text-xs">{when(r.createdAt)}<p className={r.overdue ? 'text-red-500 font-medium' : 'text-gray-400'}>due {when(r.dueBy)}</p>
                  {r.resolutionNote && <p className="text-gray-500 mt-1">{r.resolution}: {r.resolutionNote}</p>}</td>
                <td className="px-6 py-3 text-xs">{r.product.claims.length === 0 ? <span className="text-gray-400">no flagged words</span> : r.product.claims.map((c, i) => (
                  <p key={i} className={c.blocking ? 'text-red-500' : 'text-yellow-600'}>"{c.term}" in {c.field}</p>
                ))}</td>
                <td className="px-6 py-3 text-right whitespace-nowrap">
                  {r.status === 'OPEN' && <>
                    <button className="text-xs text-gray-600 mr-3" onClick={() => resolve(r, 'dismiss')}>Keep listing</button>
                    <button className="text-xs text-red-500" onClick={() => resolve(r, 'remove_listing')}>Remove listing</button>
                  </>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {open && (
        <div className="apple-card">
          <div className="flex justify-between items-start mb-3">
            <div>
              <h2 className="font-semibold">{open.name} <span className="text-xs text-gray-400">#{open.id}</span></h2>
              <p className="text-xs text-gray-400">{open.store.name} ({open.store.sellerType.toLowerCase()} seller) · {open.categorySlug ?? 'no category'} · {open.template ?? '—'} · {open.isAvailable ? 'visible' : 'hidden'}</p>
            </div>
            <button className="text-xs text-gray-500" onClick={() => setOpen(null)}>Close</button>
          </div>
          <p className="text-sm mb-2"><strong>Manufacturer:</strong> {open.safety.manufacturer?.name ?? '—'} · <strong>EU responsible person:</strong> {open.safety.responsiblePerson?.name ?? '—'} · <strong>Model:</strong> {open.safety.productModel ?? '—'} · <strong>EAN:</strong> {open.safety.gtin ?? '—'}</p>
          <h3 className="text-sm font-semibold mt-3">Claims checker</h3>
          {open.claims.length === 0 ? <p className="text-xs text-gray-400">No generic environmental claims found.</p> : open.claims.map((c, i) => (
            <p key={i} className={`text-xs ${c.blocking ? 'text-red-500' : 'text-yellow-600'}`}>"{c.term}" ({c.field}): {c.message.en}</p>
          ))}
          <h3 className="text-sm font-semibold mt-3">Publishing check {open.publishCheck.ready ? '(complete)' : '(missing information)'}</h3>
          {open.publishCheck.missing.map((m, i) => <p key={i} className="text-xs text-red-500">{m.field}: {m.message.en}</p>)}
          {open.publishCheck.warnings.map((m, i) => <p key={i} className="text-xs text-yellow-600">{m.field}: {m.message.en}</p>)}
        </div>
      )}
    </Layout>
  );
}
