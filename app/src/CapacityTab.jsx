import React, { useState, useEffect, useRef } from 'react';
import './CapacityTab.css';
import FlashDeck from './dashboard/FlashDeck';
import {
  Activity, Cpu, Wifi, Users, Camera, BarChart3,
  TrendingUp, Gauge, Zap, Server, ChevronRight,
  ArrowUpRight, ArrowDownRight, Eye, Layers,
  Network, MonitorPlay, Maximize2, X
} from 'lucide-react';

/* ═══════════════════════════════════════════════════════════════
   SIMULINK CAPACITY MODEL DATA (from Chaitali's SimEvents output)
   ═══════════════════════════════════════════════════════════════ */

const BASELINE = {
  patientsPerDay: 400,
  throughputPerDay: 399,
  cameraUtilization: 0.35,
  reviewUtilization: 0.366,
  syncUtilization: 0.199,
  reviewMeanWait: 0.3,
  syncBacklogEnd: 0,
  autoClearCases: 43,
  reviewCompleted: 356,
  bottleneck: 'Ophthalmologist',
  bottleneckThreshold: 0.90,
};

const AI_COMPARISON = {
  aiOn: { reviewCompleted: 356, autoClearCases: 43, throughput: 399 },
  aiOff: { reviewCompleted: 399, autoClearCases: 0, throughput: 399 },
  workloadReduction: ((399 - 356) / 399 * 100).toFixed(1),
};

const THRESHOLD_SWEEP = [
  { threshold: 0.70, referralRate: 60.2, reviewUtil: 0.284 },
  { threshold: 0.75, referralRate: 64.6, reviewUtil: 0.302 },
  { threshold: 0.80, referralRate: 69.3, reviewUtil: 0.325 },
  { threshold: 0.85, referralRate: 73.4, reviewUtil: 0.342 },
  { threshold: 0.90, referralRate: 75.4, reviewUtil: 0.366 },
  { threshold: 0.95, referralRate: 88.7, reviewUtil: 0.392 },
];

const BANDWIDTH_SWEEP = [
  { bandwidth: 1, backlog: 335 },
  { bandwidth: 2, backlog: 223 },
  { bandwidth: 5, backlog: 109 },
  { bandwidth: 10, backlog: 109 },
  { bandwidth: 20, backlog: 109 },
];

const RESOURCE_RECOMMENDATION = {
  numCameras: 1,
  numOphthalmologists: 1,
  bandwidthMbps: 5,
  throughputPerDay: 399,
  cameraUtilization: 0.70,
  reviewUtilization: 0.366,
  syncUtilization: 0.199,
};

const CAMERA_SWEEP = [
  { cameras: 1, utilization: 0.70, throughput: 399 },
  { cameras: 2, utilization: 0.35, throughput: 399 },
  { cameras: 3, utilization: 0.233, throughput: 399 },
  { cameras: 4, utilization: 0.175, throughput: 399 },
];

const OPHTHAL_SWEEP = [
  { doctors: 1, waitTime: 0.3, throughput: 399 },
  { doctors: 2, waitTime: 0.0, throughput: 399 },
  { doctors: 3, waitTime: 0.0, throughput: 399 },
];


/* Key findings of the SimEvents model, as flash cards */
const FINDING_CARDS = [
  {
    id: 'bottleneck',
    kicker: 'Capacity',
    front: (
      <>
        <p className="fc-big">{(BASELINE.reviewUtilization * 100).toFixed(1)}%</p>
        <p className="fc-title">busiest resource: the ophthalmologist</p>
        <p className="fc-text">Against a 90% operating threshold.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">No active bottleneck</p>
        <p className="fc-text">At {BASELINE.patientsPerDay} scheduled patients the camp completes {BASELINE.throughputPerDay}/day. The system is demand-limited, not resource-limited.</p>
      </>
    ),
  },
  {
    id: 'ai',
    kicker: 'AI triage',
    front: (
      <>
        <p className="fc-big">{AI_COMPARISON.workloadReduction}%</p>
        <p className="fc-title">fewer doctor reviews</p>
        <p className="fc-text">{BASELINE.autoClearCases} cases auto-cleared per camp.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">How</p>
        <p className="fc-text">Cases graded with ≥ 90% confidence are auto-cleared; everything else goes to the ophthalmologist ({AI_COMPARISON.aiOn.reviewCompleted} instead of {AI_COMPARISON.aiOff.reviewCompleted} reviews).</p>
      </>
    ),
  },
  {
    id: 'network',
    kicker: 'Connectivity',
    front: (
      <>
        <p className="fc-big">≥ 5 Mbps</p>
        <p className="fc-title">keeps the sync backlog stable</p>
        <p className="fc-text">Screening never waits for the network.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">At 1 Mbps</p>
        <p className="fc-text">{BANDWIDTH_SWEEP[0].backlog} images are still unsynced at camp end. Above 5 Mbps the backlog plateaus at {BANDWIDTH_SWEEP[2].backlog}.</p>
      </>
    ),
  },
  {
    id: 'threshold',
    kicker: 'Confidence threshold',
    front: (
      <>
        <p className="fc-big">0.95 → {THRESHOLD_SWEEP[5].referralRate}%</p>
        <p className="fc-title">referral rate at a strict threshold</p>
        <p className="fc-text">vs {THRESHOLD_SWEEP[4].referralRate}% at 0.90.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">The trade-off</p>
        <p className="fc-text">A stricter auto-clear threshold sends nearly every case to a doctor, wiping out most of the AI workload benefit.</p>
      </>
    ),
  },
  {
    id: 'config',
    kicker: 'Minimum setup',
    front: (
      <>
        <p className="fc-big">1 + 1</p>
        <p className="fc-title">camera and ophthalmologist</p>
        <p className="fc-text">with {RESOURCE_RECOMMENDATION.bandwidthMbps} Mbps handle {RESOURCE_RECOMMENDATION.throughputPerDay} patients/day.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">Adding more doesn’t help</p>
        <p className="fc-text">Four cameras cut utilisation from 70% to 17.5% but throughput stays at 399/day. Replace these illustrative inputs with field telemetry before deployment.</p>
      </>
    ),
  },
];


/* ═══════════ ANIMATED COUNTER HOOK ═══════════ */
function useAnimatedValue(target, duration = 1200) {
  const [value, setValue] = useState(0);
  useEffect(() => {
    let start = 0;
    const step = target / (duration / 16);
    const timer = setInterval(() => {
      start += step;
      if (start >= target) { setValue(target); clearInterval(timer); }
      else setValue(start);
    }, 16);
    return () => clearInterval(timer);
  }, [target, duration]);
  return value;
}


/* ═══════════ RADIAL GAUGE COMPONENT ═══════════ */
function RadialGauge({ value, label, icon: Icon, color, threshold = 0.9 }) {
  const animatedVal = useAnimatedValue(value * 100, 1500);
  const pct = animatedVal;
  const circumference = 2 * Math.PI * 42;
  const dashArray = `${(pct / 100) * circumference} ${circumference}`;
  const isAboveThreshold = value >= threshold;

  return (
    <div className="cap-gauge-card">
      <div className="cap-gauge-ring" style={{ '--gauge-color': color }}>
        <svg viewBox="0 0 100 100" className="cap-gauge-svg">
          <circle cx="50" cy="50" r="42" className="cap-gauge-track" />
          <circle cx="50" cy="50" r="42" className="cap-gauge-fill"
            style={{ stroke: color, strokeDasharray: dashArray }} />
          {/* Threshold marker */}
          <circle cx="50" cy="50" r="42" className="cap-gauge-threshold"
            style={{
              strokeDasharray: `2 ${circumference - 2}`,
              strokeDashoffset: -(threshold * circumference),
              stroke: '#1c1f23',
            }} />
        </svg>
        <div className="cap-gauge-center">
          <span className="cap-gauge-pct">{pct.toFixed(1)}%</span>
        </div>
      </div>
      <div className="cap-gauge-label">
        <Icon size={14} style={{ color }} />
        <span>{label}</span>
      </div>
      <div className={`cap-gauge-status ${isAboveThreshold ? 'danger' : 'ok'}`}>
        {isAboveThreshold ? 'BOTTLENECK' : `${((threshold - value) * 100).toFixed(0)}pp below threshold`}
      </div>
    </div>
  );
}


/* ═══════════ BAR CHART COMPONENT ═══════════ */
function MiniBarChart({ data, xKey, yKey, color, yLabel, formatY }) {
  const max = Math.max(...data.map(d => d[yKey]));
  return (
    <div className="cap-chart-bars">
      {data.map((d, i) => (
        <div key={i} className="cap-bar-col">
          <div className="cap-bar-value">{formatY ? formatY(d[yKey]) : d[yKey]}</div>
          <div className="cap-bar-track">
            <div className="cap-bar-fill"
              style={{ height: `${(d[yKey] / max) * 100}%`, background: color }} />
          </div>
          <div className="cap-bar-label">{d[xKey]}</div>
        </div>
      ))}
    </div>
  );
}


/* ═══════════ LINE CHART COMPONENT ═══════════ */
function MiniLineChart({ data, xKey, yKey, color, yLabel }) {
  const svgRef = useRef(null);
  const max = Math.max(...data.map(d => d[yKey]));
  const min = Math.min(...data.map(d => d[yKey]));
  const range = max - min || 1;
  const pad = 30;
  const w = 260, h = 140;
  const points = data.map((d, i) => ({
    x: pad + (i / (data.length - 1)) * (w - pad * 2),
    y: pad + (1 - (d[yKey] - min) / range) * (h - pad * 2),
  }));
  const pathD = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
  const areaD = pathD + ` L ${points[points.length - 1].x} ${h - pad} L ${points[0].x} ${h - pad} Z`;

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="cap-line-svg">
      <defs>
        <linearGradient id={`grad-${yKey}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.3" />
          <stop offset="100%" stopColor={color} stopOpacity="0.02" />
        </linearGradient>
      </defs>
      <path d={areaD} fill={`url(#grad-${yKey})`} />
      <path d={pathD} fill="none" stroke={color} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      {points.map((p, i) => (
        <g key={i}>
          <circle cx={p.x} cy={p.y} r="4" fill="#ffffff" stroke={color} strokeWidth="2" />
          <text x={p.x} y={p.y - 10} textAnchor="middle" fill="#6b7280" fontSize="8" fontWeight="600">
            {typeof data[i][yKey] === 'number' && data[i][yKey] % 1 !== 0
              ? data[i][yKey].toFixed(1) : data[i][yKey]}
          </text>
          <text x={p.x} y={h - 10} textAnchor="middle" fill="#9ca3af" fontSize="7.5" fontWeight="500">
            {data[i][xKey]}
          </text>
        </g>
      ))}
    </svg>
  );
}


/* ═══════════ LIGHTBOX (image zoom) ═══════════ */
function Lightbox({ src, alt, onClose }) {
  return (
    <div className="cap-lightbox-overlay" onClick={onClose}>
      <button className="cap-lightbox-close" onClick={onClose}><X size={24} /></button>
      <img src={src} alt={alt} className="cap-lightbox-img" onClick={e => e.stopPropagation()} />
    </div>
  );
}


/* ═══════════════════════════════════════════════
   MAIN CAPACITY TAB COMPONENT
   ═══════════════════════════════════════════════ */
export default function CapacityTab() {
  const [lightboxImg, setLightboxImg] = useState(null);
  const [activeSection, setActiveSection] = useState('overview');
  const throughput = useAnimatedValue(BASELINE.throughputPerDay, 1800);
  const workloadRed = useAnimatedValue(parseFloat(AI_COMPARISON.workloadReduction), 1400);

  return (
    <div className="cap-container">
      {lightboxImg && <Lightbox src={lightboxImg} alt="Enlarged view" onClose={() => setLightboxImg(null)} />}

      {/* ── HEADER ── */}
      <div className="cap-header">
        <div className="cap-header-left">
          <div className="cap-header-badge">
            <Cpu size={14} />
            <span>SIMULINK SimEvents</span>
          </div>
          <h1 className="cap-title">Capacity Simulation</h1>
          <p className="cap-subtitle">
            Discrete-event operational model — validates clinic throughput for rural PHC screening at scale
          </p>
        </div>
        <div className="cap-header-right">
          <div className="cap-live-badge">
            <span className="cap-live-dot" />
            Model Validated
          </div>
        </div>
      </div>

      {/* ── SECTION TABS ── */}
      <div className="cap-section-tabs">
        {[
          { id: 'overview', label: 'Overview', icon: BarChart3 },
          { id: 'experiments', label: 'Experiments', icon: TrendingUp },
          { id: 'architecture', label: 'SimEvents Model', icon: Network },
        ].map(tab => (
          <button key={tab.id}
            className={`cap-section-tab ${activeSection === tab.id ? 'active' : ''}`}
            onClick={() => setActiveSection(tab.id)}>
            <tab.icon size={16} />
            {tab.label}
          </button>
        ))}
      </div>

      {/* ═══════════ OVERVIEW SECTION ═══════════ */}
      {activeSection === 'overview' && (
        <>
          {/* KPI CARDS */}
          <div className="cap-kpi-grid">
            <div className="cap-kpi-card highlight">
              <div className="cap-kpi-icon teal"><Users size={22} /></div>
              <div className="cap-kpi-body">
                <span className="cap-kpi-label">Daily Throughput</span>
                <span className="cap-kpi-value">{Math.round(throughput)}</span>
                <span className="cap-kpi-sub">of {BASELINE.patientsPerDay} scheduled patients</span>
              </div>
            </div>
            <div className="cap-kpi-card">
              <div className="cap-kpi-icon orange"><Zap size={22} /></div>
              <div className="cap-kpi-body">
                <span className="cap-kpi-label">AI Workload Reduction</span>
                <span className="cap-kpi-value">{workloadRed.toFixed(1)}%</span>
                <span className="cap-kpi-sub">{BASELINE.autoClearCases} auto-cleared / camp</span>
              </div>
            </div>
            <div className="cap-kpi-card">
              <div className="cap-kpi-icon blue"><Activity size={22} /></div>
              <div className="cap-kpi-body">
                <span className="cap-kpi-label">Busiest resource</span>
                <span className="cap-kpi-value" style={{ fontSize: '1.3rem' }}>{BASELINE.bottleneck}</span>
                <span className="cap-kpi-sub">{(BASELINE.reviewUtilization * 100).toFixed(1)}% utilization</span>
              </div>
            </div>
            <div className="cap-kpi-card">
              <div className="cap-kpi-icon purple"><Wifi size={22} /></div>
              <div className="cap-kpi-body">
                <span className="cap-kpi-label">Sync Backlog</span>
                <span className="cap-kpi-value">{BASELINE.syncBacklogEnd}</span>
                <span className="cap-kpi-sub">images at end-of-camp</span>
              </div>
            </div>
          </div>

          <div className="cap-findings">
            <FlashDeck
              title="Key findings"
              subtitle="From the SimEvents discrete-event model"
              cards={FINDING_CARDS}
              autoAdvanceMs={8000}
            />
          </div>

          {/* RESOURCE UTILIZATION GAUGES */}
          <div className="cap-section-card">
            <div className="cap-section-title">
              <Gauge size={18} />
              <span>Resource Utilization (Baseline)</span>
              <span className="cap-threshold-note">90% threshold</span>
            </div>
            <div className="cap-gauges-row">
              <RadialGauge value={BASELINE.cameraUtilization} label="Camera" icon={Camera} color="#0b6e69" />
              <RadialGauge value={BASELINE.reviewUtilization} label="Ophthalmologist" icon={Eye} color="#0b6e69" />
              <RadialGauge value={BASELINE.syncUtilization} label="Network Sync" icon={Wifi} color="#0b6e69" />
            </div>
          </div>

          {/* AI COMPARISON */}
          <div className="cap-section-card">
            <div className="cap-section-title">
              <Zap size={18} />
              <span>AI Workload Comparison</span>
            </div>
            <div className="cap-ai-comparison">
              <div className="cap-ai-block off">
                <div className="cap-ai-tag">AI OFF</div>
                <div className="cap-ai-stat">{AI_COMPARISON.aiOff.reviewCompleted}</div>
                <div className="cap-ai-label">Manual Reviews</div>
                <div className="cap-ai-sub">All cases need doctor</div>
              </div>
              <div className="cap-ai-arrow">
                <ArrowDownRight size={20} style={{ color: '#0b6e69' }} />
                <span className="cap-ai-reduction">{AI_COMPARISON.workloadReduction}%</span>
                <span className="cap-ai-reduction-label">fewer reviews</span>
              </div>
              <div className="cap-ai-block on">
                <div className="cap-ai-tag on">AI ON</div>
                <div className="cap-ai-stat">{AI_COMPARISON.aiOn.reviewCompleted}</div>
                <div className="cap-ai-label">Doctor Reviews</div>
                <div className="cap-ai-sub">{AI_COMPARISON.aiOn.autoClearCases} auto-cleared</div>
              </div>
            </div>
          </div>

          {/* RESOURCE RECOMMENDATION */}
          <div className="cap-section-card recommendation">
            <div className="cap-section-title">
              <Server size={18} />
              <span>Minimum Feasible Configuration</span>
            </div>
            <div className="cap-rec-grid">
              <div className="cap-rec-item">
                <Camera size={28} className="cap-rec-icon" />
                <div className="cap-rec-value">{RESOURCE_RECOMMENDATION.numCameras}</div>
                <div className="cap-rec-label">Camera(s)</div>
              </div>
              <div className="cap-rec-item">
                <Eye size={28} className="cap-rec-icon" />
                <div className="cap-rec-value">{RESOURCE_RECOMMENDATION.numOphthalmologists}</div>
                <div className="cap-rec-label">Ophthalmologist(s)</div>
              </div>
              <div className="cap-rec-item">
                <Wifi size={28} className="cap-rec-icon" />
                <div className="cap-rec-value">{RESOURCE_RECOMMENDATION.bandwidthMbps}</div>
                <div className="cap-rec-label">Mbps Bandwidth</div>
              </div>
              <div className="cap-rec-item">
                <Users size={28} className="cap-rec-icon" />
                <div className="cap-rec-value">{RESOURCE_RECOMMENDATION.throughputPerDay}</div>
                <div className="cap-rec-label">Patients/Day</div>
              </div>
            </div>
            <div className="cap-rec-note">
              Planning baseline — replace illustrative inputs with measured field telemetry before deployment
            </div>
          </div>
        </>
      )}

      {/* ═══════════ EXPERIMENTS SECTION ═══════════ */}
      {activeSection === 'experiments' && (
        <>
          <div className="cap-experiments-grid">
            {/* Confidence Threshold Sweep */}
            <div className="cap-section-card">
              <div className="cap-section-title">
                <Layers size={18} />
                <span>Confidence Threshold vs Referral Rate</span>
              </div>
              <div className="cap-chart-container">
                <MiniLineChart
                  data={THRESHOLD_SWEEP}
                  xKey="threshold"
                  yKey="referralRate"
                  color="#0b6e69"
                  yLabel="Referral Rate (%)"
                />
              </div>
              <p className="cap-chart-insight">
                Higher thresholds send more cases to doctors. At 0.95, referral rate reaches 88.7% — nearly eliminating AI auto-clear benefit.
              </p>
            </div>

            {/* Bandwidth Sweep */}
            <div className="cap-section-card">
              <div className="cap-section-title">
                <Wifi size={18} />
                <span>Bandwidth vs Sync Backlog</span>
              </div>
              <div className="cap-chart-container">
                <MiniBarChart
                  data={BANDWIDTH_SWEEP}
                  xKey="bandwidth"
                  yKey="backlog"
                  color="#0b6e69"
                  formatY={v => v}
                />
              </div>
              <p className="cap-chart-insight">
                At 1 Mbps, 335 images remain unsynced at camp end. ≥ 5 Mbps stabilizes the backlog. Network failure does not halt screening.
              </p>
            </div>

            {/* Camera Sweep */}
            <div className="cap-section-card">
              <div className="cap-section-title">
                <Camera size={18} />
                <span>Camera Count vs Utilization</span>
              </div>
              <div className="cap-chart-container">
                <MiniBarChart
                  data={CAMERA_SWEEP}
                  xKey="cameras"
                  yKey="utilization"
                  color="#0b6e69"
                  formatY={v => `${(v * 100).toFixed(0)}%`}
                />
              </div>
              <p className="cap-chart-insight">
                Adding cameras from 1→4 halves utilization from 70% to 17.5%, but does not increase throughput above 399 patients/day.
              </p>
            </div>

            {/* Ophthalmologist Sweep */}
            <div className="cap-section-card">
              <div className="cap-section-title">
                <Eye size={18} />
                <span>Ophthalmologist Count vs Wait Time</span>
              </div>
              <div className="cap-chart-container">
                <MiniBarChart
                  data={OPHTHAL_SWEEP}
                  xKey="doctors"
                  yKey="waitTime"
                  color="#0b6e69"
                  formatY={v => `${v}s`}
                />
              </div>
              <p className="cap-chart-insight">
                Mean review wait is already 0.3s with 1 ophthalmologist. Adding more eliminates wait but doesn't improve daily throughput.
              </p>
            </div>
          </div>

          {/* MATLAB Plots */}
          <div className="cap-section-card">
            <div className="cap-section-title">
              <MonitorPlay size={18} />
              <span>MATLAB SimEvents Output Plots</span>
            </div>
            <div className="cap-matlab-plots">
              <div className="cap-plot-thumb" onClick={() => setLightboxImg('/simulink_dashboard.png')}>
                <img src="/simulink_dashboard.png" alt="Dashboard Summary" />
                <div className="cap-plot-overlay">
                  <Maximize2 size={18} />
                  <span>Dashboard Summary</span>
                </div>
              </div>
              <div className="cap-plot-thumb" onClick={() => setLightboxImg('/threshold_sweep.png')}>
                <img src="/threshold_sweep.png" alt="Threshold Sweep" />
                <div className="cap-plot-overlay">
                  <Maximize2 size={18} />
                  <span>Threshold Sweep</span>
                </div>
              </div>
              <div className="cap-plot-thumb" onClick={() => setLightboxImg('/bandwidth_sweep.png')}>
                <img src="/bandwidth_sweep.png" alt="Bandwidth Sweep" />
                <div className="cap-plot-overlay">
                  <Maximize2 size={18} />
                  <span>Bandwidth Sweep</span>
                </div>
              </div>
              <div className="cap-plot-thumb" onClick={() => setLightboxImg('/resource_sweeps.png')}>
                <img src="/resource_sweeps.png" alt="Resource Sweeps" />
                <div className="cap-plot-overlay">
                  <Maximize2 size={18} />
                  <span>Resource Sweeps</span>
                </div>
              </div>
            </div>
          </div>
        </>
      )}

      {/* ═══════════ ARCHITECTURE SECTION ═══════════ */}
      {activeSection === 'architecture' && (
        <>
          <div className="cap-section-card">
            <div className="cap-section-title">
              <Network size={18} />
              <span>SimEvents Discrete-Event Model Architecture</span>
            </div>
            <div className="cap-architecture-img" onClick={() => setLightboxImg('/simulink_architecture.png')}>
              <img src="/simulink_architecture.png" alt="Simulink Model Architecture" />
              <div className="cap-arch-zoom">
                <Maximize2 size={16} /> Click to zoom
              </div>
            </div>
          </div>

          {/* Flow Explanation */}
          <div className="cap-section-card">
            <div className="cap-section-title">
              <Layers size={18} />
              <span>Simulation Flow</span>
            </div>
            <div className="cap-flow">
              {[
                { icon: Users, label: 'Patient Arrivals', desc: '400 patients/8-hour camp', color: '#0b6e69' },
                { icon: Camera, label: 'Camera Queue + Acquisition', desc: '45s per capture, quality gate recapture loop', color: '#0b6e69' },
                { icon: Cpu, label: 'AI Light Processing', desc: '2s light path, 8s full path (25% probability)', color: '#0b6e69' },
                { icon: Activity, label: 'Confidence Router', desc: '≥90% confidence → auto-clear, else → doctor', color: '#0b6e69' },
                { icon: Eye, label: 'Ophthalmologist Review', desc: '30s per case, queue-based', color: '#0b6e69' },
                { icon: Wifi, label: 'Deferred Sync Branch', desc: 'Independent network path, backlog on outage', color: '#0b6e69' },
              ].map((step, i) => (
                <div key={i} className="cap-flow-step">
                  <div className="cap-flow-icon" style={{ background: `${step.color}18`, color: step.color }}>
                    <step.icon size={20} />
                  </div>
                  <div className="cap-flow-body">
                    <div className="cap-flow-label">{step.label}</div>
                    <div className="cap-flow-desc">{step.desc}</div>
                  </div>
                  {i < 5 && <ChevronRight size={16} className="cap-flow-arrow" />}
                </div>
              ))}
            </div>
          </div>

          {/* Finding */}
          <div className="cap-section-card finding">
            <div className="cap-section-title">
              <BarChart3 size={18} />
              <span>Capacity Finding</span>
            </div>
            <div className="cap-finding-text">
              <p className="cap-finding-main">
                There is <strong>no active capacity bottleneck</strong> at 400 scheduled patients/day.
                Ophthalmologist is the most utilised resource (36.6%), but remains well below the 90% operating threshold.
              </p>
              <p className="cap-finding-sub">
                The simulated camp completes <strong>399 patients/day</strong>; mean ophthalmologist wait is 0.3s
                and end-of-camp sync backlog is 0 images. Adding resources (cameras, doctors, bandwidth) does not
                improve throughput — the system is demand-limited, not resource-limited.
              </p>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
