import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard, ShoppingBag, Users, Truck,
  Store, CheckSquare, LogOut, Settings
} from 'lucide-react';

const nav = [
  { to: '/',         icon: LayoutDashboard, label: 'Overview'   },
  { to: '/orders',   icon: ShoppingBag,     label: 'Orders'     },
  { to: '/vendors',  icon: Store,           label: 'Vendors'    },
  { to: '/couriers', icon: Truck,           label: 'Couriers'   },
  { to: '/users',    icon: Users,           label: 'Users'      },
  { to: '/approvals',icon: CheckSquare,     label: 'Approvals'  },
];

export default function Sidebar() {
  const handleLogout = () => {
    localStorage.removeItem('token');
    window.location.href = '/login';
  };

  return (
    <aside className="w-60 min-h-screen bg-white border-r border-gray-100 flex flex-col py-6 px-3 fixed top-0 left-0 z-40">
      {/* Logo */}
      <div className="flex items-center gap-3 px-3 mb-8">
        <div className="w-9 h-9 bg-black rounded-xl flex items-center justify-center text-white font-bold text-lg shadow">M</div>
        <div>
          <p className="font-semibold text-sm leading-tight">Malvoya</p>
          <p className="text-[10px] text-gray-400 leading-tight">Admin Dashboard</p>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 flex flex-col gap-1">
        {nav.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            className={({ isActive }) =>
              `sidebar-item ${isActive ? 'active' : ''}`
            }
          >
            <Icon className="w-4 h-4 shrink-0" />
            {label}
          </NavLink>
        ))}
      </nav>

      {/* Bottom */}
      <div className="flex flex-col gap-1 pt-4 border-t border-gray-100">
        <NavLink to="/settings" className={({ isActive }) => `sidebar-item ${isActive ? 'active' : ''}`}>
          <Settings className="w-4 h-4 shrink-0" />
          Settings
        </NavLink>
        <button onClick={handleLogout} className="sidebar-item text-red-400 hover:text-red-500 hover:bg-red-50">
          <LogOut className="w-4 h-4 shrink-0" />
          Sign out
        </button>
      </div>
    </aside>
  );
}
