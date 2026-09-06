import React, { useState, useEffect, useRef } from 'react';

const LOGO = '/netra_logo.png';
import { 
  Eye, LayoutDashboard, MonitorPlay, MessageSquare, Activity, Settings,
  Bell, Plus, Users, Upload, Wifi, Stethoscope, ArrowRight, ChevronRight,
  HelpCircle, ShieldCheck, Heart, Zap, Brain, FileText, CheckCircle2,
  Globe, ArrowUpRight, ChevronDown
} from 'lucide-react';

/* ─── Intersection Observer Hook ─── */
function useInView(options) {
  const ref = useRef(null);
  const [isVisible, setIsVisible] = useState(false);
  useEffect(() => {
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) { setIsVisible(true); observer.unobserve(entry.target); }
    }, { threshold: 0.15, ...options });
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return [ref, isVisible];
}

/* ─── Animated Counter ─── */
function Counter({ end, suffix = '', duration = 2000 }) {
  const [count, setCount] = useState(0);
  const [ref, isVisible] = useInView();
  useEffect(() => {
    if (!isVisible) return;
    let start = 0;
    const step = end / (duration / 16);
    const timer = setInterval(() => {
      start += step;
      if (start >= end) { setCount(end); clearInterval(timer); }
      else setCount(Math.floor(start));
    }, 16);
    return () => clearInterval(timer);
  }, [isVisible, end, duration]);
  return <span ref={ref}>{count}{suffix}</span>;
}

/* ═════════════════════ LANDING PAGE ═════════════════════ */
function Landing({ onLogin }) {
  const [scrollY, setScrollY] = useState(0);
  const [navSolid, setNavSolid] = useState(false);

  useEffect(() => {
    const onScroll = () => {
      setScrollY(window.scrollY);
      setNavSolid(window.scrollY > 60);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const [s1Ref, s1Vis] = useInView();
  const [s2Ref, s2Vis] = useInView();
  const [s3Ref, s3Vis] = useInView();
  const [s4Ref, s4Vis] = useInView();
  const [s5Ref, s5Vis] = useInView();
  const [s6Ref, s6Vis] = useInView();

  return (
    <div className="landing">
      {/* ─── Fixed Nav ─── */}
      <nav className={`l-nav ${navSolid ? 'solid' : ''}`}>
        <div className="l-nav-inner">
          <div className="l-logo">
            <img src={LOGO} alt="NETRA" className="logo-img" />
            <span>NETRA</span>
          </div>
          <div className="l-nav-links">
            <a href="#problem">The Problem</a>
            <a href="#solution">Our Solution</a>
            <a href="#how">How it Works</a>
            <a href="#impact">Impact</a>
          </div>
          <button className="l-nav-cta" onClick={onLogin}>
            Open Dashboard <ArrowRight size={16} />
          </button>
        </div>
      </nav>

      {/* ─── Hero ─── */}
      <section className="l-hero">
        <div className="l-hero-video-bg">
          <video autoPlay muted loop playsInline>
            <source src="/videos/retina_hero.mp4" type="video/mp4" />
          </video>
          <div className="l-hero-overlay" />
        </div>

        <div className="l-hero-content" style={{ transform: `translateY(${scrollY * 0.25}px)`, opacity: Math.max(0, 1 - scrollY / 600) }}>
          <div className="l-badge">
            <ShieldCheck size={14} />
            <span>SIH 2026 — PROBLEM STATEMENT 26038</span>
          </div>
          <h1>
            Saving sight<br/>
            <span className="gradient-text">before it's too late.</span>
          </h1>
          <p className="l-hero-sub">
            An AI-powered retinal screening system that brings ophthalmologist-grade 
            diagnosis to rural clinics — where 80% of blindness is preventable.
          </p>
          <div className="l-hero-btns">
            <button className="btn-cta" onClick={onLogin}>
              Launch Dashboard <ArrowRight size={18} />
            </button>
            <a href="#problem" className="btn-ghost">
              Learn more <ChevronDown size={18} />
            </a>
          </div>
        </div>

        <div className="scroll-indicator">
          <div className="scroll-line" />
        </div>
      </section>

      {/* ─── The Problem ─── */}
      <section className="l-section" id="problem">
        <div ref={s1Ref} className={`l-section-inner fade-section ${s1Vis ? 'visible' : ''}`}>
          <div className="section-label">THE PROBLEM</div>
          <h2>93 million people at risk.<br/><span className="gradient-text">Not enough eyes to help.</span></h2>
          <p className="section-desc">
            India has the world's second-largest diabetic population. Diabetic Retinopathy (DR) silently 
            destroys vision — and in rural areas, patients see an ophthalmologist only after irreversible 
            damage has occurred.
          </p>
          <div className="stats-row">
            <div className="stat-block">
              <div className="stat-num"><Counter end={93} suffix="M" /></div>
              <div className="stat-label">People with DR globally</div>
            </div>
            <div className="stat-block">
              <div className="stat-num"><Counter end={80} suffix="%" /></div>
              <div className="stat-label">Of blindness is preventable</div>
            </div>
            <div className="stat-block">
              <div className="stat-num">1:<Counter end={70000} suffix="" /></div>
              <div className="stat-label">Ophthalmologist-to-patient ratio in rural India</div>
            </div>
          </div>
        </div>
      </section>

      {/* ─── Solution Overview ─── */}
      <section className="l-section dark" id="solution">
        <div ref={s2Ref} className={`l-section-inner fade-section ${s2Vis ? 'visible' : ''}`}>
          <div className="section-label light">OUR SOLUTION</div>
          <h2 className="white">NETRA sees what<br/>the human eye misses.</h2>
          <p className="section-desc light">
            National Eye Triage & Retinal Assessment — a quality-gated, explainable AI system
            that grades diabetic retinopathy severity from a single fundus photograph in under 2 minutes.
          </p>

          <div className="feature-grid">
            <div className="f-card">
              <div className="f-icon"><ShieldCheck size={28} /></div>
              <h3>Quality Gate</h3>
              <p>Rejects blurry, dark, or poorly framed images before AI analysis. 
                No bad data enters the pipeline.</p>
            </div>
            <div className="f-card">
              <div className="f-icon"><Brain size={28} /></div>
              <h3>Dual-Track AI</h3>
              <p>EfficientNet-B4 + ResNet-50 for grading, UNet++ for lesion mapping — running in 
                parallel for speed and accuracy.</p>
            </div>
            <div className="f-card">
              <div className="f-icon"><Eye size={28} /></div>
              <h3>Explainable</h3>
              <p>Grad-CAM heatmaps show exactly which lesions drove the diagnosis. 
                No black-box decisions.</p>
            </div>
            <div className="f-card">
              <div className="f-icon"><FileText size={28} /></div>
              <h3>Clinical Reports</h3>
              <p>Auto-generated PDF with severity grade, lesion overlay, confidence score, 
                and referral recommendation.</p>
            </div>
            <div className="f-card">
              <div className="f-icon"><Zap size={28} /></div>
              <h3>Edge-Ready</h3>
              <p>ONNX-optimised models run on modest hardware. 
                Works offline in connectivity-limited PHCs.</p>
            </div>
            <div className="f-card">
              <div className="f-icon"><Heart size={28} /></div>
              <h3>Built for India</h3>
              <p>Trained on Indian retinal datasets (IDRiD), with ABDM/NPCBVI compliance 
                for national health record integration.</p>
            </div>
          </div>
        </div>
      </section>

      {/* ─── How it Works ─── */}
      <section className="l-section" id="how">
        <div ref={s3Ref} className={`l-section-inner fade-section ${s3Vis ? 'visible' : ''}`}>
          <div className="section-label">HOW IT WORKS</div>
          <h2>From capture to diagnosis<br/><span className="gradient-text">in three steps.</span></h2>

          <div className="steps-container">
            <div className="step">
              <div className="step-num">01</div>
              <div className="step-content">
                <h3>Capture & Validate</h3>
                <p>A health worker captures a fundus image using a portable camera. NETRA's quality 
                  gate instantly checks sharpness, exposure, and field of view — asking for a retake 
                  if the image isn't diagnostic-ready.</p>
              </div>
            </div>
            <div className="step-divider" />
            <div className="step">
              <div className="step-num">02</div>
              <div className="step-content">
                <h3>AI Analysis</h3>
                <p>The enhanced image feeds into two parallel AI tracks simultaneously: UNet++ maps
                  every lesion pixel-by-pixel, while a hybrid CNN grades overall severity on the 
                  ICDR 0–4 scale. Temperature-calibrated confidence scores ensure reliability.</p>
              </div>
            </div>
            <div className="step-divider" />
            <div className="step">
              <div className="step-num">03</div>
              <div className="step-content">
                <h3>Report & Refer</h3>
                <p>A clinician-ready report is generated with severity grade, Grad-CAM heatmap, 
                  lesion overlay, and a clear referral recommendation. Critical cases are 
                  flagged for urgent tele-ophthalmology review.</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ─── Video Showcase ─── */}
      <section className="l-section dark" id="demo">
        <div ref={s4Ref} className={`l-section-inner fade-section ${s4Vis ? 'visible' : ''}`}>
          <div className="section-label light">RETINAL INTELLIGENCE</div>
          <h2 className="white">See the AI in action.</h2>
          <p className="section-desc light">
            Watch how NETRA processes a fundus image — from quality validation through lesion 
            segmentation to the final explainable report.
          </p>
          <div className="video-showcase">
            <div className="video-frame">
              <video autoPlay muted loop playsInline>
                <source src="/videos/retina_hero.mp4" type="video/mp4" />
              </video>
            </div>
          </div>
        </div>
      </section>

      {/* ─── Impact ─── */}
      <section className="l-section" id="impact">
        <div ref={s5Ref} className={`l-section-inner fade-section ${s5Vis ? 'visible' : ''}`}>
          <div className="section-label">IMPACT</div>
          <h2>Designed to scale<br/><span className="gradient-text">where it matters most.</span></h2>
          
          <div className="impact-grid">
            <div className="impact-card">
              <div className="impact-num"><Counter end={90} suffix="%" /></div>
              <div className="impact-text">Target sensitivity for referable DR detection</div>
            </div>
            <div className="impact-card">
              <div className="impact-num">&lt;<Counter end={2} />min</div>
              <div className="impact-text">End-to-end screening time per patient</div>
            </div>
            <div className="impact-card">
              <div className="impact-num"><Counter end={80} suffix="%" /></div>
              <div className="impact-text">Reduction in doctor workload (SimEvents validated)</div>
            </div>
            <div className="impact-card">
              <div className="impact-num">≥0.<Counter end={88} /></div>
              <div className="impact-text">Quadratic Weighted Kappa target for grading</div>
            </div>
          </div>
        </div>
      </section>

      {/* ─── CTA Footer ─── */}
      <section className="l-section cta-section">
        <div ref={s6Ref} className={`l-section-inner fade-section ${s6Vis ? 'visible' : ''}`}>
          <h2>Every scan could save someone's sight.</h2>
          <p className="section-desc">
            NETRA is built by Team ByteCrew for Smart India Hackathon 2026.
          </p>
          <button className="btn-cta large" onClick={onLogin}>
            Open the Dashboard <ArrowRight size={20} />
          </button>
        </div>
      </section>

      {/* ─── Footer ─── */}
      <footer className="l-footer">
        <div className="l-footer-inner">
          <div className="footer-brand">
            <div className="l-logo">
              <img src={LOGO} alt="NETRA" className="logo-img" />
              <span>NETRA</span>
            </div>
            <p>National Eye Triage & Retinal Assessment</p>
          </div>
          <div className="footer-cols">
            <div>
              <h4>Platform</h4>
              <a href="#solution">Features</a>
              <a href="#how">How it works</a>
              <a href="#demo">Demo</a>
              <a href="#impact">Impact</a>
            </div>
            <div>
              <h4>Project</h4>
              <a href="#">SIH 2026</a>
              <a href="#">Team ByteCrew</a>
              <a href="#">Architecture</a>
              <a href="#">Research</a>
            </div>
            <div>
              <h4>Resources</h4>
              <a href="#">ICDR Guidelines</a>
              <a href="#">IDRiD Dataset</a>
              <a href="#">APTOS 2019</a>
              <a href="#">RSSDI Guidelines</a>
            </div>
          </div>
        </div>
        <div className="footer-bottom">
          <span>© 2026 NETRA — Team ByteCrew. Built for Smart India Hackathon.</span>
          <span>Problem Statement SIH26038 · MedTech / HealthTech</span>
        </div>
      </footer>
    </div>
  );
}

/* ═════════════════════ DASHBOARD ═════════════════════ */
function Dashboard({ onLogout }) {
  const screenings = [
    { patient: 'Lakshmi Devi', initials: 'LD', id: 'NC-1048', grade: 'Level 3', status: 'Urgent', statusClass: 'status-urgent', confidence: '94%', time: '10 min ago', avatarColor: '' },
    { patient: 'Ramesh Kumar', initials: 'RK', id: 'NC-1047', grade: 'Level 1', status: 'Complete', statusClass: 'status-complete', confidence: '97%', time: '32 min ago', avatarColor: 'green' },
    { patient: 'Savitri Bai', initials: 'SB', id: 'NC-1046', grade: 'Level 2', status: 'Processing', statusClass: 'status-processing', confidence: '89%', time: '1 hr ago', avatarColor: 'green' },
  ];

  return (
    <div className="app-container">
      <div className="sidebar">
        <div className="sidebar-header" onClick={onLogout} style={{cursor: 'pointer'}} title="Back to landing page">
          <img src={LOGO} alt="NETRA" className="sidebar-logo-img" /><span>NETRA</span>
        </div>
        <div className="clinic-selector">
          <div className="clinic-icon"><Activity size={20} /></div>
          <div className="clinic-info"><div className="clinic-name">Kolar PHC</div><div className="clinic-status">Connected clinic</div></div>
          <ChevronRight size={16} color="#a0aec0" />
        </div>
        <div className="nav-section">
          <div className="nav-label">WORKSPACE</div>
          <a className="nav-item active"><LayoutDashboard size={20} /><span>Overview</span></a>
          <a className="nav-item"><MonitorPlay size={20} /><span>Screenings</span></a>
          <a className="nav-item"><MessageSquare size={20} /><span>Follow-up</span><span className="nav-badge">4</span></a>
          <a className="nav-item"><Activity size={20} /><span>Analytics</span></a>
          <a className="nav-item"><Settings size={20} /><span>Settings</span></a>
        </div>
        <div style={{ padding: '24px', borderTop: '1px solid rgba(255,255,255,0.1)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', color: '#a0aec0', fontSize: '0.9rem' }}>
            <HelpCircle size={20} />
            <div><div style={{ fontWeight: 600, color: 'white' }}>Need help?</div><div style={{ fontSize: '0.8rem' }}>Support Centre</div></div>
          </div>
        </div>
      </div>

      <div className="main-content">
        <div className="top-bar">
          <div>
            <div className="date-text">TUESDAY, 18 JUNE 2026</div>
            <h1 className="greeting">Good morning, Dr. Meera</h1>
            <p className="subtitle">Here's the latest from your triage queue.</p>
          </div>
          <div className="actions">
            <button className="btn-icon"><Bell size={20} /></button>
            <button className="btn-primary"><Plus size={20} />New screening</button>
          </div>
        </div>
        <div className="dashboard-content">
          <div className="stats-grid">
            <div className="stat-card"><div className="stat-header"><div className="icon-bg teal"><Users size={20} /></div><span>Today's patients</span></div><div className="stat-value">24</div><div className="stat-desc positive">↑ 18% this month</div></div>
            <div className="stat-card"><div className="stat-header"><div className="icon-bg orange"><Upload size={20} /></div><span>Pending processing</span></div><div className="stat-value">07</div><div className="stat-desc warning">Needs attention</div></div>
            <div className="stat-card"><div className="stat-header"><div className="icon-bg red"><Activity size={20} /></div><span>Critical alerts</span></div><div className="stat-value">03</div><div className="stat-desc danger">Doctor review</div></div>
            <div className="stat-card"><div className="stat-header"><div className="icon-bg green"><Wifi size={20} /></div><span>Pipeline status</span></div><div className="stat-value" style={{fontSize:'1.2rem'}}>All systems online</div><div className="stat-desc positive">● Models loaded · 48 ms</div></div>
          </div>
          <div className="alert-banner">
            <div className="alert-icon"><Stethoscope size={24} /></div>
            <div className="alert-content"><div className="alert-title">3 patients need urgent review</div><div className="alert-text">High confidence Level 3+ DR detected. Keep these cases ready for triage.</div></div>
            <div className="alert-action">Review queue <ArrowRight size={16} /></div>
          </div>
          <div className="two-col">
            <div className="table-card">
              <div className="card-header"><div><div className="card-title">Recent screenings</div><div className="card-subtitle">Latest AI processing activity</div></div><button className="btn-link">View all <ArrowRight size={16} /></button></div>
              <table className="data-table">
                <thead><tr><th>PATIENT</th><th>SCREENING ID</th><th>AI GRADE</th><th>STATUS</th><th>CONFIDENCE</th><th>UPLOADED</th><th></th></tr></thead>
                <tbody>
                  {screenings.map((s, i) => (
                    <tr key={i}>
                      <td><div className="patient-cell"><div className={`avatar ${s.avatarColor}`}>{s.initials}</div>{s.patient}</div></td>
                      <td style={{ color: '#718096' }}>{s.id}</td>
                      <td><span className={`badge ${s.grade.toLowerCase().replace(' ', '-')}`}>{s.grade}</span></td>
                      <td><div className={`status-cell ${s.statusClass}`}><div className="status-dot"></div>{s.status}</div></td>
                      <td className="confidence">{s.confidence}</td>
                      <td style={{ color: '#718096' }}>{s.time}</td>
                      <td><ChevronRight size={16} color="#cbd5e0" /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="info-card">
              <div className="info-label">PERFORMANCE SIGNAL</div>
              <h2 className="info-title">Faster reviews,<br/><span>better outcomes.</span></h2>
              <p className="info-text">Cases with Level 3–4 signal are triaged 2.4× faster when images pass the automated quality gate.</p>
              <div className="progress-container"><div className="progress-labels"><span>82%</span><span>auto-approved uploads</span></div><div className="progress-bar"><div className="progress-fill"></div></div></div>
              <button className="btn-link">View telemetry <ArrowRight size={16} /></button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ═════════════════════ APP ═════════════════════ */
export default function App() {
  const [page, setPage] = useState('landing');
  return page === 'landing'
    ? <Landing onLogin={() => setPage('dashboard')} />
    : <Dashboard onLogout={() => setPage('landing')} />;
}
