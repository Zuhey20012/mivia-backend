import { useEffect, useState } from 'react';
import { RefreshCw, ScrollText, ExternalLink } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

// Legal texts and their versions (API 2.11). Texts are written in legal/*.md in the repository; what is in force is
// the published version. Publishing a change sets when it takes effect and tells everyone it binds.
interface Version {
  id: number; version: string; status: 'current' | 'pending' | 'superseded';
  publishedAt: string; effectiveAt: string; noticeDays: number;
  summaryEn: string; summaryFi: string;
  legalObligation: boolean; legalObligationReason: string | null;
  notifiedAt: string | null; notifiedCount: number;
  acceptances: number; url: string;
}
interface Doc {
  doc: string; title: { en: string; fi: string }; file: string; url: string;
  minNoticeDays: number; noticeRule: string; blocking: boolean; roles: string[]; affectedUsers: number;
  currentVersion: string | null; pendingVersion: string | null; fileVersion: string | null; unpublishedChange: boolean;
  versions: Version[];
  legacyAcceptances: { version: string; acceptances: number }[];
}

const DAY = 86_400_000;
const statusBadge: Record<string, string> = { current: 'badge-green', pending: 'badge-blue', superseded: 'badge-gray' };
const fmt = (d: string) => new Date(d).toLocaleString('fi-FI', { dateStyle: 'medium', timeStyle: 'short' });

/** datetime-local value (local time) for a moment */
function localInput(ms: number) {
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function PublishForm({ doc, onDone }: { doc: Doc; onDone: () => void }) {
  // The moment the form opened: notice is counted from it (refreshed on each change of the date)
  const [openedAt, setOpenedAt] = useState(() => Date.now());
  const [effective, setEffective] = useState(() => localInput(openedAt + doc.minNoticeDays * DAY + 3_600_000));
  const [summaryEn, setSummaryEn] = useState('');
  const [summaryFi, setSummaryFi] = useState('');
  const [legal, setLegal] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const days = (new Date(effective).getTime() - openedAt) / DAY;
  const tooShort = !legal && days < doc.minNoticeDays;
  const termsWarning = doc.doc === 'terms' && days < 30;

  const submit = async () => {
    setError('');
    if (!confirm(`Publish the new ${doc.title.en}? Everyone it binds (${doc.affectedUsers} accounts) is told by push and email, and it takes effect ${fmt(new Date(effective).toISOString())}.`)) return;
    setBusy(true);
    try {
      await api.post(`/admin/legal/${doc.doc}/publish`, {
        effectiveAt: new Date(effective).toISOString(), summaryEn, summaryFi,
        ...(legal ? { legalObligation: true, reason } : {}),
      });
      onDone();
    } catch (e: unknown) {
      const msg = (e as { response?: { data?: { error?: string } } }).response?.data?.error;
      setError(msg || 'Publishing failed.');
    } finally { setBusy(false); }
  };

  return (
    <div style={{ marginTop: '1rem', padding: '1rem', borderRadius: '12px', background: '#FAFAFC', border: '1px solid #E5E5EA' }}>
      <p style={{ fontWeight: 600, marginBottom: '0.25rem' }}>Publish the change in {doc.file}</p>
      <p style={{ fontSize: '0.75rem', color: '#6E6E73', marginBottom: '0.75rem' }}>
        Notice rule: {doc.noticeRule} New version: <code>{doc.fileVersion}</code>
      </p>
      <label style={{ fontSize: '0.8125rem', display: 'block', marginBottom: '0.5rem' }}>
        Takes effect
        <input type="datetime-local" className="apple-input" value={effective} onChange={e => { setEffective(e.target.value); setOpenedAt(e.timeStamp + performance.timeOrigin); }} style={{ marginTop: '0.25rem' }} />
      </label>
      <p style={{ fontSize: '0.75rem', color: tooShort ? '#D93025' : '#6E6E73', marginBottom: '0.5rem' }}>
        {Math.max(0, Math.floor(days))} days' notice{tooShort ? ` — at least ${doc.minNoticeDays} days needed unless the law requires the change` : ''}
        {termsWarning && !tooShort ? ' — the Terms promise 30 days for changes to the customer\'s disadvantage' : ''}
      </p>
      <label style={{ fontSize: '0.8125rem', display: 'block', marginBottom: '0.5rem' }}>
        What changes (English)
        <textarea className="apple-input" rows={2} value={summaryEn} onChange={e => setSummaryEn(e.target.value)} style={{ marginTop: '0.25rem' }} />
      </label>
      <label style={{ fontSize: '0.8125rem', display: 'block', marginBottom: '0.5rem' }}>
        Mikä muuttuu (suomeksi)
        <textarea className="apple-input" rows={2} value={summaryFi} onChange={e => setSummaryFi(e.target.value)} style={{ marginTop: '0.25rem' }} />
      </label>
      <label style={{ fontSize: '0.8125rem', display: 'flex', gap: '0.5rem', alignItems: 'center', marginBottom: '0.5rem' }}>
        <input type="checkbox" checked={legal} onChange={e => setLegal(e.target.checked)} />
        The law requires this change (shorter notice allowed; the reason is kept in the audit log)
      </label>
      {legal && (
        <input className="apple-input" placeholder="Which law or authority requires it" value={reason} onChange={e => setReason(e.target.value)} style={{ marginBottom: '0.5rem' }} />
      )}
      {error && <p style={{ color: '#D93025', fontSize: '0.8125rem', marginBottom: '0.5rem' }}>{error}</p>}
      <button className="apple-btn-primary" disabled={busy || tooShort || summaryEn.trim().length < 10 || summaryFi.trim().length < 10 || (legal && reason.trim().length < 10)} onClick={submit}>
        {busy ? 'Publishing…' : 'Publish and notify'}
      </button>
    </div>
  );
}

export default function Legal() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    try { const r = await api.get('/admin/legal'); setDocs(r.data.docs); }
    catch { /* silent */ }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  return (
    <Layout>
      <div style={{ marginBottom: '2rem', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 600, letterSpacing: '-0.02em' }}>Legal</h1>
          <p style={{ color: '#8E8E93', fontSize: '0.875rem', marginTop: '0.25rem' }}>
            Versions of the terms, agreements and privacy policy. A deploy never changes what is in force: publish a change here.
          </p>
        </div>
        <button onClick={load} style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', color: '#0071E3', fontSize: '0.875rem', fontWeight: 500, background: 'none', border: 'none', cursor: 'pointer' }}>
          <RefreshCw style={{ width: '14px', height: '14px' }} /> Refresh
        </button>
      </div>

      {loading ? (
        <div className="apple-card" style={{ padding: '3rem', textAlign: 'center', color: '#8E8E93' }}>Loading…</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
          {docs.map(d => (
            <div key={d.doc} className="apple-card">
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: '1rem', flexWrap: 'wrap' }}>
                <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
                  <ScrollText style={{ width: '20px', height: '20px', color: '#6D2E8C' }} />
                  <div>
                    <p style={{ fontWeight: 600 }}>{d.title.en} <span style={{ color: '#8E8E93', fontWeight: 400 }}>/ {d.title.fi}</span></p>
                    <p style={{ fontSize: '0.75rem', color: '#6E6E73' }}>
                      Binds {d.roles.join(', ').toLowerCase()} ({d.affectedUsers} accounts) · minimum notice {d.minNoticeDays} days
                      {d.blocking ? ' · must be accepted before ordering / selling / delivering' : ' · acknowledged, never blocks'}
                    </p>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
                  {d.pendingVersion && <span className="badge-blue">Change announced</span>}
                  {d.unpublishedChange && <span className="badge-yellow" title="The file in the repository differs from every published version">Unpublished change in {d.file}</span>}
                  <a href={d.url} target="_blank" rel="noreferrer" style={{ color: '#0071E3', fontSize: '0.8125rem', display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                    Public page <ExternalLink style={{ width: '12px', height: '12px' }} />
                  </a>
                </div>
              </div>

              <div style={{ overflowX: 'auto', marginTop: '1rem' }}>
                <table style={{ width: '100%', fontSize: '0.8125rem', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid #F5F5F7', color: '#8E8E93', textAlign: 'left' }}>
                      {['Version', 'Status', 'Published', 'In effect from', 'Notice', 'Summary', 'Accepted by', 'Notified'].map(h => <th key={h} style={{ padding: '0.5rem', fontWeight: 500 }}>{h}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {d.versions.map(v => (
                      <tr key={v.id} className="table-row">
                        <td style={{ padding: '0.5rem' }}><a href={v.url} target="_blank" rel="noreferrer" style={{ color: '#0071E3' }}><code>{v.version.split('@')[1]}</code></a></td>
                        <td style={{ padding: '0.5rem' }}><span className={statusBadge[v.status]}>{v.status}</span></td>
                        <td style={{ padding: '0.5rem', whiteSpace: 'nowrap' }}>{fmt(v.publishedAt)}</td>
                        <td style={{ padding: '0.5rem', whiteSpace: 'nowrap' }}>{fmt(v.effectiveAt)}</td>
                        <td style={{ padding: '0.5rem', whiteSpace: 'nowrap' }}>
                          {v.noticeDays} d{v.legalObligation && <span className="badge-orange" style={{ marginLeft: '0.25rem' }} title={v.legalObligationReason ?? ''}>required by law</span>}
                        </td>
                        <td style={{ padding: '0.5rem', maxWidth: '320px' }} title={v.summaryFi}>{v.summaryEn}</td>
                        <td style={{ padding: '0.5rem' }}>{v.acceptances}</td>
                        <td style={{ padding: '0.5rem', whiteSpace: 'nowrap' }}>{v.notifiedAt ? `${v.notifiedCount} emails` : '—'}</td>
                      </tr>
                    ))}
                    {d.legacyAcceptances.map(l => (
                      <tr key={l.version} className="table-row" style={{ color: '#8E8E93' }}>
                        <td style={{ padding: '0.5rem' }}><code>{l.version.split('@')[1]}</code></td>
                        <td style={{ padding: '0.5rem' }} colSpan={5}>accepted before 2.11 (text not stored)</td>
                        <td style={{ padding: '0.5rem' }}>{l.acceptances}</td>
                        <td />
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {d.unpublishedChange && !d.pendingVersion && (
                open === d.doc
                  ? <PublishForm doc={d} onDone={() => { setOpen(null); load(); }} />
                  : <button className="apple-btn-primary" style={{ marginTop: '1rem' }} onClick={() => setOpen(d.doc)}>Publish this change…</button>
              )}
              {d.unpublishedChange && d.pendingVersion && (
                <p style={{ fontSize: '0.75rem', color: '#6E6E73', marginTop: '0.75rem' }}>Another change can be published once the announced one has taken effect.</p>
              )}
            </div>
          ))}
        </div>
      )}
    </Layout>
  );
}
