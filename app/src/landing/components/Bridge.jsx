import React, { useState, useEffect } from 'react';
import { useReveal } from '../hooks/useReveal';
import { 
  Clock, User, Stethoscope, Camera, Eye, CheckCircle2, 
  ArrowRight, ChevronLeft, ChevronRight, ShieldCheck, 
  Activity, MapPin, Sparkles, HeartPulse, FileCheck, Play, Pause
} from 'lucide-react';

const CHAPTERS = [
  {
    id: 1,
    time: '09:15 AM',
    location: 'Sikar Sub-Centre, Rajasthan',
    actor: 'Ramesh Kumar, 58',
    role: 'Farmer · 11 Years with Type-2 Diabetes',
    title: 'The Silent Risk: No Pain, No Warning',
    quote: '"I can see my wheat fields clearly. Why would I spend two days and 80 km of bus travel to see an eye doctor?"',
    body: 'Ramesh walks into his local rural sub-centre for a routine blood pressure refill. Like 80% of rural diabetic patients in India, he has never undergone a dilated eye exam. Unknown to him, microvascular damage is already spreading across his retina.',
    highlight: 'Diabetic Retinopathy causes zero pain in early stages. By the time symptoms appear, vision loss is irreversible.',
    metrics: [
      { label: 'Reported Symptoms', value: '0 Symptoms' },
      { label: 'Time Since Last Eye Exam', value: 'Never Screened' },
      { label: 'Local Specialist Access', value: '80 km Away' }
    ],
    badgeColor: 'amber',
    exhibit: {
      type: 'patient',
      avatarBg: '#FEF3C7',
      avatarColor: '#B45309',
      initials: 'RK',
      vitals: [
        { label: 'Blood Glucose (Fasting)', val: '184 mg/dL', status: 'elevated' },
        { label: 'HbA1c Estimate', val: '8.4%', status: 'elevated' },
        { label: 'Visual Acuity (Snellen)', val: '6/6 (Normal)', status: 'normal' },
        { label: 'Retinal Warning Signal', val: 'Silent / Asymptomatic', status: 'warning' }
      ]
    }
  },
  {
    id: 2,
    time: '09:18 AM',
    location: 'Primary Health Consultation Desk',
    actor: 'Sunita Devi',
    role: 'Accredited ASHA Community Health Worker',
    title: 'The 60-Second Quality-Gated Capture',
    quote: '"No stinging eye drops, no waiting in dark rooms. Ramesh sits on the stool, looks at the green LED, and we take one photo."',
    body: 'Sunita uses a low-cost portable non-mydriatic fundus camera. Instead of risking blurry field photos, VITREOUS’s deterministic MATLAB Quality Gate instantly verifies focus, exposure, and retinal field-of-view in under 350ms.',
    highlight: 'Instant on-device feedback tells Sunita the image is mathematically sharp before Ramesh leaves the room.',
    metrics: [
      { label: 'Capture & Verification', value: '< 60 Seconds' },
      { label: 'Pupil Dilation Needed', value: 'None (Non-Mydriatic)' },
      { label: 'Quality Gate Validation', value: '100% Passed' }
    ],
    badgeColor: 'teal',
    exhibit: {
      type: 'quality',
      checks: [
        { name: 'Modified Laplacian Focus Check', score: '0.94 / 1.0', passed: true },
        { name: 'Quantile Exposure Balance', score: 'Normal (Optic Disc Protected)', passed: true },
        { name: '45° Macular Centering & FOV', score: 'Fovea + Arcades Included', passed: true },
        { name: 'Adaptive CLAHE Enhancement', score: 'Standardized 512×512', passed: true }
      ]
    }
  },
  {
    id: 3,
    time: '09:20 AM',
    location: 'VITREOUS Dual-Track Inference Core',
    actor: 'VITREOUS Engine',
    role: 'Quality-Gated Explainable AI (Track A + Track B)',
    title: 'Visual Proof: Unmasking Hidden Microaneurysms',
    quote: '"VITREOUS does not simply output a grade number. It draws exact boundaries around each leaking capillary so doctors can trust the diagnosis."',
    body: 'Track A UNet++ segments 14 microaneurysms and 2 blot hemorrhages invisible to untrained eyes. Track B merges EfficientNet and ResNet deep features to classify ICDR Grade 2 (Moderate NPDR). Grad-CAM heatmaps verify the AI inspected the true pathology.',
    highlight: 'Clinically calibrated confidence of 94.2% ensures zero guesswork and prevents hospital overburdening.',
    metrics: [
      { label: 'Inference Latency', value: '48 ms' },
      { label: 'Segmented Lesions', value: '14 Microaneurysms' },
      { label: 'Calibrated Confidence', value: '94.2%' }
    ],
    badgeColor: 'rose',
    exhibit: {
      type: 'ai_proof',
      classification: 'Grade 2 · Moderate NPDR',
      riskTier: 'Referable DR (Actionable Early)',
      confidence: '94.2%',
      detectedFeatures: [
        'Microaneurysms: 14 segmented lesions (perimacular)',
        'Dot/Blot Hemorrhages: 2 focal lesions in superior arcade',
        'Hard Exudates: None detected (macula safe)',
        'Grad-CAM Lesion IoU Overlap: 88.4% clinical alignment'
      ]
    }
  },
  {
    id: 4,
    time: '09:22 AM',
    location: 'District Hospital Tele-Ophthalmology Hub',
    actor: 'Dr. Meera Sen',
    role: 'Consultant Retinal Specialist (80 km Away)',
    title: 'The Triage Action: Sight Preserved',
    quote: '"Because VITREOUS pre-filtered the scan and highlighted the exact microaneurysms, reviewing Ramesh took me 45 seconds instead of 15 minutes."',
    body: 'Dr. Meera approves an early glycemic management and targeted laser referral from her hospital workstation. Ramesh receives a printed tele-health advisory and an SMS appointment before leaving the village sub-centre.',
    highlight: '6 months later, Ramesh’s vision remains 6/6. Early detection intervened 2 years before irreversible macular edema could occur.',
    metrics: [
      { label: 'Doctor Review Time', value: '45 Seconds' },
      { label: 'Workload Reduction', value: '82% Automated' },
      { label: 'Long-Term Outcome', value: 'Sight 100% Saved' }
    ],
    badgeColor: 'emerald',
    exhibit: {
      type: 'outcome',
      status: 'Prescription & Care Plan Dispatched',
      actionPlan: [
        'Glycemic target tightening (HbA1c < 7.0%)',
        'District eye hospital visit scheduled for next Tuesday',
        'Follow-up fundus check in 6 months via local Sub-Centre',
        'Prevented: Proliferative DR & Neovascular Glaucoma'
      ]
    }
  }
];

export default function Bridge() {
  const [ref, visible] = useReveal({ threshold: 0.1 });
  const [activeIdx, setActiveIdx] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);

  const cur = CHAPTERS[activeIdx];

  // Auto-advance narrative every 8 seconds if playing
  useEffect(() => {
    if (!isPlaying) return;
    const timer = setInterval(() => {
      setActiveIdx((prev) => (prev + 1) % CHAPTERS.length);
    }, 7000);
    return () => clearInterval(timer);
  }, [isPlaying]);

  return (
    <section className="story-narrative-section" id="patient-story" aria-labelledby="story-h2">
      <div className="story-container">
        
        {/* Header Block */}
        <div ref={ref} className={`story-header reveal-stagger ${visible ? 'visible' : ''}`}>
          <div className="story-pill">
            <span className="story-pill-dot" />
            THE HUMAN STORY · SIKAR DISTRICT, RAJASTHAN
          </div>
          <h2 className="story-h2" id="story-h2">
            4 Minutes That Saved Ramesh’s Sight
          </h2>
          <p className="story-subtitle">
            Diabetic Retinopathy strikes silently with zero early symptoms. 
            Follow how an ordinary morning check-up at a rural Sub-Centre changed a farmer’s life.
          </p>
        </div>

        {/* Chapter Navigation Timeline */}
        <div className="story-timeline-nav" role="tablist">
          {CHAPTERS.map((ch, idx) => {
            const isActive = idx === activeIdx;
            const isPassed = idx < activeIdx;
            return (
              <button
                key={ch.id}
                role="tab"
                aria-selected={isActive}
                onClick={() => { setActiveIdx(idx); setIsPlaying(false); }}
                className={`timeline-tab ${isActive ? 'active' : ''} ${isPassed ? 'passed' : ''}`}
              >
                <div className="tab-progress-track">
                  <div 
                    className="tab-progress-fill" 
                    style={{ width: isActive ? '100%' : isPassed ? '100%' : '0%' }}
                  />
                </div>
                <div className="tab-meta">
                  <span className="tab-num">0{idx + 1}</span>
                  <div className="tab-text-group">
                    <span className="tab-time">{ch.time}</span>
                    <span className="tab-title">{ch.actor}</span>
                  </div>
                </div>
              </button>
            );
          })}
        </div>

        {/* Main Interactive Story Card */}
        <div className="story-card-grid">
          
          {/* Left Column: Narrative Details */}
          <div className="story-content-col">
            
            <div className="story-meta-bar">
              <div className="story-badge-cluster">
                <span className={`story-time-badge ${cur.badgeColor}`}>
                  <Clock size={14} /> {cur.time}
                </span>
                <span className="story-loc-badge">
                  <MapPin size={13} /> {cur.location}
                </span>
              </div>
              <div className="story-actor-info">
                <span className="story-actor-name">{cur.actor}</span>
                <span className="story-actor-role">{cur.role}</span>
              </div>
            </div>

            <h3 className="story-chapter-title">{cur.title}</h3>

            {/* Human Quote */}
            <blockquote className="story-quote">
              <span className="quote-mark">“</span>
              {cur.quote.replace(/^"|"$/g, '')}
            </blockquote>

            {/* Narrative Body */}
            <p className="story-body-text">{cur.body}</p>

            {/* Clinical Takeaway Callout */}
            <div className="story-callout">
              <div className="callout-icon">
                <Sparkles size={18} />
              </div>
              <div className="callout-text">
                <strong>Clinical Significance:</strong> {cur.highlight}
              </div>
            </div>

            {/* Micro Metrics Grid */}
            <div className="story-metrics-grid">
              {cur.metrics.map((m, i) => (
                <div key={i} className="story-metric-item">
                  <span className="metric-val">{m.value}</span>
                  <span className="metric-lbl">{m.label}</span>
                </div>
              ))}
            </div>

            {/* Bottom Controls */}
            <div className="story-controls-bar">
              <div className="story-nav-buttons">
                <button
                  className="story-btn-icon"
                  disabled={activeIdx === 0}
                  onClick={() => { setActiveIdx((p) => Math.max(0, p - 1)); setIsPlaying(false); }}
                  aria-label="Previous chapter"
                >
                  <ChevronLeft size={18} />
                </button>
                <span className="story-step-indicator">
                  Chapter {activeIdx + 1} of {CHAPTERS.length}
                </span>
                <button
                  className="story-btn-icon"
                  disabled={activeIdx === CHAPTERS.length - 1}
                  onClick={() => { setActiveIdx((p) => Math.min(CHAPTERS.length - 1, p + 1)); setIsPlaying(false); }}
                  aria-label="Next chapter"
                >
                  <ChevronRight size={18} />
                </button>
              </div>

              <button 
                className={`story-play-toggle ${isPlaying ? 'playing' : ''}`}
                onClick={() => setIsPlaying(!isPlaying)}
              >
                {isPlaying ? <Pause size={14} /> : <Play size={14} />}
                <span>{isPlaying ? 'Pause Story' : 'Auto Play'}</span>
              </button>
            </div>

          </div>

          {/* Right Column: Visual Exhibit for Current Chapter */}
          <div className="story-visual-col">
            
            {/* Exhibit 1: Patient Profile & Health Signals */}
            {cur.exhibit.type === 'patient' && (
              <div className="exhibit-card patient-exhibit">
                <div className="exhibit-header">
                  <div className="patient-avatar" style={{ background: cur.exhibit.avatarBg, color: cur.exhibit.avatarColor }}>
                    {cur.exhibit.initials}
                  </div>
                  <div>
                    <h4 className="exhibit-title">Patient Intake Profile</h4>
                    <span className="exhibit-subtitle">Sub-Centre Registry #SKR-2026-881</span>
                  </div>
                  <span className="status-tag tag-warning">At-Risk</span>
                </div>

                <div className="vitals-list">
                  {cur.exhibit.vitals.map((v, i) => (
                    <div key={i} className="vital-row">
                      <span className="vital-label">{v.label}</span>
                      <span className={`vital-val ${v.status}`}>{v.val}</span>
                    </div>
                  ))}
                </div>

                <div className="exhibit-footer-note">
                  <HeartPulse size={16} className="text-amber" />
                  <span>Silent vascular deterioration active in retinal micro-capillaries.</span>
                </div>
              </div>
            )}

            {/* Exhibit 2: Quality Gate Telemetry */}
            {cur.exhibit.type === 'quality' && (
              <div className="exhibit-card quality-exhibit">
                <div className="exhibit-header">
                  <div className="patient-avatar" style={{ background: '#CCFBF1', color: '#0F766E' }}>
                    <Camera size={22} />
                  </div>
                  <div>
                    <h4 className="exhibit-title">Deterministic Quality Gate</h4>
                    <span className="exhibit-subtitle">MATLAB Focus & Exposure Check</span>
                  </div>
                  <span className="status-tag tag-success">Gate Passed</span>
                </div>

                <div className="checks-list">
                  {cur.exhibit.checks.map((c, i) => (
                    <div key={i} className="check-row">
                      <div className="check-info">
                        <CheckCircle2 size={16} className="text-teal" />
                        <span className="check-name">{c.name}</span>
                      </div>
                      <span className="check-score">{c.score}</span>
                    </div>
                  ))}
                </div>

                <div className="exhibit-footer-note">
                  <ShieldCheck size={16} className="text-teal" />
                  <span>Zero unusable images sent downstream. Doctor review time preserved.</span>
                </div>
              </div>
            )}

            {/* Exhibit 3: AI Lesion Proof & Heatmap */}
            {cur.exhibit.type === 'ai_proof' && (
              <div className="exhibit-card ai-exhibit">
                <div className="exhibit-header">
                  <div className="patient-avatar" style={{ background: '#FFE4E6', color: '#BE123C' }}>
                    <Eye size={22} />
                  </div>
                  <div>
                    <h4 className="exhibit-title">Explainable AI Triage</h4>
                    <span className="exhibit-subtitle">Dual-Track UNet++ & Hybrid Grading</span>
                  </div>
                  <span className="status-tag tag-danger">Actionable</span>
                </div>

                <div className="ai-diagnosis-banner">
                  <div className="ai-diag-grade">{cur.exhibit.classification}</div>
                  <div className="ai-diag-conf">Calibrated Confidence: <strong>{cur.exhibit.confidence}</strong></div>
                </div>

                <div className="features-list">
                  {cur.exhibit.detectedFeatures.map((f, i) => (
                    <div key={i} className="feature-item">
                      <div className="feature-dot" />
                      <span>{f}</span>
                    </div>
                  ))}
                </div>

                <div className="exhibit-footer-note">
                  <Activity size={16} className="text-rose" />
                  <span>Grad-CAM visual heatmaps confirm predictions stem from actual lesions.</span>
                </div>
              </div>
            )}

            {/* Exhibit 4: Clinical Outcome & Prescription */}
            {cur.exhibit.type === 'outcome' && (
              <div className="exhibit-card outcome-exhibit">
                <div className="exhibit-header">
                  <div className="patient-avatar" style={{ background: '#D1FAE5', color: '#047857' }}>
                    <Stethoscope size={22} />
                  </div>
                  <div>
                    <h4 className="exhibit-title">Tele-Consultation Resolution</h4>
                    <span className="exhibit-subtitle">District Eye Hospital Confirmation</span>
                  </div>
                  <span className="status-tag tag-success">Confirmed</span>
                </div>

                <div className="outcome-alert">
                  <FileCheck size={18} className="text-emerald" />
                  <span>{cur.exhibit.status}</span>
                </div>

                <div className="action-plan-list">
                  <span className="action-plan-title">Prescribed Clinical Protocol:</span>
                  {cur.exhibit.actionPlan.map((step, i) => (
                    <div key={i} className="action-step">
                      <span className="step-num">{i + 1}</span>
                      <span>{step}</span>
                    </div>
                  ))}
                </div>

                <div className="exhibit-footer-note">
                  <CheckCircle2 size={16} className="text-emerald" />
                  <span>Routine village visit prevented permanent visual impairment.</span>
                </div>
              </div>
            )}

          </div>

        </div>

      </div>
    </section>
  );
}
