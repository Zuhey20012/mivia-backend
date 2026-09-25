import axios from 'axios';

const api = axios.create({
  baseURL: (import.meta.env.VITE_API_URL as string) || 'http://localhost:4000/api/v1',
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token && config.headers) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Access tokens live 15 minutes and the panel keeps no refresh token, so an expired or
// revoked session sends the admin back to the login screen instead of failing silently.
api.interceptors.response.use(
  (res) => res,
  (error) => {
    const onLogin = window.location.hash.startsWith('#/login');
    if (error.response?.status === 401 && !onLogin) {
      localStorage.removeItem('token');
      window.location.hash = '#/login';
    }
    return Promise.reject(error);
  },
);

export default api;
