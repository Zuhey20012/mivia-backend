import { useEffect, useState } from 'react';
import { ShieldCheck, ShieldAlert, KeyRound, Copy, Download } from 'lucide-react';
import QRCode from 'qrcode';
import { isAxiosError } from 'axios';
import Layout from '../components/Layout';
import api from '../utils/api';

// GET /me/mfa (2.13): two-step sign-in with an authenticator app
type Status = {
  enabled: boolean;
  enabledAt: string | null;
  required: boolean;
  pending: boolean;
  recoveryCodesLeft: number | null;
  sessionVerified: boolean;
  needsPassword: boolean;
};

const errorText = (e: unknown, fallback: string): string =>
  (isAxiosError(e) && typeof e.response?.data?.error === 'string' && e.response.data.error) || fallback;

/** The codes shown once after turning it on or renewing them: copy or save as a text file. */
function RecoveryCodes({ codes, onDone }: { codes: string[]; onDone: () => void }) {
  const text = `Malvoya admin recovery codes (each works once)\n\n${codes.join('\n')}\n`;
  const download = () => {
    const url = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = 'malvoya-recovery-codes.txt';
    a.click();
    URL.revokeObjectURL(url);
  };
  return (
    <div className="apple-card">
      <h2 className="font-semibold mb-1">Save your recovery codes</h2>
      <p className="text-sm text-gray-500 mb-4">
        If you lose your phone, each code signs you in once instead of the authenticator app. They are shown only now:
        keep them in a password manager or on paper, not on the same phone.
      </p>
      <div className="grid grid-cols-2 gap-2 font-mono text-sm bg-gray-50 rounded-xl p-4 mb-4">
        {codes.map((c) => <span key={c}>{c}</span>)}
      </div>
      <div className="flex flex-wrap gap-2">
        <button className="apple-btn-secondary" onClick={() => navigator.clipboard?.writeText(text)}>
          <Copy className="w-4 h-4" /> Copy
        </button>
        <button className="apple-btn-secondary" onClick={download}>
          <Download className="w-4 h-4" /> Download .txt
        </button>
        <button className="apple-btn-primary" onClick={onDone}>I have saved them</button>
      </div>
    </div>
  );
}

export default function Security() {
  const [status, setStatus] = useState<Status | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [setup, setSetup] = useState<{ secret: string; otpauthUrl: string; qr: string } | null>(null);
  const [codes, setCodes] = useState<string[] | null>(null);

  const load = () => api.get('/me/mfa').then((r) => setStatus(r.data));
  useEffect(() => {
    api.get('/me/mfa')
      .then((r) => setStatus(r.data))
      .catch((e) => setError(errorText(e, 'Could not load the security settings.')));
  }, []);

  const run = async (fn: () => Promise<void>) => {
    setError('');
    setBusy(true);
    try { await fn(); } catch (e) { setError(errorText(e, 'Something went wrong. Please try again.')); }
    finally { setBusy(false); }
  };

  const startSetup = () => run(async () => {
    const res = await api.post('/me/mfa/setup', { password: password || undefined });
    // The QR code is drawn here in the browser: the secret never goes to a third-party QR service
    const qr = await QRCode.toDataURL(res.data.otpauthUrl, { margin: 1, width: 220 });
    setSetup({ secret: res.data.secret, otpauthUrl: res.data.otpauthUrl, qr });
    setPassword('');
  });

  const enable = () => run(async () => {
    const res = await api.post('/me/mfa/enable', { code });
    // Turning it on ends every older session; this is the new, verified one
    localStorage.setItem('token', res.data.accessToken);
    setCodes(res.data.recoveryCodes);
    setSetup(null);
    setCode('');
    await load();
  });

  const renew = () => run(async () => {
    const res = await api.post('/me/mfa/recovery-codes', { code });
    setCodes(res.data.recoveryCodes);
    setCode('');
    await load();
  });

  const disable = () => run(async () => {
    if (!window.confirm('Turn off two-step sign-in? Signing in will only ask for your password.')) return;
    await api.post('/me/mfa/disable', { password: password || undefined, code });
    setPassword('');
    setCode('');
    await load();
  });

  const codeInput = (
    <input
      className="apple-input w-44 font-mono tracking-widest"
      inputMode="numeric"
      autoComplete="one-time-code"
      placeholder="123 456"
      value={code}
      onChange={(e) => setCode(e.target.value)}
    />
  );
  const passwordInput = status?.needsPassword && (
    <input
      type="password"
      className="apple-input w-64"
      placeholder="Your password"
      autoComplete="current-password"
      value={password}
      onChange={(e) => setPassword(e.target.value)}
    />
  );

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Security</h1>
        <p className="text-gray-400 text-sm mt-1">Two-step sign-in protects every order, payout and personal record behind this panel</p>
      </div>

      <div className="grid grid-cols-1 gap-6 max-w-2xl">
        {error && <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3">{error}</div>}

        {status && !status.enabled && status.required && (
          <div className="bg-amber-50 text-amber-800 text-sm rounded-xl px-4 py-3">
            This service requires two-step sign-in for admins. Set it up below to open the rest of the admin panel.
          </div>
        )}

        {codes && <RecoveryCodes codes={codes} onDone={() => setCodes(null)} />}

        {status && (
          <div className="apple-card">
            <div className="flex items-center gap-3 mb-5">
              <div className={`w-9 h-9 rounded-xl flex items-center justify-center ${status.enabled ? 'bg-green-50' : 'bg-amber-50'}`}>
                {status.enabled ? <ShieldCheck className="w-5 h-5 text-green-600" /> : <ShieldAlert className="w-5 h-5 text-amber-600" />}
              </div>
              <div>
                <h2 className="font-semibold">Two-step sign-in: {status.enabled ? 'on' : 'off'}</h2>
                <p className="text-xs text-gray-400">
                  {status.enabled
                    ? `Since ${new Date(status.enabledAt!).toLocaleDateString()} · ${status.recoveryCodesLeft} recovery code(s) left`
                    : 'Signing in asks only for your password'}
                </p>
              </div>
            </div>

            {!status.enabled && !setup && (
              <>
                <p className="text-sm text-gray-500 mb-4">
                  You need an authenticator app on your phone, for example Google Authenticator, Microsoft Authenticator or 1Password.
                  {status.needsPassword && ' Enter your password to start.'}
                </p>
                <div className="flex flex-wrap items-center gap-3">
                  {passwordInput}
                  <button className="apple-btn-primary" disabled={busy || (status.needsPassword && !password)} onClick={startSetup}>
                    <KeyRound className="w-4 h-4" /> Set up
                  </button>
                </div>
              </>
            )}

            {!status.enabled && setup && (
              <>
                <ol className="text-sm text-gray-600 list-decimal pl-5 mb-4 space-y-1">
                  <li>In the authenticator app, add an account and scan this code.</li>
                  <li>Enter the 6-digit code the app shows.</li>
                </ol>
                <div className="flex flex-col sm:flex-row gap-6 items-start mb-4">
                  <img src={setup.qr} alt="QR code for the authenticator app" width={220} height={220} className="rounded-xl border border-gray-100" />
                  <div className="text-sm text-gray-500">
                    <p className="mb-1">Can't scan? Enter this key in the app:</p>
                    <p className="font-mono text-gray-800 break-all select-all">{setup.secret.replace(/(.{4})/g, '$1 ').trim()}</p>
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-3">
                  {codeInput}
                  <button className="apple-btn-primary" disabled={busy || code.replace(/\D/g, '').length !== 6} onClick={enable}>Turn on</button>
                </div>
              </>
            )}

            {status.enabled && (
              <div className="flex flex-col gap-5">
                <div>
                  <p className="text-sm font-medium mb-1">New recovery codes</p>
                  <p className="text-xs text-gray-400 mb-3">Your earlier codes stop working. Enter a current code from the app.</p>
                  <div className="flex flex-wrap items-center gap-3">
                    {codeInput}
                    <button className="apple-btn-secondary" disabled={busy || !code} onClick={renew}>Make new codes</button>
                  </div>
                </div>
                <div className="pt-4 border-t border-gray-100">
                  <p className="text-sm font-medium mb-1">Turn off</p>
                  <p className="text-xs text-gray-400 mb-3">
                    {status.required
                      ? 'This service requires two-step sign-in, so you will have to set it up again before using the admin tools.'
                      : 'Takes your password and a code from the app (or a recovery code).'}
                  </p>
                  <div className="flex flex-wrap items-center gap-3">
                    {passwordInput}
                    {codeInput}
                    <button className="apple-btn-danger" disabled={busy || !code || (status.needsPassword && !password)} onClick={disable}>Turn off</button>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </Layout>
  );
}
