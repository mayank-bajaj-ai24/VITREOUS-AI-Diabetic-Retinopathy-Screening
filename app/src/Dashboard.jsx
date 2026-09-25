import React from 'react';
import { Routes, Route, Link, useLocation, useNavigate } from 'react-router-dom';
import { LayoutDashboard, MonitorPlay, User, LogOut, Activity, Settings } from 'lucide-react';
import AnalysisTab from './AnalysisTab';
import AccountTab from './AccountTab';

const LOGO = '/netra_logo.png';

export default function Dashboard() {
  const location = useLocation();
  const navigate = useNavigate();

  const handleLogout = () => {
    navigate('/');
  };

  const isActive = (path) => location.pathname === path ? 'active' : '';

  return (
    <div className="app-container">
      {/* SIDEBAR */}
      <div className="sidebar">
        <div className="sidebar-header" onClick={() => navigate('/')} style={{cursor: 'pointer'}}>
          <img src={LOGO} alt="VITREOUS" className="sidebar-logo-img" />
          <span>VITREOUS</span>
        </div>

        <div className="nav-section" style={{ marginTop: '32px' }}>
          <div className="nav-label">WORKSPACE</div>
          
          <Link to="/dashboard" className={`nav-item ${location.pathname === '/dashboard' || location.pathname === '/dashboard/' ? 'active' : ''}`}>
            <LayoutDashboard size={20} />
            <span>Overview</span>
          </Link>
          
          <Link to="/dashboard/analysis" className={`nav-item ${isActive('/dashboard/analysis')}`}>
            <MonitorPlay size={20} />
            <span>AI Analysis</span>
          </Link>

          <Link to="/dashboard/account" className={`nav-item ${isActive('/dashboard/account')}`}>
            <User size={20} />
            <span>Account Info</span>
          </Link>
        </div>

        <div style={{ marginTop: 'auto', padding: '24px', borderTop: '1px solid rgba(255,255,255,0.1)' }}>
          <div 
            className="nav-item" 
            onClick={handleLogout} 
            style={{ color: '#fc8181', cursor: 'pointer', padding: '0', background: 'transparent' }}
          >
            <LogOut size={20} />
            <span>Secure Logout</span>
          </div>
        </div>
      </div>

      {/* MAIN CONTENT AREA */}
      <div className="main-content" style={{ overflowY: 'auto' }}>
        <Routes>
          <Route path="/" element={<OverviewTab />} />
          <Route path="/analysis" element={<AnalysisTab />} />
          <Route path="/account" element={<AccountTab />} />
        </Routes>
      </div>
    </div>
  );
}

// Simple Overview Tab (using the dashboard content we had before, simplified)
function OverviewTab() {
  return (
    <div style={{ padding: '20px' }}>
      <div className="top-bar" style={{ padding: 0, border: 'none', marginBottom: '32px' }}>
        <div>
          <div className="date-text">TODAY'S ACTIVITY</div>
          <h1 className="greeting">Welcome to the Dashboard</h1>
          <p className="subtitle">Select "AI Analysis" from the sidebar to process fundus images.</p>
        </div>
      </div>
      
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-header">
            <div className="icon-bg teal"><Activity size={20} /></div>
            <span>Pipeline Status</span>
          </div>
          <div className="stat-value" style={{fontSize:'1.4rem'}}>Online</div>
          <div className="stat-desc positive">All modules loaded</div>
        </div>
        <div className="stat-card">
          <div className="stat-header">
            <div className="icon-bg orange"><MonitorPlay size={20} /></div>
            <span>Scans Processed</span>
          </div>
          <div className="stat-value">0</div>
          <div className="stat-desc">This session</div>
        </div>
      </div>
    </div>
  );
}
