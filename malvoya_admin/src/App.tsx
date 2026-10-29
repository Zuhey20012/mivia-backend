import React from 'react';
import { HashRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Vendors from './pages/Vendors';
import Couriers from './pages/Couriers';
import Orders from './pages/Orders';
import UsersPage from './pages/UsersPage';
import Approvals from './pages/Approvals';
import Settings from './pages/Settings';
import Moderation from './pages/Moderation';
import Payouts from './pages/Payouts';
import Support from './pages/Support';
import System from './pages/System';
import Security from './pages/Security';
import PromoCodes from './pages/PromoCodes';
import Analytics from './pages/Analytics';
import Dac7 from './pages/Dac7';
import Legal from './pages/Legal';
import Categories from './pages/Categories';
import Certificates from './pages/Certificates';
import ProductReports from './pages/ProductReports';
import Recalls from './pages/Recalls';
import Sounds from './pages/Sounds';
import Live from './pages/Live';

function RequireAuth({ children }: { children: React.ReactElement }) {
  const token = localStorage.getItem('token');
  if (!token) return <Navigate to="/login" replace />;
  return children;
}

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/"         element={<RequireAuth><Dashboard /></RequireAuth>} />
        <Route path="/vendors"  element={<RequireAuth><Vendors /></RequireAuth>} />
        <Route path="/couriers" element={<RequireAuth><Couriers /></RequireAuth>} />
        <Route path="/orders"   element={<RequireAuth><Orders /></RequireAuth>} />
        <Route path="/users"    element={<RequireAuth><UsersPage /></RequireAuth>} />
        <Route path="/approvals"element={<RequireAuth><Approvals /></RequireAuth>} />
        <Route path="/settings" element={<RequireAuth><Settings /></RequireAuth>} />
        <Route path="/moderation" element={<RequireAuth><Moderation /></RequireAuth>} />
        <Route path="/payouts"  element={<RequireAuth><Payouts /></RequireAuth>} />
        <Route path="/support"  element={<RequireAuth><Support /></RequireAuth>} />
        <Route path="/system"   element={<RequireAuth><System /></RequireAuth>} />
        <Route path="/security" element={<RequireAuth><Security /></RequireAuth>} />
        <Route path="/promo-codes" element={<RequireAuth><PromoCodes /></RequireAuth>} />
        <Route path="/analytics" element={<RequireAuth><Analytics /></RequireAuth>} />
        <Route path="/dac7"     element={<RequireAuth><Dac7 /></RequireAuth>} />
        <Route path="/legal"    element={<RequireAuth><Legal /></RequireAuth>} />
        <Route path="/categories" element={<RequireAuth><Categories /></RequireAuth>} />
        <Route path="/certificates" element={<RequireAuth><Certificates /></RequireAuth>} />
        <Route path="/product-reports" element={<RequireAuth><ProductReports /></RequireAuth>} />
        <Route path="/recalls" element={<RequireAuth><Recalls /></RequireAuth>} />
        <Route path="/sounds"  element={<RequireAuth><Sounds /></RequireAuth>} />
        <Route path="/live"    element={<RequireAuth><Live /></RequireAuth>} />
        <Route path="*"         element={<Navigate to="/" replace />} />
      </Routes>
    </Router>
  );
}

export default App;
