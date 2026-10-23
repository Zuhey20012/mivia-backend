import { useEffect, useState } from 'react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Cert = {
  id: number; scheme: string; schemeName: { en: string; fi: string }; licenceNumber: string; holderName: string;
  scope: string; componentDescription: string | null; validUntil: string; publicVerifyUrl: string | null;
  status: string; rejectionReason: string | null; evidenceUrl: string; store: { id: number; name: string };
  productCount: number; submittedAt: string; reviewedAt: string | null;
};

const apiError = (err: unknown, fallback: string) =>
  (err as { response?: { data?: { error?: string } } })?.response?.data?.error ?? fallback;

/**
 * Certificates stores submit (EU Ecolabel, Nordic Swan, GOTS, …). Only verified, unexpired ones are ever shown to
 * shoppers or used in filters. Check the licence in the scheme's own register before verifying.
 */
export default function Certificates() {
  const [status, setStatus] = useState<'PENDING' | 'VERIFIED' | 'REJECTED'>('PENDING');
  const [rows, setRows] = useState<Cert[]>([]);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const r = await api.get(`/admin/certificates?status=${status}`);
      setRows(r.data.certificates);
      setError(null);
    } catch {
      setError('Could not load certificates.');
    }
  }
  useEffect(() => { load(); }, [status]); // eslint-disable-line react-hooks/exhaustive-deps

  async function review(c: Cert, decision: 'verify' | 'reject') {
    let reason: string | undefined;
    if (decision === 'reject') {
      const r = window.prompt('Why is the certificate rejected? (shown to the store)');
      if (!r) return;
      reason = r;
    } else if (!window.confirm(`Verify ${c.schemeName.en} licence ${c.licenceNumber} held by ${c.holderName}? Check it in the scheme's register first.`)) return;
    try { await api.post(`/admin/certificates/${c.id}/review`, { decision, reason }); await load(); }
    catch (err) { alert(apiError(err, 'Could not save the decision')); }
  }

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Certificates</h1>
        <p className="text-gray-400 text-sm mt-1">Certificates replace the old self-declared "eco" flag. Verify only after checking the licence number, holder, scope and expiry in the scheme's own register.</p>
      </div>
      <div className="flex gap-2 mb-4">
        {(['PENDING', 'VERIFIED', 'REJECTED'] as const).map((s) => (
          <button key={s} className={status === s ? 'apple-btn-primary' : 'apple-btn-secondary'} onClick={() => setStatus(s)}>{s.toLowerCase()}</button>
        ))}
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}
      <div className="apple-card p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Scheme', 'Licence', 'Covers', 'Valid until', 'Store', 'Evidence', ''].map((h) => <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>)}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td className="px-6 py-6 text-gray-400" colSpan={7}>Nothing here.</td></tr>}
            {rows.map((c) => (
              <tr key={c.id} className="table-row align-top">
                <td className="px-6 py-3 font-medium">{c.schemeName.en}<p className="text-xs text-gray-400">{c.schemeName.fi}</p></td>
                <td className="px-6 py-3"><p className="font-mono">{c.licenceNumber}</p><p className="text-xs text-gray-400">{c.holderName}</p></td>
                <td className="px-6 py-3 text-xs text-gray-500">{c.scope === 'component' ? `part: ${c.componentDescription}` : 'whole product'}<p>{c.productCount} product(s)</p></td>
                <td className="px-6 py-3">{new Date(c.validUntil).toLocaleDateString('fi-FI')}</td>
                <td className="px-6 py-3">{c.store.name}<p className="text-xs text-gray-400">#{c.store.id}</p></td>
                <td className="px-6 py-3 text-xs">
                  <a className="text-blue-600" href={c.evidenceUrl} target="_blank" rel="noreferrer noopener">certificate file</a>
                  {c.publicVerifyUrl && <p><a className="text-blue-600" href={c.publicVerifyUrl} target="_blank" rel="noreferrer noopener">scheme register</a></p>}
                  {c.rejectionReason && <p className="text-red-500">{c.rejectionReason}</p>}
                </td>
                <td className="px-6 py-3 text-right whitespace-nowrap">
                  {c.status !== 'VERIFIED' && <button className="text-xs text-green-600 mr-3" onClick={() => review(c, 'verify')}>Verify</button>}
                  {c.status !== 'REJECTED' && <button className="text-xs text-red-500" onClick={() => review(c, 'reject')}>Reject</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
