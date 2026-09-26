import React, { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { motion, animate, useReducedMotion } from 'framer-motion';
import {
  ArrowRight, ScanEye, RefreshCcw, Upload, ShieldCheck,
  Sparkles, Brain, Layers, Database, Trash2, ChevronDown, Server,
} from 'lucide-react';
import { useBackendHealth } from './useBackendHealth';
import { GRADES, getScreenings, subscribe, loadSampleScreenings, clearScreenings } from './screeningStore';
import FlashDeck from './FlashDeck';
import './Overview.css';

const PIPELINE = [
  { label: 'Upload', desc: 'Fundus photo received', Icon: Upload },
  { label: 'Quality gate', desc: 'Focus, exposure, field of view', Icon: ShieldCheck },
  { label: 'Enhancement', desc: 'CLAHE contrast + denoise', Icon: Sparkles },
  { label: 'Grading', desc: 'ICDR grade 0–4', Icon: Brain },
  { label: 'Explain', desc: 'Grad-CAM + Score-CAM', Icon: Layers },
];

const GLOSSARY = [
  ['Photos processed', 'Every fundus photo sent through the pipeline from this device, including ones sent back for a retake.'],
  ['Referable', 'Graded Moderate NPDR (grade 2) or worse. These should be seen by an ophthalmologist.'],
  ['Retakes requested', 'Photos the quality gate refused to grade because they were blurred, badly lit or off-centre.'],
  ['Model confidence', "The grading model's probability for the grade it chose. Low confidence is a reason for a closer human look."],
  ['Heatmap agreement', 'How closely Grad-CAM and Score-CAM point to the same regions (Pearson correlation). High agreement suggests the finding rests on real lesions.'],
  ['Focus (Laplacian)', 'The quality gate’s sharpness measure. Below 3.0 the photo is too blurred to grade and is sent back.'],
];

/* ─── Data hooks ─── */
function useScreenings() {
  const [records, setRecords] = useState(getScreenings);
  useEffect(() => subscribe(() => setRecords(getScreenings())), []);
  return records;
}

/* ─── Small pieces ─── */
function CountUp({ value, decimals = 0, suffix = '' }) {
  const reduce = useReducedMotion();
  const [display, setDisplay] = useState(reduce ? value : 0);

  useEffect(() => {
    if (reduce) {
      setDisplay(value);
      return;
    }
    const controls = animate(0, value, { duration: 1.2, ease: [0.16, 1, 0.3, 1], onUpdate: setDisplay });
    return () => controls.stop();
  }, [value, reduce]);

  return (
    <>
      {display.toFixed(decimals)}
      {suffix}
    </>
  );
}

function timeAgo(t) {
  const mins = Math.round((Date.now() - t) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs} h ago`;
  return new Date(t).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
}

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}

function GradeBadge({ record }) {
  if (record.outcome === 'rejected') {
    return <span className="ov-grade ov-grade-retake">Retake</span>;
  }
  const g = GRADES[record.grade];
  return (
    <span className="ov-grade" style={{ '--g': 'var(--accent)' }}>
      <i />
      {record.grade} · {g.short}
    </span>
  );
}

/* Flash cards summarising this device's screenings */
function buildDeck(stats) {
  const cards = [];
  const graded = stats.graded.length;
  const refPct = graded ? Math.round((stats.referable.length / graded) * 100) : 0;
  cards.push({
    id: 'referrals',
    kicker: 'Referrals',
    front: (
      <>
        <p className="fc-big">{stats.referable.length}</p>
        <p className="fc-title">eye{stats.referable.length === 1 ? '' : 's'} need a specialist</p>
        <p className="fc-text">{refPct}% of graded photos are grade 2 or worse.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">What to do</p>
        <ul className="fc-list">
          <li>Grade 2: refer within 3–6 months</li>
          <li>Grade 3: urgent referral, 2–4 weeks</li>
          <li>Grade 4: immediate referral</li>
        </ul>
      </>
    ),
  });

  const reasons = {};
  stats.rejected.forEach((r) => { if (r.reason) reasons[r.reason] = (reasons[r.reason] || 0) + 1; });
  const topReason = Object.entries(reasons).sort((a, b) => b[1] - a[1])[0];
  cards.push({
    id: 'gate',
    kicker: 'Quality gate',
    front: (
      <>
        <p className="fc-big">{Math.round(stats.passRate * 100)}%</p>
        <p className="fc-title">of photos were gradeable</p>
        <p className="fc-text">{stats.rejected.length} sent back for a retake.</p>
      </>
    ),
    back: (
      <>
        <p className="fc-title">{topReason ? `Most common: ${topReason[0]}` : 'No retakes needed'}</p>
        <p className="fc-text">
          {topReason
            ? 'Ask the patient to fixate on the target light, blink, then hold still; adjust fine focus until vessels are crisp.'
            : 'Every photo so far passed focus, exposure and field-of-view checks.'}
        </p>
      </>
    ),
  });

  const common = stats.dist.indexOf(Math.max(...stats.dist));
  if (graded) {
    cards.push({
      id: 'common',
      kicker: 'Most common finding',
      front: (
        <>
          <p className="fc-big">G{common}</p>
          <p className="fc-title">{GRADES[common].name}</p>
          <p className="fc-text">{stats.dist[common]} of {graded} graded photos.</p>
        </>
      ),
      back: (
        <>
          <p className="fc-title">Recommended follow-up</p>
          <p className="fc-text">{GRADES[common].action}.</p>
        </>
      ),
    });
  }

  if (stats.avgConfidence !== null) {
    const lowest = [...stats.graded].filter((r) => typeof r.confidence === 'number').sort((a, b) => a.confidence - b.confidence)[0];
    cards.push({
      id: 'confidence',
      kicker: 'Model confidence',
      front: (
        <>
          <p className="fc-big">{stats.avgConfidence.toFixed(0)}%</p>
          <p className="fc-title">average confidence</p>
          <p className="fc-text">Raw probability of the chosen grade.</p>
        </>
      ),
      back: (
        <>
          <p className="fc-title">Worth a second look</p>
          <p className="fc-text">
            {lowest ? `${lowest.id} had the lowest confidence (${lowest.confidence.toFixed(0)}%). Low confidence is a reason for a closer human review.` : 'No graded photos yet.'}
          </p>
        </>
      ),
    });
  }

  if (stats.avgDuration !== null) {
    cards.push({
      id: 'speed',
      kicker: 'Analysis time',
      front: (
        <>
          <p className="fc-big">{(stats.avgDuration / 1000).toFixed(1)} s</p>
          <p className="fc-title">per photo, all five phases</p>
          <p className="fc-text">Measured end to end in MATLAB.</p>
        </>
      ),
      back: (
        <>
          <p className="fc-title">Where the time goes</p>
          <p className="fc-text">Score-CAM explainability runs 24 masked forward passes and takes most of it; grading itself is under two seconds.</p>
        </>
      ),
    });
  }
  return cards;
}

const rise = {
  hidden: { opacity: 0, y: 24 },
  show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] } },
};

/* ─── Page ─── */
export default function Overview() {
  const records = useScreenings();
  const [health, recheck] = useBackendHealth();
  const [showGlossary, setShowGlossary] = useState(false);

  const role = useMemo(() => {
    try {
      return sessionStorage.getItem('vitreous.role');
    } catch {
      return null;
    }
  }, []);

  const stats = useMemo(() => {
    const graded = records.filter((r) => r.outcome === 'graded');
    const rejected = records.filter((r) => r.outcome === 'rejected');
    const referable = graded.filter((r) => r.grade >= 2);
    const mean = (arr, key) => {
      const vals = arr.map((r) => r[key]).filter((v) => typeof v === 'number');
      return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
    };
    const dist = GRADES.map((g) => graded.filter((r) => r.grade === g.grade).length);
    const queue = [...referable].sort((a, b) => b.grade - a.grade || a.time - b.time).slice(0, 6);
    return {
      total: records.length,
      graded,
      rejected,
      referable,
      dist,
      queue,
      maxDist: Math.max(1, ...dist),
      avgConfidence: mean(graded, 'confidence'),
      avgQuality: mean(records, 'focus'),
      avgAgreement: mean(graded, 'agreement'),
      avgDuration: mean(graded, 'durationMs'),
      passRate: records.length ? graded.length / records.length : 0,
      isSample: records.length > 0 && records.every((r) => r.sample),
    };
  }, [records]);

  const deckCards = useMemo(() => buildDeck(stats), [stats]);

  const empty = records.length === 0;
  const today = new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' });
  const who = role === 'Doctor' ? ', Doctor' : '';

  const statusMeta = {
    checking: { label: 'Checking…', tone: 'wait' },
    online: { label: 'Ready', tone: 'ok' },
    busy: { label: 'Analysing', tone: 'ok' },
    loading: { label: 'Loading models', tone: 'wait' },
    bridge: { label: 'MATLAB bridge', tone: 'ok' },
    offline: { label: 'Offline', tone: 'bad' },
  }[health.status];

  const RING_R = 52;
  const RING_C = 2 * Math.PI * RING_R;

  return (
    <motion.div className="ov" initial="hidden" animate="show" variants={{ show: { transition: { staggerChildren: 0.08 } } }}>
      {/* ── Header ── */}
      <motion.header className="ov-hero" variants={rise}>
        <div className="ov-hero-top">
          <div>
            <p className="ov-date">{today}</p>
            <h1 className="ov-title">{greeting()}{who}.</h1>
            <p className="ov-sub">
              {empty
                ? 'No screenings on this device yet. Here is how a photo moves through VITREOUS.'
                : `${stats.total} photo${stats.total === 1 ? '' : 's'} processed on this device${stats.referable.length ? `, ${stats.referable.length} need a specialist` : ''}.`}
            </p>
          </div>
        </div>

        {/* A photo's path through the pipeline; the pulse travels stage to stage */}
        <ol className="ov-pipeline" aria-label="Screening pipeline">
          {PIPELINE.map((s, i) => (
            <li key={s.label} style={{ '--i': i }}>
              <span className="ov-pipe-node"><s.Icon size={18} /></span>
              <span className="ov-pipe-label">{s.label}</span>
              <span className="ov-pipe-desc">{s.desc}</span>
            </li>
          ))}
          <span className="ov-pipe-track" aria-hidden="true"><span className="ov-pipe-pulse" /></span>
        </ol>
      </motion.header>

      {/* ── Data source notice ── */}
      {stats.isSample && (
        <motion.div className="ov-notice" variants={rise}>
          <Database size={18} />
          <p>
            <strong>You are looking at sample data.</strong> It disappears as soon as you run a real screening.
          </p>
          <button type="button" onClick={clearScreenings} className="ov-btn ov-btn-ghost">
            <Trash2 size={15} />
            <span>Clear sample</span>
          </button>
        </motion.div>
      )}

      {empty ? (
        <motion.section className="ov-empty" variants={rise}>
          <div className="ov-empty-icon"><ScanEye size={28} /></div>
          <h2>Your screenings will appear here</h2>
          <p>
            Run a fundus photo through AI Analysis and this page fills in with grades, referrals, quality-gate
            results and model confidence for everything processed on this device.
          </p>
          <div className="ov-empty-actions">
            <Link to="/dashboard/analysis" className="ov-btn ov-btn-dark">
              <span>Run the first screening</span>
              <ArrowRight size={17} />
            </Link>
            <button type="button" className="ov-btn ov-btn-outline" onClick={loadSampleScreenings}>
              Preview with sample data
            </button>
          </div>
        </motion.section>
      ) : (
        <>
          {/* ── KPIs ── */}
          <motion.section className="ov-kpis" variants={rise}>
            <div className="ov-kpi">
              <p className="ov-kpi-label">Photos processed</p>
              <p className="ov-kpi-value"><CountUp value={stats.total} /></p>
              <p className="ov-kpi-foot">{stats.graded.length} graded · {stats.rejected.length} sent back</p>
            </div>
            <div className="ov-kpi ov-kpi-alert">
              <p className="ov-kpi-label">Referable</p>
              <p className="ov-kpi-value"><CountUp value={stats.referable.length} /></p>
              <p className="ov-kpi-foot">
                {stats.graded.length ? Math.round((stats.referable.length / stats.graded.length) * 100) : 0}% of graded eyes · grade 2+
              </p>
            </div>
            <div className="ov-kpi">
              <p className="ov-kpi-label">Retakes requested</p>
              <p className="ov-kpi-value"><CountUp value={stats.rejected.length} /></p>
              <p className="ov-kpi-foot">Refused by the quality gate</p>
            </div>
            <div className="ov-kpi">
              <p className="ov-kpi-label">Avg. model confidence</p>
              <p className="ov-kpi-value">
                {stats.avgConfidence === null ? '—' : <CountUp value={stats.avgConfidence} decimals={1} suffix="%" />}
              </p>
              <p className="ov-kpi-foot">
                {stats.avgAgreement === null ? 'Across graded photos' : `Heatmap agreement ${stats.avgAgreement.toFixed(0)}%`}
              </p>
            </div>
          </motion.section>

          {/* ── Distribution + quality gate ── */}
          <motion.section className="ov-row ov-row-wide" variants={rise}>
            <div className="ov-card">
              <div className="ov-card-head">
                <div>
                  <h2>Severity mix</h2>
                  <p>Graded photos by ICDR grade</p>
                </div>
                <span className="ov-chip">{stats.graded.length} graded</span>
              </div>
              <ul className="ov-dist">
                {GRADES.map((g, i) => {
                  const n = stats.dist[i];
                  return (
                    <li key={g.grade}>
                      <span className="ov-dist-name">
                        <b>{g.grade}</b> {g.name}
                      </span>
                      <span className="ov-dist-bar">
                        <motion.span
                          style={{ background: 'var(--accent)' }}
                          initial={{ scaleX: 0 }}
                          animate={{ scaleX: n / stats.maxDist }}
                          transition={{ duration: 1, delay: 0.3 + i * 0.08, ease: [0.16, 1, 0.3, 1] }}
                        />
                      </span>
                      <span className="ov-dist-count">{n}</span>
                      <span className="ov-dist-action">{g.action}</span>
                    </li>
                  );
                })}
              </ul>
            </div>

            <div className="ov-card ov-gate">
              <div className="ov-card-head">
                <div>
                  <h2>Quality gate</h2>
                  <p>Share of photos good enough to grade</p>
                </div>
              </div>
              <div className="ov-ring">
                <svg viewBox="0 0 120 120" aria-hidden="true">
                  <circle cx="60" cy="60" r={RING_R} className="ov-ring-bg" />
                  <motion.circle
                    cx="60"
                    cy="60"
                    r={RING_R}
                    className="ov-ring-fg"
                    strokeDasharray={RING_C}
                    initial={{ strokeDashoffset: RING_C }}
                    animate={{ strokeDashoffset: RING_C * (1 - stats.passRate) }}
                    transition={{ duration: 1.4, delay: 0.3, ease: [0.16, 1, 0.3, 1] }}
                    transform="rotate(-90 60 60)"
                  />
                </svg>
                <div className="ov-ring-label">
                  <strong><CountUp value={stats.passRate * 100} suffix="%" /></strong>
                  <span>passed</span>
                </div>
              </div>
              <dl className="ov-gate-stats">
                <div>
                  <dt>Avg. focus (Laplacian)</dt>
                  <dd>{stats.avgQuality === null ? '—' : stats.avgQuality.toFixed(2)}</dd>
                </div>
                <div>
                  <dt>Sent back</dt>
                  <dd>{stats.rejected.length}</dd>
                </div>
              </dl>
            </div>
          </motion.section>

          {/* ── Flash cards + referral queue + system ── */}
          <motion.section className="ov-row ov-row-3" variants={rise}>
            <FlashDeck
              title="At a glance"
              subtitle="Tap a card for what it means"
              cards={deckCards}
              autoAdvanceMs={7000}
            />
            <div className="ov-card">
              <div className="ov-card-head">
                <div>
                  <h2>Referral queue</h2>
                  <p>Most severe first, then longest waiting</p>
                </div>
                <span className="ov-chip ov-chip-alert">{stats.referable.length} to refer</span>
              </div>
              {stats.queue.length === 0 ? (
                <p className="ov-muted-block">No referable findings. Every graded eye is grade 0 or 1.</p>
              ) : (
                <ul className="ov-queue">
                  {stats.queue.map((r, i) => {
                    const g = GRADES[r.grade];
                    return (
                      <motion.li
                        key={r.id}
                        style={{ '--g': 'var(--accent)' }}
                        initial={{ opacity: 0, x: -16 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ duration: 0.5, delay: 0.35 + i * 0.07, ease: [0.16, 1, 0.3, 1] }}
                      >
                        <span className="ov-queue-sev" />
                        <div className="ov-queue-main">
                          <p className="ov-queue-id">{r.id}</p>
                          <p className="ov-queue-meta">{g.name} · {timeAgo(r.time)}</p>
                        </div>
                        <span className="ov-queue-action">{g.action}</span>
                      </motion.li>
                    );
                  })}
                </ul>
              )}
            </div>

            <div className="ov-card ov-system">
              <div className="ov-card-head">
                <div>
                  <h2>System</h2>
                  <p>Analysis backend and pipeline</p>
                </div>
                <button type="button" className="ov-icon-btn" onClick={recheck} aria-label="Check backend again">
                  <RefreshCcw size={15} className={health.status === 'checking' ? 'ov-spin' : ''} />
                </button>
              </div>

              <div className={`ov-status ov-status-${statusMeta.tone}`}>
                <span className="ov-status-dot" />
                <Server size={16} />
                <span>Backend</span>
                <strong>{statusMeta.label}</strong>
              </div>
              {health.status === 'offline' && (
                <p className="ov-system-hint">Start it with <code>python3 server.py</code>; it launches MATLAB with the trained models.</p>
              )}

              <dl className="ov-system-list">
                <div>
                  <dt>Model</dt>
                  <dd>{health.info?.model || '—'}</dd>
                </div>
                <div>
                  <dt>MATLAB</dt>
                  <dd>{health.info?.version?.match(/R\d{4}[ab]/)?.[0] || '—'}</dd>
                </div>
                <div>
                  <dt>Avg. analysis time</dt>
                  <dd>{stats.avgDuration === null ? '—' : `${(stats.avgDuration / 1000).toFixed(1)} s`}</dd>
                </div>
              </dl>
            </div>
          </motion.section>

          {/* ── Recent screenings ── */}
          <motion.section className="ov-card" variants={rise}>
            <div className="ov-card-head">
              <div>
                <h2>Recent screenings</h2>
                <p>Latest photos processed on this device</p>
              </div>
              {!stats.isSample && (
                <button type="button" className="ov-btn ov-btn-ghost ov-btn-sm" onClick={clearScreenings}>
                  <Trash2 size={14} />
                  <span>Clear history</span>
                </button>
              )}
            </div>
            <div className="ov-table-wrap">
              <table className="ov-table">
                <thead>
                  <tr>
                    <th>Screening</th>
                    <th>Result</th>
                    <th>Confidence</th>
                    <th>Focus</th>
                    <th>Heatmap agreement</th>
                    <th>When</th>
                  </tr>
                </thead>
                <tbody>
                  {records.slice(0, 8).map((r, i) => (
                    <motion.tr
                      key={r.id}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ duration: 0.4, delay: 0.4 + i * 0.05 }}
                    >
                      <td>
                        <p className="ov-td-id">{r.id}</p>
                        <p className="ov-td-sub">{r.filename || '—'}</p>
                      </td>
                      <td>
                        <GradeBadge record={r} />
                        {r.outcome === 'rejected' && r.reason && <p className="ov-td-sub">{r.reason}</p>}
                      </td>
                      <td>
                        {typeof r.confidence === 'number' ? (
                          <span className="ov-meter">
                            <span className="ov-meter-bar"><span style={{ width: `${r.confidence}%` }} /></span>
                            {r.confidence.toFixed(0)}%
                          </span>
                        ) : '—'}
                      </td>
                      <td>{typeof r.focus === 'number' ? r.focus.toFixed(2) : '—'}</td>
                      <td>{typeof r.agreement === 'number' ? `${r.agreement.toFixed(0)}%` : '—'}</td>
                      <td className="ov-td-time">{timeAgo(r.time)}</td>
                    </motion.tr>
                  ))}
                </tbody>
              </table>
            </div>
          </motion.section>
        </>
      )}

      {/* ── How to read this page ── */}
      <motion.section className="ov-card ov-glossary" variants={rise}>
        <button type="button" className="ov-glossary-toggle" onClick={() => setShowGlossary((v) => !v)} aria-expanded={showGlossary}>
          <span>
            <h2>How to read this page</h2>
            <p>What each number means and where it comes from</p>
          </span>
          <ChevronDown size={18} className={showGlossary ? 'open' : ''} />
        </button>
        {showGlossary && (
          <motion.dl
            className="ov-glossary-list"
            initial={{ opacity: 0, y: -6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3 }}
          >
            {GLOSSARY.map(([term, def]) => (
              <div key={term}>
                <dt>{term}</dt>
                <dd>{def}</dd>
              </div>
            ))}
            <div>
              <dt>Where the data lives</dt>
              <dd>Screenings are stored in this browser only. Nothing on this page is sent to a server.</dd>
            </div>
          </motion.dl>
        )}
      </motion.section>
    </motion.div>
  );
}
