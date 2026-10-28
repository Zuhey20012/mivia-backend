import { useEffect, useRef, useState } from 'react';
import { Music, Upload, Pencil } from 'lucide-react';
import { isAxiosError } from 'axios';
import Layout from '../components/Layout';
import api from '../utils/api';

// GET /admin/sounds (2.14): the licensed music library stores can add to their drops
type Sound = {
  id: number;
  title: string;
  artist: string | null;
  publicId: string;
  durationSec: number;
  licence: string;
  licenceUrl: string | null;
  active: boolean;
  useCount: number;
  createdAt: string;
  url: string;
};

type Signed = { kind: string; publicId: string; resourceType: string; uploadUrl: string; params: Record<string, string | number> };

const MAX_BYTES = 20 * 1024 * 1024;

const errorText = (e: unknown, fallback: string): string =>
  (isAxiosError(e) && typeof e.response?.data?.error === 'string' && e.response.data.error) ||
  (e instanceof Error && e.message) ||
  fallback;

const duration = (sec: number) => {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

const isHttps = (url: string) => {
  try { return new URL(url).protocol === 'https:'; } catch { return false; }
};

/** Shared checks for the upload and edit forms; returns the first problem, or ''. */
function checkFields(f: { title: string; artist: string; licence: string; licenceUrl: string }): string {
  const title = f.title.trim();
  const licence = f.licence.trim();
  if (!title) return 'Give the track a title.';
  if (title.length > 100) return 'The title can be at most 100 characters.';
  if (f.artist.trim().length > 100) return 'The artist can be at most 100 characters.';
  if (licence.length < 5 || licence.length > 300) return 'Describe the licence in 5 to 300 characters: what licence and from whom.';
  if (f.licenceUrl.trim() && !isHttps(f.licenceUrl.trim())) return 'The licence link must start with https://';
  return '';
}

/** Uploads straight to Cloudinary with the server's one-time signature, reporting progress (0–100). */
function uploadToCloudinary(signed: Signed, file: File, onProgress: (pct: number) => void) {
  return new Promise<{ public_id: string; version: number; signature: string }>((resolve, reject) => {
    const form = new FormData();
    Object.entries(signed.params).forEach(([k, v]) => form.append(k, String(v)));
    form.append('file', file);
    const xhr = new XMLHttpRequest();
    xhr.open('POST', signed.uploadUrl);
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100)); };
    xhr.onload = () => {
      let body: { public_id?: string; version?: number; signature?: string; error?: { message?: string } } = {};
      try { body = JSON.parse(xhr.responseText); } catch { /* handled below */ }
      if (xhr.status >= 200 && xhr.status < 300 && body.public_id && body.version !== undefined && body.signature) {
        resolve({ public_id: body.public_id, version: body.version, signature: body.signature });
      } else {
        reject(new Error(`The upload to Cloudinary failed${body.error?.message ? `: ${body.error.message}` : ''}.`));
      }
    };
    xhr.onerror = () => reject(new Error('The upload to Cloudinary failed: check the connection and try again.'));
    xhr.send(form);
  });
}

const emptyForm = { title: '', artist: '', licence: '', licenceUrl: '', rights: false };

function UploadForm({ onCreated }: { onCreated: (s: Sound) => void }) {
  const [form, setForm] = useState(emptyForm);
  const [file, setFile] = useState<File | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setDone('');
    if (!file) return setError('Choose an audio file.');
    if (file.size > MAX_BYTES) return setError('The file is larger than 20 MB.');
    const problem = checkFields(form);
    if (problem) return setError(problem);
    if (!form.rights) return setError('Confirm that Malvoya holds a licence for commercial use of this track.');

    setBusy(true);
    try {
      const signed: Signed = (await api.post('/media/sign', { kind: 'library_sound' })).data;
      setProgress(0);
      const up = await uploadToCloudinary(signed, file, setProgress);
      const res = await api.post('/admin/sounds', {
        title: form.title.trim(),
        artist: form.artist.trim() || undefined,
        licence: form.licence.trim(),
        licenceUrl: form.licenceUrl.trim() || undefined,
        rightsConfirmed: true,
        upload: { publicId: up.public_id, version: up.version, signature: up.signature },
      });
      onCreated(res.data.sound);
      setDone(`“${res.data.sound.title}” was added to the library.`);
      setForm(emptyForm);
      setFile(null);
      if (fileRef.current) fileRef.current.value = '';
    } catch (err) {
      setError(errorText(err, 'The track could not be added. Please try again.'));
    } finally {
      setBusy(false);
      setProgress(null);
    }
  };

  return (
    <form onSubmit={submit} className="apple-card mb-6">
      <h2 className="font-semibold mb-1 flex items-center gap-2"><Upload className="w-4 h-4" /> Add a track</h2>
      <p className="text-sm text-gray-500 mb-4">Audio file up to 20 MB and 3 minutes (mp3, m4a, aac, wav, ogg, opus, flac).</p>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-3">
        <label className="text-sm md:col-span-2">
          <span className="block text-gray-500 mb-1">Audio file</span>
          <input ref={fileRef} type="file" accept="audio/*" className="text-sm" disabled={busy}
            onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        </label>
        <label className="text-sm">
          <span className="block text-gray-500 mb-1">Title *</span>
          <input className="apple-input w-full" maxLength={100} value={form.title} disabled={busy}
            onChange={(e) => setForm({ ...form, title: e.target.value })} />
        </label>
        <label className="text-sm">
          <span className="block text-gray-500 mb-1">Artist</span>
          <input className="apple-input w-full" maxLength={100} value={form.artist} disabled={busy}
            onChange={(e) => setForm({ ...form, artist: e.target.value })} />
        </label>
        <label className="text-sm md:col-span-2">
          <span className="block text-gray-500 mb-1">Licence * (what licence and from whom)</span>
          <input className="apple-input w-full" maxLength={300} value={form.licence} disabled={busy}
            placeholder="Bought from X under licence #…, commercial use"
            onChange={(e) => setForm({ ...form, licence: e.target.value })} />
        </label>
        <label className="text-sm md:col-span-2">
          <span className="block text-gray-500 mb-1">Licence link</span>
          <input className="apple-input w-full" type="url" value={form.licenceUrl} disabled={busy} placeholder="https://"
            onChange={(e) => setForm({ ...form, licenceUrl: e.target.value })} />
        </label>
      </div>
      <label className="flex items-start gap-2 text-sm mb-4">
        <input type="checkbox" className="mt-1" checked={form.rights} disabled={busy}
          onChange={(e) => setForm({ ...form, rights: e.target.checked })} />
        Malvoya holds a licence for commercial use of this track in drops
      </label>
      {progress !== null && (
        <div className="mb-3">
          <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
            <div className="h-full bg-blue-500 transition-all" style={{ width: `${progress}%` }} />
          </div>
          <p className="text-xs text-gray-400 mt-1">{progress < 100 ? `Uploading… ${progress} %` : 'Checking the file…'}</p>
        </div>
      )}
      {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3 mb-3">{error}</div>}
      {done && <div className="bg-green-50 text-green-700 text-sm rounded-xl px-4 py-3 mb-3">{done}</div>}
      <button type="submit" className="apple-btn-primary" disabled={busy}>{busy ? 'Adding…' : 'Add to library'}</button>
    </form>
  );
}

function EditRow({ sound, onSaved, onCancel }: { sound: Sound; onSaved: (s: Sound) => void; onCancel: () => void }) {
  const [form, setForm] = useState({
    title: sound.title,
    artist: sound.artist ?? '',
    licence: sound.licence,
    licenceUrl: sound.licenceUrl ?? '',
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const save = async () => {
    setError('');
    const problem = checkFields(form);
    if (problem) return setError(problem);
    // Only what changed; a cleared artist or link is sent as null
    const body: Record<string, string | null> = {};
    if (form.title.trim() !== sound.title) body.title = form.title.trim();
    if ((form.artist.trim() || null) !== sound.artist) body.artist = form.artist.trim() || null;
    if (form.licence.trim() !== sound.licence) body.licence = form.licence.trim();
    if ((form.licenceUrl.trim() || null) !== sound.licenceUrl) body.licenceUrl = form.licenceUrl.trim() || null;
    if (Object.keys(body).length === 0) return onCancel();
    setBusy(true);
    try {
      const res = await api.patch(`/admin/sounds/${sound.id}`, body);
      onSaved(res.data.sound);
    } catch (e) {
      setError(errorText(e, 'The changes could not be saved.'));
    } finally {
      setBusy(false);
    }
  };

  return (
    <tr className="bg-gray-50">
      <td colSpan={7} className="px-6 py-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-3">
          <label className="text-sm">
            <span className="block text-gray-500 mb-1">Title</span>
            <input className="apple-input w-full" maxLength={100} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
          </label>
          <label className="text-sm">
            <span className="block text-gray-500 mb-1">Artist</span>
            <input className="apple-input w-full" maxLength={100} value={form.artist} onChange={(e) => setForm({ ...form, artist: e.target.value })} />
          </label>
          <label className="text-sm md:col-span-2">
            <span className="block text-gray-500 mb-1">Licence</span>
            <input className="apple-input w-full" maxLength={300} value={form.licence} onChange={(e) => setForm({ ...form, licence: e.target.value })} />
          </label>
          <label className="text-sm md:col-span-2">
            <span className="block text-gray-500 mb-1">Licence link</span>
            <input className="apple-input w-full" type="url" placeholder="https://" value={form.licenceUrl} onChange={(e) => setForm({ ...form, licenceUrl: e.target.value })} />
          </label>
        </div>
        {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3 mb-3">{error}</div>}
        <div className="flex gap-2">
          <button className="apple-btn-primary text-xs px-3 py-1.5" disabled={busy} onClick={save}>{busy ? 'Saving…' : 'Save'}</button>
          <button className="apple-btn-secondary text-xs px-3 py-1.5" disabled={busy} onClick={onCancel}>Cancel</button>
        </div>
      </td>
    </tr>
  );
}

export default function Sounds() {
  const [sounds, setSounds] = useState<Sound[] | null>(null);
  const [loadError, setLoadError] = useState('');
  const [error, setError] = useState('');
  const [editing, setEditing] = useState<number | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);

  useEffect(() => {
    api.get('/admin/sounds')
      .then((r) => setSounds(r.data.sounds ?? []))
      .catch((e) => setLoadError(errorText(e, 'Could not load the sound library.')));
  }, []);

  const replace = (s: Sound) => setSounds((list) => (list ?? []).map((x) => (x.id === s.id ? s : x)));

  const toggle = async (s: Sound) => {
    const question = s.active
      ? `Deactivate “${s.title}”? Stores will no longer be offered it for new drops. Drops that already use it keep playing it.`
      : `Activate “${s.title}”? Stores can add it to their drops again.`;
    if (!window.confirm(question)) return;
    setError('');
    setBusyId(s.id);
    try {
      const res = await api.patch(`/admin/sounds/${s.id}`, { active: !s.active });
      replace(res.data.sound);
    } catch (e) {
      setError(errorText(e, 'The change could not be saved.'));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2"><Music className="w-6 h-6" /> Sounds</h1>
        <p className="text-gray-500 text-sm mt-1 max-w-3xl">
          The music library holds tracks Malvoya has a commercial licence for (bought licences, CC0, own recordings);
          stores can add them to their drops. Sounds a store uploads itself stay with that store and are never shared here.
        </p>
      </div>

      <UploadForm onCreated={(s) => setSounds((list) => [s, ...(list ?? [])])} />

      {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3 mb-4">{error}</div>}

      <div className="apple-card p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Track', 'Length', 'Licence', 'Uses', 'Status', 'Preview', ''].map((h) => (
                <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loadError && (
              <tr><td colSpan={7} className="px-6 py-6"><div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3">{loadError}</div></td></tr>
            )}
            {!loadError && sounds === null && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">Loading…</td></tr>}
            {sounds?.length === 0 && <tr><td colSpan={7} className="px-6 py-6 text-gray-400">The library is empty. Add the first licensed track above.</td></tr>}
            {sounds?.map((s) => (
              editing === s.id
                ? <EditRow key={s.id} sound={s} onCancel={() => setEditing(null)} onSaved={(n) => { replace(n); setEditing(null); }} />
                : (
                  <tr key={s.id} className="table-row align-top">
                    <td className="px-6 py-3">
                      <p className="font-medium">{s.title}</p>
                      <p className="text-xs text-gray-400">{s.artist || 'Unknown artist'}</p>
                    </td>
                    <td className="px-6 py-3 font-mono">{duration(s.durationSec)}</td>
                    <td className="px-6 py-3 text-xs text-gray-600 max-w-xs">
                      <p className="break-words">{s.licence}</p>
                      {s.licenceUrl && (
                        <a href={s.licenceUrl} target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">Licence</a>
                      )}
                    </td>
                    <td className="px-6 py-3">{s.useCount}</td>
                    <td className="px-6 py-3">
                      <span className={s.active ? 'badge-green' : 'badge-gray'}>{s.active ? 'active' : 'inactive'}</span>
                    </td>
                    <td className="px-6 py-3">
                      <audio controls preload="none" src={s.url} className="h-8 w-56" />
                    </td>
                    <td className="px-6 py-3 text-right whitespace-nowrap">
                      <button className="apple-btn-secondary text-xs px-3 py-1.5 mr-2" onClick={() => setEditing(s.id)} aria-label={`Edit ${s.title}`}>
                        <Pencil className="w-3 h-3" /> Edit
                      </button>
                      {s.active
                        ? <button className="apple-btn-danger text-xs px-3 py-1.5" disabled={busyId === s.id} onClick={() => toggle(s)}>Deactivate</button>
                        : <button className="apple-btn-secondary text-xs px-3 py-1.5" disabled={busyId === s.id} onClick={() => toggle(s)}>Activate</button>}
                    </td>
                  </tr>
                )
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
