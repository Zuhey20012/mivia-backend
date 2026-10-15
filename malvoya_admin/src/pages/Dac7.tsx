import { useEffect, useState } from 'react';
import { Download, AlertTriangle, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Quarters = { q1: number; q2: number; q3: number; q4: number; total: number };
type Seller = {
  storeId: number; storeName: string; sellerType: 'BUSINESS' | 'PRIVATE';
  identity: {
    legalName: string | null; businessId: string | null; vatNumber: string | null; dateOfBirth: string | null;
    tin: string | null; tinUnreadable: boolean;
    address: { line: string; postalCode: string; city: string; country: string } | null;
  };
  taxInfoComplete: boolean; missing: string[]; sales: number;
  considerationCents: Quarters; feesCents: Quarters; exempt: boolean;
};
type Missing = { storeId: number; storeName: string; sellerType: string; hasSales: boolean; missing: string[] };
type Report = { year: number; dueBy: string; sellers: Seller[]; reportable: number; missingTaxData: Missing[] };

const euro = (c: number) => new Intl.NumberFormat('fi-FI', { style: 'currency', currency: 'EUR' }).format(c / 100);
const FIELD: Record<string, string> = {
  legalName: 'legal name', businessId: 'Y-tunnus', dateOfBirth: 'date of birth', tin: 'tax ID', address: 'address', country: 'country',
};
const thisYear = new Date().getFullYear();

/** DAC7: sellers' identity and sales per year, for the report to Vero (due by 31 January). */
export default function Dac7() {
  const [year, setYear] = useState(thisYear - 1 >= 2026 ? thisYear - 1 : thisYear);
  const [report, setReport] = useState<Report | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);

  async function load(y = year) {
    try {
      const r = await api.get('/admin/dac7', { params: { year: y } });
      setReport(r.data);
      setError(null);
    } catch {
      setError('Could not load the DAC7 report.');
    }
  }
  useEffect(() => {
    let alive = true;
    api.get('/admin/dac7', { params: { year } })
      .then((r) => { if (alive) setReport(r.data); })
      .catch(() => { if (alive) setError('Could not load the DAC7 report.'); });
    return () => { alive = false; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // The admin API needs the bearer header, so the CSV is fetched and saved as a Blob (no token in a URL)
  async function downloadCsv() {
    setDownloading(true);
    try {
      const r = await api.get('/admin/dac7.csv', { params: { year }, responseType: 'blob' });
      const url = URL.createObjectURL(r.data as Blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `malvoya-dac7-${year}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch {
      alert('Could not download the CSV.');
    } finally { setDownloading(false); }
  }

  const years = Array.from({ length: Math.max(1, thisYear - 2025) }, (_, i) => thisYear - i);

  return (
    <Layout>
      <div style={{ marginBottom: '1.5rem', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: '1rem', flexWrap: 'wrap' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 600, letterSpacing: '-0.02em' }}>DAC7 seller report</h1>
          <p style={{ color: '#8E8E93', fontSize: '0.875rem', marginTop: '0.25rem', maxWidth: '44rem' }}>
            Platforms report each seller's identity, number of sales, and the consideration and fees per quarter to Vero once a year
            {report ? `, for ${report.year} by ${report.dueBy.split('-').reverse().join('.')}` : ''}. Consideration is what the seller was paid (sales − refunds − commission).
          </p>
        </div>
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
          <select className="apple-input" style={{ width: 'auto', padding: '0.375rem 0.75rem' }} value={year} aria-label="Year"
            onChange={(e) => { const y = Number(e.target.value); setYear(y); load(y); }}>
            {years.map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
          <button className="apple-btn-secondary" style={{ padding: '0.375rem 0.75rem', fontSize: '0.8125rem', display: 'flex', alignItems: 'center', gap: '0.375rem' }} onClick={() => load()}>
            <RefreshCw style={{ width: '13px', height: '13px' }} /> Refresh
          </button>
          <button className="apple-btn-primary" style={{ padding: '0.375rem 0.875rem', fontSize: '0.8125rem', display: 'flex', alignItems: 'center', gap: '0.375rem' }} onClick={downloadCsv} disabled={downloading}>
            <Download style={{ width: '13px', height: '13px' }} /> {downloading ? 'Preparing…' : 'Download CSV'}
          </button>
        </div>
      </div>

      {error && <div style={{ background: '#FFF1F0', color: '#B91C1C', padding: '1rem', borderRadius: '0.75rem', marginBottom: '1.5rem', fontSize: '0.875rem' }}>{error}</div>}

      {report && report.missingTaxData.length > 0 && (
        <div className="apple-card" style={{ marginBottom: '1.5rem', borderLeft: '4px solid #E08A00' }}>
          <h2 style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.75rem' }}>
            <AlertTriangle style={{ width: '16px', height: '16px', color: '#E08A00' }} /> {report.missingTaxData.length} store(s) missing tax data
          </h2>
          <p style={{ fontSize: '0.8125rem', color: '#3C3C43', marginBottom: '0.75rem' }}>
            Stores enter it in the store app (Store → Tax details). Stores with sales this year come first: they must be reported.
          </p>
          <ul style={{ display: 'flex', flexDirection: 'column', gap: '0.375rem', fontSize: '0.8125rem' }}>
            {[...report.missingTaxData].sort((a, b) => Number(b.hasSales) - Number(a.hasSales)).map((m) => (
              <li key={m.storeId}>
                <strong>{m.storeName}</strong> <span style={{ color: '#8E8E93' }}>#{m.storeId} · {m.sellerType.toLowerCase()}{m.hasSales ? ' · has sales' : ''}</span>
                {' — missing '}{m.missing.map((f) => FIELD[f] ?? f).join(', ')}
              </li>
            ))}
          </ul>
        </div>
      )}

      {report && (
        <div className="apple-card" style={{ padding: 0, overflow: 'auto' }}>
          <div style={{ padding: '1rem 1.5rem', fontSize: '0.8125rem', color: '#3C3C43' }}>
            {report.sellers.length} seller(s) with sales in {report.year} · {report.reportable} above the de-minimis (30 sales or more, or over 2 000 €), the rest are exempt.
            Tax IDs are only in the CSV.
          </div>
          <table style={{ width: '100%', fontSize: '0.8125rem', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid #F5F5F7' }}>
                {['Seller', 'Identity', 'Sales', 'Consideration Q1–Q4', 'Total', 'Fees', 'Status'].map((h) => (
                  <th key={h} style={{ textAlign: 'left', padding: '0.75rem 1rem', fontSize: '0.6875rem', fontWeight: 500, color: '#8E8E93', textTransform: 'uppercase', letterSpacing: '0.05em' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {report.sellers.length === 0 && (
                <tr><td colSpan={7} style={{ padding: '2rem', textAlign: 'center', color: '#8E8E93' }}>No sales in {report.year}.</td></tr>
              )}
              {report.sellers.map((s) => (
                <tr key={s.storeId} className="table-row">
                  <td style={{ padding: '0.75rem 1rem' }}>
                    <p style={{ fontWeight: 500 }}>{s.storeName}</p>
                    <p style={{ color: '#8E8E93', fontSize: '0.75rem' }}>#{s.storeId} · {s.sellerType === 'BUSINESS' ? 'Business' : 'Private'}</p>
                  </td>
                  <td style={{ padding: '0.75rem 1rem', fontSize: '0.75rem', color: '#3C3C43' }}>
                    <p>{s.identity.legalName ?? '—'}</p>
                    <p style={{ color: '#8E8E93' }}>
                      {s.sellerType === 'BUSINESS'
                        ? `${s.identity.businessId ?? 'no Y-tunnus'}${s.identity.vatNumber ? ` · ${s.identity.vatNumber}` : ''}`
                        : `${s.identity.dateOfBirth ?? 'no date of birth'} · ${s.identity.tin ? 'tax ID saved' : s.identity.tinUnreadable ? 'tax ID unreadable (check DATA_ENCRYPTION_KEY)' : 'no tax ID'}`}
                    </p>
                    {s.identity.address && <p style={{ color: '#8E8E93' }}>{s.identity.address.line}, {s.identity.address.postalCode} {s.identity.address.city}, {s.identity.address.country}</p>}
                  </td>
                  <td style={{ padding: '0.75rem 1rem' }}>{s.sales}</td>
                  <td style={{ padding: '0.75rem 1rem', whiteSpace: 'nowrap', fontSize: '0.75rem', color: '#3C3C43' }}>
                    {(['q1', 'q2', 'q3', 'q4'] as const).map((q) => euro(s.considerationCents[q])).join(' · ')}
                  </td>
                  <td style={{ padding: '0.75rem 1rem', whiteSpace: 'nowrap', fontWeight: 500 }}>{euro(s.considerationCents.total)}</td>
                  <td style={{ padding: '0.75rem 1rem', whiteSpace: 'nowrap' }}>{euro(s.feesCents.total)}</td>
                  <td style={{ padding: '0.75rem 1rem' }}>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.25rem', alignItems: 'flex-start' }}>
                      {s.exempt ? <span className="badge-gray">Exempt</span> : <span className="badge-blue">Reportable</span>}
                      {s.taxInfoComplete ? <span className="badge-green">Data complete</span> : <span className="badge-yellow">Missing {s.missing.map((f) => FIELD[f] ?? f).join(', ')}</span>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Layout>
  );
}
