import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Vendors from './pages/Vendors';
import Couriers from './pages/Couriers';
import Orders from './pages/Orders';
import UsersPage from './pages/UsersPage';
import Approvals from './pages/Approvals';
import Settings from './pages/Settings';

function RequireAuth({ children }: { children: JSX.Element }) {
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
        <Route path="*"         element={<Navigate to="/" replace />} />
      </Routes>
    </Router>
  );
}

export default App;
