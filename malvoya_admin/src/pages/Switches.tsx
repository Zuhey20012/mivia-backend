import { useCallback, useEffect, useState } from 'react';
import { ToggleRight, RefreshCw } from 'lucide-react';
import Layout from '../components/Layout';
import { Overlay, ErrorBox, NoticeBox } from '../components/Dialog';
import api from '../utils/api';
import { obj, errorText } from '../utils/parse';
import { SWITCHES, parseSwitches, type Switch, type Message } from '../utils/switches';

// Runtime switches (2.16, contract C16): GET /admin/settings → { switches: [{ key, on, message, customMessage, … }] },
// PATCH /admin/settings/:key { on, message } (backend lib/settings.ts). PlatformSetting rows, enforced by the API within 30 s (cached per
// instance), each with the message the apps show while it is in effect. Every change is audited.

const sameMessage = (a: Message, b: Message) => JSON.stringify(a) === JSON.stringify(b);

function SwitchRow({ sw, onSaved }: { sw: Switch; onSaved: (text: string) => void }) {
  const def = SWITCHES.find((s) => s.key === sw.key)!;
  const [message, setMessage] = useState<Message>(sw.message);
  const [confirming, setConfirming] = useState<boolean | null>(null); // the value being confirmed
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const stopped = sw.value === def.stopsWhen;

  const save = async (value: boolean) => {
    setBusy(true);
    setError('');
    try {
      await api.patch(`/admin/settings/${sw.key}`, { on: value, message: typeof message === 'string' ? (message.trim() || null) : message });
      setConfirming(null);
      onSaved(value === sw.value ? `${def.title}: message saved.` : `${def.title}: ${value === def.stopsWhen ? def.off.toLowerCase() : def.on.toLowerCase()} (in effect within 30 seconds).`);
    } catch (e) {
      setError(errorText(e, 'The switch could not be changed.'));
    } finally {
      setBusy(false);
    }
  };

  const msgEmpty = typeof message === 'string' ? !message.trim() : !message.en.trim() && !message.fi.trim();

  return (
    <div className={`apple-card ${stopped ? 'border-amber-200' : ''}`}>
      <div className="flex items-start justify-between gap-4 mb-2">
        <div>
          <p className="font-semibold">{def.title}</p>
          <p className="text-xs text-gray-500 max-w-md">{def.help}</p>
        </div>
        <span className={stopped ? 'badge-orange' : 'badge-green'}>{stopped ? def.off : def.on}</span>
      </div>

      <div className="mt-3 space-y-2">
        {typeof message === 'string' ? (
          <label className="text-sm block">
            <span className="block text-gray-500 mb-1">Message shown to users while {def.off.toLowerCase()}</span>
            <input className="apple-input" maxLength={300} value={message} disabled={busy}
              placeholder={sw.defaultMessage ? `Default: “${sw.defaultMessage}”` : 'e.g. “Tauko huoltotöiden vuoksi klo 22 asti / Paused for maintenance until 22:00”'} onChange={(e) => setMessage(e.target.value)} />
          </label>
        ) : (
          <>
            <label className="text-sm block">
              <span className="block text-gray-500 mb-1">Message in Finnish</span>
              <input className="apple-input" maxLength={300} value={message.fi} disabled={busy} onChange={(e) => setMessage({ ...message, fi: e.target.value })} />
            </label>
            <label className="text-sm block">
              <span className="block text-gray-500 mb-1">Message in English</span>
              <input className="apple-input" maxLength={300} value={message.en} disabled={busy} onChange={(e) => setMessage({ ...message, en: e.target.value })} />
            </label>
          </>
        )}
      </div>

      {error && <div className="mt-3"><ErrorBox>{error}</ErrorBox></div>}

      <div className="flex items-center gap-2 mt-4 flex-wrap">
        <button className={stopped ? 'apple-btn-primary' : 'apple-btn-danger'} disabled={busy}
          onClick={() => {
            const next = !sw.value;
            // Turning something off for users always asks first; turning it back on asks too for ordering
            if (next === def.stopsWhen || def.danger) setConfirming(next); else save(next);
          }}>
          {stopped ? (def.stopsWhen ? `Resume ${def.title.toLowerCase()}` : `Turn ${def.title.toLowerCase()} on`) : (def.stopsWhen ? `Pause ${def.title.toLowerCase()}` : `Turn ${def.title.toLowerCase()} off`)}
        </button>
        {!sameMessage(message, sw.message) && (
          <button className="apple-btn-secondary" disabled={busy} onClick={() => save(sw.value)}>{busy ? 'Saving…' : 'Save message'}</button>
        )}
        {(sw.updatedAt || sw.updatedBy) && (
          <span className="text-xs text-gray-400 ml-auto">Changed {sw.updatedAt ? new Date(sw.updatedAt).toLocaleString('fi-FI') : ''}{sw.updatedBy ? ` by ${sw.updatedBy}` : ''}</span>
        )}
      </div>

      {confirming !== null && (
        <Overlay title={confirming === def.stopsWhen ? `${def.off}?` : `${def.on}?`} onClose={busy ? () => undefined : () => setConfirming(null)}>
          {confirming === def.stopsWhen ? (
            <>
              <p className="text-sm text-gray-600 mb-2">{def.help}</p>
              <p className="text-sm mb-3">It takes effect on every server within 30 seconds and stays until you switch it back.</p>
              {msgEmpty
                ? (sw.defaultMessage
                  ? <p className="text-sm text-gray-500 bg-gray-50 rounded-xl px-3 py-2 mb-3">Users see the default text: “{sw.defaultMessage}”</p>
                  : <p className="text-sm text-amber-600 mb-3">No message is set: users get a generic “temporarily unavailable” text. Consider writing one first.</p>)
                : <p className="text-sm text-gray-500 bg-gray-50 rounded-xl px-3 py-2 mb-3">Users see: “{typeof message === 'string' ? message : `${message.fi} / ${message.en}`}”</p>}
            </>
          ) : (
            <p className="text-sm text-gray-600 mb-3">{def.title} works again for everyone within 30 seconds.</p>
          )}
          {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
          <div className="flex gap-2 justify-end">
            <button className="apple-btn-secondary" disabled={busy} onClick={() => setConfirming(null)}>Back</button>
            <button className={confirming === def.stopsWhen ? 'apple-btn-danger' : 'apple-btn-primary'} disabled={busy} onClick={() => save(confirming)}>
              {busy ? 'Saving…' : confirming === def.stopsWhen ? (def.stopsWhen ? `Yes, pause ${def.title.toLowerCase()}` : `Yes, turn ${def.title.toLowerCase()} off`) : 'Yes, turn it back on'}
            </button>
          </div>
        </Overlay>
      )}
    </div>
  );
}

export default function Switches() {
  const [switches, setSwitches] = useState<Switch[] | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [version, setVersion] = useState(0);

  const load = useCallback(() => api.get('/admin/settings')
    .then((r) => { setSwitches(parseSwitches(obj(r.data))); setError(''); setVersion((n) => n + 1); })
    .catch((e) => setError(errorText(e, 'Could not load the switches.'))), []);

  useEffect(() => { load(); }, [load]);

  return (
    <Layout>
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2"><ToggleRight className="w-6 h-6" /> Switches</h1>
          <p className="text-gray-500 text-sm mt-1 max-w-3xl">
            Stop parts of Malvoya at once without a deploy, for example during an outage, a courier shortage or a legal problem.
            Changes reach every server within 30 seconds, are shown in System, and are recorded in the audit log.
          </p>
        </div>
        <button className="apple-btn-secondary text-xs px-3 py-1.5 shrink-0" onClick={() => { setNotice(''); load(); }}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>

      {notice && <div className="mb-4"><NoticeBox>{notice}</NoticeBox></div>}
      {error && <div className="mb-4"><ErrorBox>{error}{switches !== null && ' Showing the last loaded state.'}</ErrorBox></div>}
      {switches === null && !error && <p className="text-gray-400 text-sm">Loading…</p>}

      {switches && (
        <div className="grid md:grid-cols-2 gap-6">
          {switches.map((s) => (
            // Re-mounted after each load so the message fields show what the API stored
            <SwitchRow key={`${s.key}-${version}`} sw={s} onSaved={(text) => { setNotice(text); load(); }} />
          ))}
        </div>
      )}
    </Layout>
  );
}
