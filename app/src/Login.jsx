import React, { useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import {
  ArrowLeft, ArrowRight, Eye, EyeOff, Stethoscope, ClipboardList, User,
  Check, AlertCircle, Loader2,
} from 'lucide-react';
import './landing/landing.css'; // Loads the shared fonts
import './Login.css';

const LOGO = '/vitreous_logo.png';

const ROLES = [
  {
    id: 'Doctor',
    label: 'Doctor',
    hint: 'Ophthalmologist',
    Icon: Stethoscope,
    idLabel: 'Staff ID',
    idPlaceholder: 'e.g. DOC-1042',
  },
  {
    id: 'Nurse',
    label: 'Health worker',
    hint: 'Nurse / technician',
    Icon: ClipboardList,
    idLabel: 'Staff ID',
    idPlaceholder: 'e.g. PHC-2231',
  },
  {
    id: 'Patient',
    label: 'Patient',
    hint: 'Or guardian',
    Icon: User,
    idLabel: 'ABHA number or Patient ID',
    idPlaceholder: 'e.g. 91-1234-5678-9012',
  },
];

const POINTS = [
  'Every photo passes a quality check before it is graded',
  'Findings that need attention go to an ophthalmologist',
  'Designed around the DPDP Act 2023',
];

export default function Login() {
  const navigate = useNavigate();
  const passwordRef = useRef(null);
  const [role, setRole] = useState('Doctor');
  const [loginId, setLoginId] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [remember, setRemember] = useState(true);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [showHelp, setShowHelp] = useState(false);

  const current = ROLES.find((r) => r.id === role);

  const validate = () => {
    const next = {};
    if (!loginId.trim()) next.loginId = `Enter your ${current.idLabel.toLowerCase()}.`;
    if (!password) next.password = 'Enter your password.';
    return next;
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    const next = validate();
    setErrors(next);
    if (Object.keys(next).length) return;

    // No real authentication in this build; a short pause keeps the
    // loading state visible before entering the dashboard.
    setSubmitting(true);
    try {
      sessionStorage.setItem('vitreous.role', role);
    } catch {
      // Storage blocked; the dashboard falls back to a generic greeting
    }
    setTimeout(() => navigate('/dashboard'), 700);
  };

  const handleKey = (e) => {
    if (typeof e.getModifierState === 'function') setCapsLock(e.getModifierState('CapsLock'));
  };

  return (
    <div className="auth-root">
      {/* ── Left: brand panel ── */}
      <aside className="auth-aside" aria-hidden="true">
        <Link to="/" className="auth-brand" tabIndex={-1}>
          <img src={LOGO} alt="" />
          <span>VITREOUS</span>
        </Link>

        <div className="auth-aside-body">
          <motion.div
            className="auth-fundus"
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1.1, ease: [0.16, 1, 0.3, 1] }}
          >
            <img src="/retina_fundus.jpg" alt="" />
          </motion.div>

          <motion.h1
            className="auth-aside-title"
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.15, ease: [0.16, 1, 0.3, 1] }}
          >
            The clinical portal for diabetic eye screening.
          </motion.h1>

          <ul className="auth-points">
            {POINTS.map((p, i) => (
              <motion.li
                key={p}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ duration: 0.6, delay: 0.3 + i * 0.1, ease: [0.16, 1, 0.3, 1] }}
              >
                <span className="auth-point-check"><Check size={12} strokeWidth={3} /></span>
                {p}
              </motion.li>
            ))}
          </ul>
        </div>

        <p className="auth-aside-foot">Built by Team ByteCrew · SIH 2026</p>
      </aside>

      {/* ── Right: form ── */}
      <main className="auth-main">
        <div className="auth-topbar">
          <Link to="/" className="auth-back">
            <ArrowLeft size={16} />
            <span>Back to home</span>
          </Link>
          <Link to="/" className="auth-brand auth-brand-mobile">
            <img src={LOGO} alt="" />
            <span>VITREOUS</span>
          </Link>
        </div>

        <motion.div
          className="auth-panel"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
        >
          <h2 className="auth-title">Sign in</h2>
          <p className="auth-sub">Choose how you use VITREOUS, then enter your details.</p>

          <form onSubmit={handleSubmit} noValidate>
            <fieldset className="auth-roles">
              <legend className="auth-label">I am a</legend>
              <div className="auth-roles-grid" role="radiogroup">
                {ROLES.map((r) => {
                  const selected = role === r.id;
                  return (
                    <label key={r.id} className={`auth-role${selected ? ' selected' : ''}`}>
                      <input
                        type="radio"
                        name="role"
                        value={r.id}
                        checked={selected}
                        onChange={() => {
                          setRole(r.id);
                          setErrors({});
                        }}
                      />
                      {selected && (
                        <motion.span
                          layoutId="authRole"
                          className="auth-role-bg"
                          transition={{ type: 'spring', stiffness: 420, damping: 36 }}
                        />
                      )}
                      <r.Icon size={20} className="auth-role-icon" />
                      <span className="auth-role-label">{r.label}</span>
                      <span className="auth-role-hint">{r.hint}</span>
                    </label>
                  );
                })}
              </div>
            </fieldset>

            <div className={`auth-field${errors.loginId ? ' invalid' : ''}`}>
              <label className="auth-label" htmlFor="login-id">
                <AnimatePresence mode="wait" initial={false}>
                  <motion.span
                    key={current.idLabel}
                    initial={{ opacity: 0, y: 4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -4 }}
                    transition={{ duration: 0.15 }}
                  >
                    {current.idLabel}
                  </motion.span>
                </AnimatePresence>
              </label>
              <input
                id="login-id"
                type="text"
                autoComplete="username"
                placeholder={current.idPlaceholder}
                value={loginId}
                onChange={(e) => {
                  setLoginId(e.target.value);
                  if (errors.loginId) setErrors((x) => ({ ...x, loginId: undefined }));
                }}
                aria-invalid={Boolean(errors.loginId)}
                aria-describedby={errors.loginId ? 'login-id-error' : undefined}
              />
              {errors.loginId && (
                <p className="auth-error" id="login-id-error" role="alert">
                  <AlertCircle size={14} /> {errors.loginId}
                </p>
              )}
            </div>

            <div className={`auth-field${errors.password ? ' invalid' : ''}`}>
              <div className="auth-label-row">
                <label className="auth-label" htmlFor="login-password">Password</label>
                <button type="button" className="auth-link" onClick={() => setShowHelp((v) => !v)} aria-expanded={showHelp}>
                  Forgot password?
                </button>
              </div>
              <div className="auth-input-wrap">
                <input
                  id="login-password"
                  ref={passwordRef}
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  placeholder="Enter your password"
                  value={password}
                  onChange={(e) => {
                    setPassword(e.target.value);
                    if (errors.password) setErrors((x) => ({ ...x, password: undefined }));
                  }}
                  onKeyDown={handleKey}
                  onKeyUp={handleKey}
                  onBlur={() => setCapsLock(false)}
                  aria-invalid={Boolean(errors.password)}
                  aria-describedby={errors.password ? 'login-password-error' : undefined}
                />
                <button
                  type="button"
                  className="auth-eye"
                  onClick={() => {
                    setShowPassword((v) => !v);
                    passwordRef.current?.focus();
                  }}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  aria-pressed={showPassword}
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
              {errors.password && (
                <p className="auth-error" id="login-password-error" role="alert">
                  <AlertCircle size={14} /> {errors.password}
                </p>
              )}
              {capsLock && !errors.password && <p className="auth-note">Caps Lock is on.</p>}

              <AnimatePresence initial={false}>
                {showHelp && (
                  <motion.p
                    className="auth-help"
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: 'auto', opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.25 }}
                  >
                    {role === 'Patient'
                      ? 'Ask the health centre where you were screened to reset your access.'
                      : 'Contact your district programme administrator to reset your staff password.'}
                  </motion.p>
                )}
              </AnimatePresence>
            </div>

            <label className="auth-check">
              <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
              <span className="auth-check-box"><Check size={12} strokeWidth={3} /></span>
              Keep me signed in on this device
            </label>

            <button type="submit" className="auth-submit" disabled={submitting}>
              {submitting ? (
                <>
                  <Loader2 size={18} className="auth-spin" />
                  <span>Signing in…</span>
                </>
              ) : (
                <>
                  <span>Sign in as {current.label.toLowerCase()}</span>
                  <ArrowRight size={18} />
                </>
              )}
            </button>
          </form>

          <p className="auth-demo">
            Demo build — any ID and password will open the dashboard.
          </p>
        </motion.div>
      </main>
    </div>
  );
}
