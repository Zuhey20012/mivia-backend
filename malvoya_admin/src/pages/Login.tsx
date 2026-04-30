import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Lock, Mail } from 'lucide-react';
import api from '../utils/api';

export default function Login() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const res = await api.post('/auth/login', { email, password });
      if (res.data.ok && res.data.user.role === 'ADMIN') {
        localStorage.setItem('token', res.data.accessToken);
        navigate('/');
      } else {
        setError('Access denied. Only Admins can access this dashboard.');
      }
    } catch (err: any) {
      setError(err.response?.data?.error || 'Login failed. Check your credentials.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="min-h-screen flex items-center justify-center p-4"
      style={{ background: 'linear-gradient(135deg, #F5F5F7 0%, #E8E8ED 100%)' }}
    >
      <div style={{ width: '100%', maxWidth: '420px' }}>
        {/* Card */}
        <div className="apple-card" style={{ padding: '2.5rem' }}>
          {/* Logo */}
          <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
            <div
              style={{
                width: '64px', height: '64px',
                background: 'black',
                borderRadius: '18px',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                margin: '0 auto 1rem',
                boxShadow: '0 4px 16px rgba(0,0,0,0.15)',
              }}
            >
              <span style={{ color: 'white', fontSize: '1.5rem', fontWeight: 700 }}>M</span>
            </div>
            <h1 style={{ fontSize: '1.5rem', fontWeight: 600, letterSpacing: '-0.02em', margin: 0 }}>Malvoya Admin</h1>
            <p style={{ color: '#8E8E93', fontSize: '0.875rem', marginTop: '0.375rem' }}>Sign in to your command center</p>
          </div>

          {/* Error */}
          {error && (
            <div style={{ background: '#FFF1F0', color: '#EF4444', padding: '0.75rem 1rem', borderRadius: '0.75rem', marginBottom: '1.25rem', fontSize: '0.875rem', textAlign: 'center' }}>
              {error}
            </div>
          )}

          {/* Email/Password Form */}
          <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
            <div style={{ position: 'relative' }}>
              <Mail style={{ position: 'absolute', left: '1rem', top: '50%', transform: 'translateY(-50%)', width: '16px', height: '16px', color: '#8E8E93' }} />
              <input
                id="admin-email"
                type="email"
                placeholder="Admin Email"
                className="apple-input"
                style={{ paddingLeft: '2.75rem' }}
                value={email}
                onChange={e => setEmail(e.target.value)}
                required
              />
            </div>
            <div style={{ position: 'relative' }}>
              <Lock style={{ position: 'absolute', left: '1rem', top: '50%', transform: 'translateY(-50%)', width: '16px', height: '16px', color: '#8E8E93' }} />
              <input
                id="admin-password"
                type="password"
                placeholder="Password"
                className="apple-input"
                style={{ paddingLeft: '2.75rem' }}
                value={password}
                onChange={e => setPassword(e.target.value)}
                required
              />
            </div>
            <button
              id="sign-in-btn"
              type="submit"
              className="apple-btn-primary"
              disabled={loading}
              style={{ width: '100%', justifyContent: 'center', marginTop: '0.5rem', padding: '0.875rem', fontSize: '0.9375rem' }}
            >
              {loading ? 'Signing in...' : 'Sign In'}
            </button>
          </form>

          {/* Divider */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', margin: '1.5rem 0' }}>
            <div style={{ flex: 1, height: '1px', background: '#F2F2F7' }} />
            <span style={{ color: '#8E8E93', fontSize: '0.75rem', fontWeight: 500 }}>OR</span>
            <div style={{ flex: 1, height: '1px', background: '#F2F2F7' }} />
          </div>

          {/* Google Sign In Note */}
          <div
            style={{
              background: '#F5F5F7',
              borderRadius: '0.75rem',
              padding: '1rem',
              textAlign: 'center',
            }}
          >
            <p style={{ fontSize: '0.8125rem', color: '#636366', lineHeight: 1.5, margin: 0 }}>
              🔐 <strong>Admin access only.</strong><br />
              Use your registered admin email and password to sign in. Contact the platform owner to get admin access.
            </p>
          </div>
        </div>

        {/* Footer */}
        <p style={{ textAlign: 'center', fontSize: '0.75rem', color: '#8E8E93', marginTop: '1.5rem' }}>
          © 2026 Malvoya · All rights reserved
        </p>
      </div>
    </div>
  );
}
