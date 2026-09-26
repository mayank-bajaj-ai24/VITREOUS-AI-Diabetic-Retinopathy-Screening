import React, { useMemo } from 'react';
import { Routes, Route, Link, useLocation, useNavigate } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { LayoutDashboard, MonitorPlay, User, LogOut, Cpu, ChevronRight, ScanEye } from 'lucide-react';
import './dashboard/dashboard.css';
import AnalysisTab from './AnalysisTab';
import CapacityTab from './CapacityTab';
import AccountTab from './AccountTab';
import Overview from './dashboard/Overview';
import { useBackendHealth } from './dashboard/useBackendHealth';

const LOGO = '/vitreous_logo.png';

const NAV = [
  { to: '/dashboard', label: 'Overview', Icon: LayoutDashboard },
  { to: '/dashboard/analysis', label: 'AI Analysis', Icon: MonitorPlay },
  { to: '/dashboard/capacity', label: 'Capacity Sim', Icon: Cpu },
  { to: '/dashboard/account', label: 'Account Info', Icon: User },
];

const ROLE_LABEL = { Doctor: 'Doctor', Nurse: 'Health worker', Patient: 'Patient' };

export default function Dashboard() {
  const location = useLocation();
  const navigate = useNavigate();
  const [health] = useBackendHealth();

  const path = location.pathname.replace(/\/$/, '') || '/dashboard';
  const current = NAV.find((n) => n.to === path) || NAV[0];

  const role = useMemo(() => {
    try {
      return sessionStorage.getItem('vitreous.role');
    } catch {
      return null;
    }
  }, []);
  const roleLabel = ROLE_LABEL[role] || 'Clinician';

  const handleLogout = () => {
    try {
      sessionStorage.removeItem('vitreous.role');
    } catch {
      // ignore
    }
    navigate('/');
  };

  const status = {
    checking: { cls: '', label: 'Checking backend' },
    online: { cls: 'ok', label: 'MATLAB engine ready' },
    busy: { cls: 'ok', label: 'MATLAB analysing' },
    loading: { cls: '', label: 'MATLAB loading models' },
    bridge: { cls: 'ok', label: 'MATLAB bridge' },
    offline: { cls: 'bad', label: 'Engine offline' },
  }[health.status];

  return (
    <div className="app-container">
      <aside className="sidebar">
        <div className="sidebar-header" onClick={() => navigate('/')} style={{ cursor: 'pointer' }}>
          <img src={LOGO} alt="VITREOUS" className="sidebar-logo-img" />
          <span>VITREOUS</span>
        </div>

        <nav className="nav-section" aria-label="Dashboard">
          <div className="nav-label">Workspace</div>
          {NAV.map(({ to, label, Icon }) => {
            const active = current.to === to;
            return (
              <Link key={to} to={to} className={`nav-item${active ? ' active' : ''}`} aria-current={active ? 'page' : undefined}>
                {active && (
                  <motion.span
                    layoutId="navActive"
                    className="nav-item-bg"
                    transition={{ type: 'spring', stiffness: 420, damping: 36 }}
                  />
                )}
                <Icon size={19} />
                <span>{label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="sidebar-foot">
          <div className={`sidebar-system ${status.cls}`}>
            <div className="sidebar-system-row">
              <i />
              <span>{status.label}</span>
            </div>
            {health.status === 'offline' && (
              <p>Run <code>python3 server.py</code>; it starts MATLAB.</p>
            )}
            {(health.status === 'online' || health.status === 'busy') && health.info?.model && <p>{health.info.model}</p>}
          </div>
          <div className="sidebar-user">
            <span className="sidebar-user-avatar">{roleLabel[0]}</span>
            <span>
              <span className="sidebar-user-name">{roleLabel}</span>
              <span className="sidebar-user-role">Signed in on this device</span>
            </span>
          </div>
          <button type="button" className="logout-btn" onClick={handleLogout}>
            <LogOut size={19} />
            <span>Log out</span>
          </button>
        </div>
      </aside>

      <main className="main-content">
        <div className="dash-topbar">
          <div className="dash-crumb">
            <span>Workspace</span>
            <ChevronRight size={14} />
            <strong>{current.label}</strong>
          </div>
          <div className="dash-topbar-right">
            <span className="dash-date">
              {new Date().toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' })}
            </span>
            {current.to !== '/dashboard/analysis' && (
              <Link to="/dashboard/analysis" className="dash-new">
                <ScanEye size={16} />
                <span>New screening</span>
              </Link>
            )}
          </div>
        </div>

        {/* Each tab slides in; the old one fades out first */}
        <AnimatePresence mode="wait">
          <motion.div
            key={current.to}
            className="dash-page"
            initial={{ opacity: 0, y: 16, filter: 'blur(6px)' }}
            // Drop the filter afterwards: any filter traps position:fixed children (e.g. the lightbox)
            animate={{ opacity: 1, y: 0, filter: 'blur(0px)', transitionEnd: { filter: 'none', transform: 'none' } }}
            exit={{ opacity: 0, y: -8, filter: 'blur(4px)' }}
            transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
          >
            <Routes location={location}>
              <Route path="/" element={<Overview />} />
              <Route path="/analysis" element={<AnalysisTab />} />
              <Route path="/capacity" element={<CapacityTab />} />
              <Route path="/account" element={<AccountTab />} />
            </Routes>
          </motion.div>
        </AnimatePresence>
      </main>
    </div>
  );
}
