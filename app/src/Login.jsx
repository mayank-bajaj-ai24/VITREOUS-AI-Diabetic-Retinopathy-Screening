import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ShieldCheck, ArrowRight, UserCircle2 } from 'lucide-react';
import './landing/landing.css'; // Reuse landing aesthetics

const LOGO = '/netra_logo.png';

export default function Login() {
  const [role, setRole] = useState('Doctor');
  const [loginId, setLoginId] = useState('');
  const [password, setPassword] = useState('');
  const navigate = useNavigate();

  const handleLogin = (e) => {
    e.preventDefault();
    if (loginId && password) {
      // Basic validation just to ensure fields are filled before navigating
      navigate('/dashboard');
    }
  };

  return (
    <div className="landing-root" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: '#0a0a0a' }}>
      {/* Simple Header */}
      <nav className="l-nav solid" style={{ position: 'absolute' }}>
        <div className="l-nav-inner" style={{ justifyContent: 'center' }}>
          <div className="l-logo" onClick={() => navigate('/')} style={{ cursor: 'pointer' }}>
            <img src={LOGO} alt="VITREOUS" className="logo-img" />
            <span>VITREOUS</span>
          </div>
        </div>
      </nav>

      {/* Login Container */}
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '120px 20px 20px' }}>
        <div className="login-card" style={{
          backgroundColor: '#111',
          border: '1px solid #333',
          borderRadius: '16px',
          padding: '40px',
          width: '100%',
          maxWidth: '420px',
          boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255, 255, 255, 0.05)',
          display: 'flex',
          flexDirection: 'column',
          gap: '24px'
        }}>
          
          <div style={{ textAlign: 'center' }}>
            <ShieldCheck size={48} color="#00e5ff" style={{ marginBottom: '16px' }} />
            <h2 style={{ fontSize: '1.8rem', color: '#fff', margin: '0 0 8px 0', letterSpacing: '-0.5px' }}>Secure Access</h2>
            <p style={{ color: '#888', margin: 0, fontSize: '0.95rem' }}>Login to the VITREOUS Clinical Portal</p>
          </div>

          <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            
            {/* Role Dropdown */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <label style={{ color: '#ccc', fontSize: '0.85rem', fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>Access Level</label>
              <div style={{ position: 'relative' }}>
                <select 
                  value={role} 
                  onChange={(e) => setRole(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '12px 16px',
                    backgroundColor: '#1a1a1a',
                    border: '1px solid #333',
                    borderRadius: '8px',
                    color: '#fff',
                    fontSize: '1rem',
                    appearance: 'none',
                    outline: 'none',
                    cursor: 'pointer'
                  }}
                >
                  <option value="Doctor">Doctor / Ophthalmologist</option>
                  <option value="Nurse">Nurse / Technician</option>
                  <option value="Patient">Patient / Guardian</option>
                </select>
                <UserCircle2 size={18} color="#666" style={{ position: 'absolute', right: '16px', top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }} />
              </div>
            </div>

            {/* Login ID */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <label style={{ color: '#ccc', fontSize: '0.85rem', fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>Login ID</label>
              <input 
                type="text" 
                required
                placeholder={role === 'Patient' ? "Enter Patient ID" : "Enter Staff ID"}
                value={loginId}
                onChange={(e) => setLoginId(e.target.value)}
                style={{
                  width: '100%',
                  padding: '12px 16px',
                  backgroundColor: '#1a1a1a',
                  border: '1px solid #333',
                  borderRadius: '8px',
                  color: '#fff',
                  fontSize: '1rem',
                  outline: 'none',
                  transition: 'border-color 0.2s'
                }}
                onFocus={(e) => e.target.style.borderColor = '#00e5ff'}
                onBlur={(e) => e.target.style.borderColor = '#333'}
              />
            </div>

            {/* Password */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <label style={{ color: '#ccc', fontSize: '0.85rem', fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.5px' }}>Password</label>
              <input 
                type="password" 
                required
                placeholder="Enter password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                style={{
                  width: '100%',
                  padding: '12px 16px',
                  backgroundColor: '#1a1a1a',
                  border: '1px solid #333',
                  borderRadius: '8px',
                  color: '#fff',
                  fontSize: '1rem',
                  outline: 'none',
                  transition: 'border-color 0.2s'
                }}
                onFocus={(e) => e.target.style.borderColor = '#00e5ff'}
                onBlur={(e) => e.target.style.borderColor = '#333'}
              />
            </div>

            {/* Submit */}
            <button 
              type="submit" 
              style={{
                marginTop: '12px',
                padding: '14px',
                backgroundColor: '#fff',
                color: '#000',
                border: 'none',
                borderRadius: '8px',
                fontSize: '1rem',
                fontWeight: 600,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                transition: 'transform 0.1s, opacity 0.2s'
              }}
              onMouseOver={(e) => e.target.style.opacity = '0.9'}
              onMouseOut={(e) => e.target.style.opacity = '1'}
              onMouseDown={(e) => e.target.style.transform = 'scale(0.98)'}
              onMouseUp={(e) => e.target.style.transform = 'scale(1)'}
            >
              Sign In <ArrowRight size={18} />
            </button>
          </form>
          
          <div style={{ textAlign: 'center', marginTop: '8px' }}>
            <a href="#" style={{ color: '#666', fontSize: '0.85rem', textDecoration: 'none' }}>Forgot password? Contact IT Support</a>
          </div>

        </div>
      </div>
    </div>
  );
}
