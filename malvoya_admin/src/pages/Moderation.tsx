import { useEffect, useState } from 'react';
import { Flag, Play, EyeOff, RotateCcw, MessageSquare } from 'lucide-react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Drop = {
  id: number;
  kind: 'VIDEO' | 'IMAGE';
  caption: string | null;
  status: 'PROCESSING' | 'READY' | 'FAILED' | 'REMOVED';
  media: { poster: string | null; mp4: string | null; image: string | null };
  likeCount: number;
  viewCount: number;
  openReports: number;
  removedReason: string | null;
  store: { id: number; name: string };
  product: { name: string };
};

type Report = {
  id: number;
  reason: string;
  details: string | null;
  createdAt: string;
  reporterId: number | null;
  drop: { id: number; status: string; caption: string | null; store: { name: string } };
};

type ReportedComment = {
  id: number;
  dropId: number;
  body: string;
  status: 'VISIBLE' | 'HIDDEN';
  reportCount: number;
  createdAt: string;
  user: { id: number; name: string };
  reports: { reason: string; createdAt: string }[];
};

const STATUSES = ['READY', 'REMOVED', 'PROCESSING', 'FAILED'] as const;

/**
 * Notice-and-action (Digital Services Act): every report is reviewed by a person, and removing a
 * drop sends the store a statement of reasons with how to object.
 */
export default function Moderation() {
  const [reports, setReports] = useState<Report[]>([]);
  const [drops, setDrops] = useState<Drop[]>([]);
  const [comments, setComments] = useState<ReportedComment[]>([]);
  const [status, setStatus] = useState<(typeof STATUSES)[number]>('READY');
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setError(null);
    try {
      const [r, d, c] = await Promise.all([api.get('/admin/reports'), api.get(`/admin/drops?status=${status}`), api.get('/admin/comments/reported')]);
      setReports(r.data.reports);
      setDrops(d.data.drops);
      setComments(c.data.comments);
    } catch {
      setError('Could not load moderation data.');
    }
  }

  useEffect(() => { load(); }, [status]);

  async function remove(dropId: number) {
    const reason = prompt('Reason shown to the store (at least 10 characters). Name the rule or law it breaks.');
    if (!reason) return;
    try { await api.patch(`/admin/drops/${dropId}`, { action: 'remove', reason }); await load(); }
    catch (e: any) { alert(e.response?.data?.error ?? 'Removal failed'); }
  }

  async function restore(dropId: number) {
    if (!confirm('Restore this drop and dismiss its open reports?')) return;
    try { await api.patch(`/admin/drops/${dropId}`, { action: 'restore' }); await load(); }
    catch { alert('Restore failed'); }
  }

  async function moderateComment(commentId: number, action: 'remove' | 'restore') {
    try { await api.post(`/admin/comments/${commentId}`, { action }); await load(); }
    catch { alert(action === 'remove' ? 'Could not remove the comment' : 'Could not restore the comment'); }
  }

  async function dismiss(reportId: number) {
    try { await api.patch(`/admin/reports/${reportId}`, { status: 'DISMISSED' }); await load(); }
    catch { alert('Could not dismiss'); }
  }

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Moderation</h1>
        <p className="text-gray-400 text-sm mt-1">Reports from users and every drop in the feed. Three reports from different users hide a drop until you review it.</p>
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}

      <div className="apple-card mb-6">
        <h2 className="font-semibold mb-4 flex items-center gap-2"><Flag className="w-4 h-4" /> Open reports ({reports.length})</h2>
        {reports.length === 0 ? <p className="text-gray-400 text-sm">Nothing to review.</p> : (
          <table className="w-full text-sm">
            <tbody>
              {reports.map(r => (
                <tr key={r.id} className="table-row">
                  <td className="py-3 pr-4"><span className="badge-red">{r.reason}</span></td>
                  <td className="py-3 pr-4">
                    <p className="font-medium">Drop #{r.drop.id} · {r.drop.store.name}</p>
                    <p className="text-gray-400 text-xs">{r.details ?? r.drop.caption ?? ''}</p>
                  </td>
                  <td className="py-3 pr-4 text-gray-400 text-xs">{new Date(r.createdAt).toLocaleString('fi-FI')}{r.reporterId ? '' : ' · anonymous'}</td>
                  <td className="py-3 text-right whitespace-nowrap">
                    <button className="apple-btn-danger text-xs px-3 py-1.5 mr-2" onClick={() => remove(r.drop.id)}>Remove drop</button>
                    <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => dismiss(r.id)}>Dismiss</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="apple-card mb-6">
        <h2 className="font-semibold mb-1 flex items-center gap-2"><MessageSquare className="w-4 h-4" /> Reported comments ({comments.length})</h2>
        <p className="text-gray-400 text-xs mb-4">Three reports from different users hide a comment until you decide. Restoring makes it visible again and clears its reports.</p>
        {comments.length === 0 ? <p className="text-gray-400 text-sm">Nothing to review.</p> : (
          <table className="w-full text-sm">
            <tbody>
              {comments.map(c => (
                <tr key={c.id} className="table-row">
                  <td className="py-3 pr-4 whitespace-nowrap">
                    {[...new Set(c.reports.map(r => r.reason))].map(reason => <span key={reason} className="badge-red mr-1">{reason}</span>)}
                  </td>
                  <td className="py-3 pr-4">
                    <p className="font-medium">{c.body}</p>
                    <p className="text-gray-400 text-xs">Drop #{c.dropId} · by user #{c.user.id} · {c.reportCount} reports · {c.status === 'HIDDEN' ? 'hidden' : 'visible'}</p>
                  </td>
                  <td className="py-3 pr-4 text-gray-400 text-xs">{new Date(c.createdAt).toLocaleString('fi-FI')}</td>
                  <td className="py-3 text-right whitespace-nowrap">
                    <button className="apple-btn-danger text-xs px-3 py-1.5 mr-2" onClick={() => moderateComment(c.id, 'remove')}>Remove</button>
                    {c.status === 'HIDDEN' && <button className="apple-btn-secondary text-xs px-3 py-1.5" onClick={() => moderateComment(c.id, 'restore')}>Restore</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="flex gap-2 mb-4">
        {STATUSES.map(s => (
          <button key={s} className={s === status ? 'apple-btn-primary text-xs px-3 py-1.5' : 'apple-btn-secondary text-xs px-3 py-1.5'} onClick={() => setStatus(s)}>{s}</button>
        ))}
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {drops.map(d => (
          <div key={d.id} className="apple-card p-3">
            <div className="relative aspect-[9/16] rounded-xl overflow-hidden bg-gray-100 mb-3">
              {d.kind === 'VIDEO' && d.media.mp4 && d.status === 'READY'
                ? <video src={d.media.mp4} poster={d.media.poster ?? undefined} controls muted className="w-full h-full object-cover" />
                : d.media.poster ? <img src={d.media.poster} alt="" className="w-full h-full object-cover" /> : <Play className="w-8 h-8 m-auto mt-24 text-gray-300" />}
              {d.openReports > 0 && <span className="absolute top-2 left-2 badge-red">{d.openReports} reports</span>}
            </div>
            <p className="font-medium text-sm">{d.store.name}</p>
            <p className="text-gray-400 text-xs">{d.product.name} · {d.viewCount} views · {d.likeCount} likes</p>
            {d.caption && <p className="text-xs mt-1 line-clamp-2">{d.caption}</p>}
            {d.removedReason && <p className="text-xs text-red-500 mt-1">{d.removedReason}</p>}
            <div className="mt-3">
              {d.status === 'READY' && <button className="apple-btn-danger text-xs px-3 py-1.5 w-full" onClick={() => remove(d.id)}><EyeOff className="w-3 h-3 mr-1" />Remove</button>}
              {d.status === 'REMOVED' && d.removedReason !== 'Deleted by store' && <button className="apple-btn-secondary text-xs px-3 py-1.5 w-full" onClick={() => restore(d.id)}><RotateCcw className="w-3 h-3 mr-1" />Restore</button>}
            </div>
          </div>
        ))}
        {drops.length === 0 && <p className="text-gray-400 text-sm col-span-4">No drops with status {status}.</p>}
      </div>
    </Layout>
  );
}
