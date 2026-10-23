import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Recall = {
  id: number; title: string; status: 'ACTIVE' | 'CLOSED'; publishedAt: string; closedAt: string | null; url: string;
  hazard: { fi: string; en: string }; remedies: string[]; contact: string;
  products: { id: number; name: string; brand: string | null; productModel: string | null; gtin: string | null; storeName: string; matchedBy: string }[];
  buyersNotifiedAt: string | null; notifiedUsers: number;
};

const apiError = (err: unknown, fallback: string) => {
  const d = (err as { response?: { data?: { error?: string; fields?: { message: { en: string } }[] } } })?.response?.data;
  return d?.fields?.length ? d.fields.map((f) => f.message.en).join('\n') : d?.error ?? fallback;
};

const EMPTY = { productIds: '', title: '', reasonFi: '', reasonEn: '', reasonSv: '', remedyFi: '', remedyEn: '', contact: '', repair: false, replacement: false, refund: true };

/**
 * Product safety recalls (GPSR Art. 22(12), 35-37). Creating one locks the products and every identical listing
 * (same EAN, or same brand + model), tells the stores why and notifies every buyer directly by push and email in the
 * legal "Product safety recall" format. Public at /recalls.
 */
export default function Recalls() {
  const [rows, setRows] = useState<Recall[]>([]);
  const [form, setForm] = useState(EMPTY);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function load() {
    try { setRows((await api.get('/admin/recalls')).data.recalls); setError(null); }
    catch { setError('Could not load recalls.'); }
  }
  useEffect(() => { load(); }, []);

  async function create(e: FormEvent) {
    e.preventDefault();
    const productIds = form.productIds.split(/[\s,]+/).map(Number).filter((n) => Number.isInteger(n) && n > 0);
    const remedies = (['repair', 'replacement', 'refund'] as const).filter((k) => form[k]);
    if (!productIds.length) { setError('Give at least one product id.'); return; }
    if (!window.confirm(`Lock ${productIds.length} product(s) and every identical listing, and notify every buyer now?`)) return;
    setSaving(true);
    try {
      const r = await api.post('/admin/recalls', {
        productIds, remedies, title: form.title.trim() || undefined,
        reasonFi: form.reasonFi, reasonEn: form.reasonEn, reasonSv: form.reasonSv.trim() || undefined,
        remedyFi: form.remedyFi, remedyEn: form.remedyEn, contact: form.contact,
      });
      alert(`Recall created: ${r.data.locked} listing(s) locked (${r.data.identical} identical). Buyers are being notified.`);
      setForm(EMPTY);
      await load();
    } catch (err) {
      setError(apiError(err, 'Could not create the recall.'));
    } finally { setSaving(false); }
  }

  async function setStatus(r: Recall, status: 'ACTIVE' | 'CLOSED') {
    try { await api.patch(`/admin/recalls/${r.id}`, { status }); await load(); }
    catch (err) { alert(apiError(err, 'Could not change the status')); }
  }

  const set = (k: keyof typeof EMPTY) => (e: { target: { value: string } }) => setForm({ ...form, [k]: e.target.value });
  const label = 'block text-xs font-medium text-gray-500 mb-1';

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Recalls</h1>
        <p className="text-gray-400 text-sm mt-1">Describe the hazard plainly (no "voluntary", "precautionary", "in rare cases" or "no accidents reported"). Also notify the authorities through the EU Safety Business Gateway.</p>
      </div>

      <form onSubmit={create} className="apple-card mb-6">
        <h2 className="font-semibold mb-4">New recall</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={label}>Product ids (comma separated)</label><input className="apple-input" required value={form.productIds} onChange={set('productIds')} /></div>
          <div><label className={label}>Title (optional: brand, product, model)</label><input className="apple-input" maxLength={160} value={form.title} onChange={set('title')} /></div>
          <div><label className={label}>Hazard (Finnish)</label><textarea className="apple-input" required minLength={10} rows={3} value={form.reasonFi} onChange={set('reasonFi')} /></div>
          <div><label className={label}>Hazard (English)</label><textarea className="apple-input" required minLength={10} rows={3} value={form.reasonEn} onChange={set('reasonEn')} /></div>
          <div><label className={label}>What to do / remedy (Finnish)</label><textarea className="apple-input" required minLength={5} rows={3} value={form.remedyFi} onChange={set('remedyFi')} /></div>
          <div><label className={label}>What to do / remedy (English)</label><textarea className="apple-input" required minLength={5} rows={3} value={form.remedyEn} onChange={set('remedyEn')} /></div>
          <div><label className={label}>Hazard (Swedish, optional)</label><textarea className="apple-input" rows={2} value={form.reasonSv} onChange={set('reasonSv')} /></div>
          <div><label className={label}>Contact (free phone number or online service)</label><input className="apple-input" required minLength={5} maxLength={200} value={form.contact} onChange={set('contact')} /></div>
        </div>
        <div className="flex items-center justify-between mt-4">
          <div className="flex gap-4 text-sm text-gray-600">
            {(['repair', 'replacement', 'refund'] as const).map((k) => (
              <label key={k} className="flex items-center gap-2"><input type="checkbox" checked={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.checked })} />{k}</label>
            ))}
          </div>
          <button type="submit" className="apple-btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Create recall'}</button>
        </div>
      </form>

      {error && <p className="text-red-500 text-sm mb-4 whitespace-pre-line">{error}</p>}

      <div className="apple-card p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Recall', 'Products', 'Buyers told', 'Status', ''].map((h) => <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>)}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td className="px-6 py-6 text-gray-400" colSpan={5}>No recalls.</td></tr>}
            {rows.map((r) => (
              <tr key={r.id} className="table-row align-top">
                <td className="px-6 py-3"><a className="font-medium text-blue-600" href={r.url} target="_blank" rel="noreferrer noopener">{r.title}</a>
                  <p className="text-xs text-gray-400">{new Date(r.publishedAt).toLocaleDateString('fi-FI')} · {r.remedies.join(', ')}</p></td>
                <td className="px-6 py-3 text-xs text-gray-500">{r.products.map((p) => <p key={p.id}>#{p.id} {p.name} · {p.storeName} <span className="text-gray-400">({p.matchedBy})</span></p>)}</td>
                <td className="px-6 py-3">{r.notifiedUsers}<p className="text-xs text-gray-400">{r.buyersNotifiedAt ? new Date(r.buyersNotifiedAt).toLocaleString('fi-FI') : 'sending…'}</p></td>
                <td className="px-6 py-3"><span className={r.status === 'ACTIVE' ? 'badge-red' : 'badge-gray'}>{r.status.toLowerCase()}</span></td>
                <td className="px-6 py-3 text-right">
                  {r.status === 'ACTIVE'
                    ? <button className="text-xs text-gray-600" onClick={() => setStatus(r, 'CLOSED')}>Close</button>
                    : <button className="text-xs text-gray-600" onClick={() => setStatus(r, 'ACTIVE')}>Reopen</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
