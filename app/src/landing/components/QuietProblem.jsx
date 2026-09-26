import React, { useMemo, useRef, useState } from 'react';
import { motion, useScroll, useTransform, useMotionValueEvent } from 'framer-motion';
import { useReveal, useCountUp } from '../hooks/useReveal';
import SplitReveal from './SplitReveal';

/* ─── ICDR stages the scroll walks through ─── */
const STAGES = [
  {
    grade: 0,
    name: 'No retinopathy',
    desc: 'Healthy vessels, clear retina. Vision is perfect.',
    feels: 'Nothing',
  },
  {
    grade: 1,
    name: 'Mild NPDR',
    desc: 'Microaneurysms — tiny bulges in the capillary walls — begin to appear.',
    feels: 'Nothing',
  },
  {
    grade: 2,
    name: 'Moderate NPDR',
    desc: 'Vessels start to leak. Small haemorrhages and fatty hard exudates form.',
    feels: 'Nothing',
  },
  {
    grade: 3,
    name: 'Severe NPDR',
    desc: 'Bleeding in every quadrant. Cotton-wool spots show the retina is starved of oxygen.',
    feels: 'Usually still nothing',
  },
  {
    grade: 4,
    name: 'Proliferative DR',
    desc: 'Fragile new vessels grow and bleed into the eye. Vision loss can now be permanent.',
    feels: 'Floaters, blurring, sudden vision loss',
  },
];

// Scroll progress (0–1 through the pinned section) at which each stage begins
const STAGE_AT = [0, 0.2, 0.4, 0.6, 0.8];
const DAMAGE = [3, 25, 50, 75, 100];
const FELT = [0, 0, 0, 5, 100];

/* ─── Deterministic retina geometry ─── */
const DISC = { x: 395, y: 285 };
const MACULA = { x: 222, y: 302 };

function seeded(seed) {
  let s = seed;
  return () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

function buildVessels() {
  const rand = seeded(11);
  const paths = [];

  const grow = (x, y, angle, curve, len, width, depth) => {
    if (depth === 0 || width < 0.5) return;
    const segs = 4;
    let cx = x;
    let cy = y;
    let a = angle;
    let d = `M${x.toFixed(1)} ${y.toFixed(1)}`;
    for (let s = 0; s < segs; s++) {
      a += curve + (rand() - 0.5) * 0.35;
      const nx = cx + (Math.cos(a) * len) / segs;
      const ny = cy + (Math.sin(a) * len) / segs;
      const mx = (cx + nx) / 2 + (rand() - 0.5) * 7;
      const my = (cy + ny) / 2 + (rand() - 0.5) * 7;
      d += ` Q${mx.toFixed(1)} ${my.toFixed(1)} ${nx.toFixed(1)} ${ny.toFixed(1)}`;
      cx = nx;
      cy = ny;
      if (s > 0 && s < segs - 1 && rand() < 0.55) {
        const side = rand() < 0.5 ? -1 : 1;
        grow(cx, cy, a + side * (0.7 + rand() * 0.5), curve * 0.3, len * 0.42, width * 0.55, depth - 1);
      }
    }
    paths.push({ d, w: width });
    grow(cx, cy, a - 0.3 - rand() * 0.25, curve * 0.7, len * 0.68, width * 0.7, depth - 1);
    grow(cx, cy, a + 0.3 + rand() * 0.25, curve * 0.7, len * 0.68, width * 0.7, depth - 1);
  };

  // Temporal arcades curve around the macula; nasal branches fan out
  grow(DISC.x, DISC.y - 8, -1.95, -0.2, 150, 7, 4);
  grow(DISC.x, DISC.y + 8, 1.95, 0.2, 150, 7, 4);
  grow(DISC.x + 6, DISC.y - 6, -0.9, 0.05, 120, 5, 4);
  grow(DISC.x + 6, DISC.y + 6, 0.9, -0.05, 120, 5, 4);
  grow(DISC.x + 10, DISC.y, 0.05, 0, 110, 3.5, 3);
  return paths;
}

function randomPoint(rand, { minR = 0, maxR = 250, avoidDisc = 58 } = {}) {
  for (;;) {
    const a = rand() * Math.PI * 2;
    const r = minR + Math.sqrt(rand()) * (maxR - minR);
    const x = 300 + Math.cos(a) * r;
    const y = 300 + Math.sin(a) * r;
    if (Math.hypot(x - DISC.x, y - DISC.y) > avoidDisc) return { x, y };
  }
}

function buildLesions() {
  const rand = seeded(29);
  const lesions = [];

  // Grade 1: microaneurysms
  for (let i = 0; i < 16; i++) {
    const p = randomPoint(rand, { maxR: 190 });
    lesions.push({ type: 'ma', stage: 1, ...p, r: 2.4 + rand() * 1.6 });
  }
  // Grade 2: dot-blot haemorrhages + first exudates in a ring near the macula
  for (let i = 0; i < 10; i++) {
    const p = randomPoint(rand, { maxR: 210 });
    lesions.push({ type: 'haem', stage: 2, ...p, rx: 6 + rand() * 7, ry: 4 + rand() * 5, rot: rand() * 180 });
  }
  const exCentre = { x: MACULA.x + 34, y: MACULA.y + 30 };
  for (let i = 0; i < 26; i++) {
    const a = rand() * Math.PI * 2;
    const r = 30 + rand() * 26;
    lesions.push({
      type: 'ex',
      stage: i < 12 ? 2 : 3,
      x: exCentre.x + Math.cos(a) * r,
      y: exCentre.y + Math.sin(a) * r,
      r: 2 + rand() * 2.8,
    });
  }
  // Grade 3: haemorrhages in every quadrant + cotton-wool spots
  for (let q = 0; q < 4; q++) {
    for (let i = 0; i < 4; i++) {
      const a = (q + 0.15 + rand() * 0.7) * (Math.PI / 2);
      const r = 90 + rand() * 150;
      const x = 300 + Math.cos(a) * r;
      const y = 300 + Math.sin(a) * r;
      if (Math.hypot(x - DISC.x, y - DISC.y) < 58) continue;
      lesions.push({ type: 'haem', stage: 3, x, y, rx: 7 + rand() * 9, ry: 4 + rand() * 6, rot: rand() * 180 });
    }
  }
  for (let i = 0; i < 6; i++) {
    const p = randomPoint(rand, { minR: 60, maxR: 200 });
    lesions.push({ type: 'cws', stage: 3, ...p, rx: 12 + rand() * 8, ry: 8 + rand() * 5, rot: rand() * 180 });
  }
  return lesions;
}

function buildNeovessels() {
  const rand = seeded(53);
  const tufts = [];
  const centres = [
    { x: DISC.x - 4, y: DISC.y - 30 },
    { x: DISC.x + 22, y: DISC.y + 24 },
    { x: 250, y: 170 },
  ];
  centres.forEach((c) => {
    for (let i = 0; i < 9; i++) {
      let x = c.x;
      let y = c.y;
      let d = `M${x.toFixed(1)} ${y.toFixed(1)}`;
      for (let s = 0; s < 5; s++) {
        const nx = x + (rand() - 0.5) * 34;
        const ny = y + (rand() - 0.5) * 34;
        d += ` Q${(x + (rand() - 0.5) * 30).toFixed(1)} ${(y + (rand() - 0.5) * 30).toFixed(1)} ${nx.toFixed(1)} ${ny.toFixed(1)}`;
        x = nx;
        y = ny;
      }
      tufts.push(d);
    }
  });
  return tufts;
}

/* ─── The retina illustration ─── */
function Retina({ stage, drawProgress, showAi }) {
  const vessels = useMemo(buildVessels, []);
  const lesions = useMemo(buildLesions, []);
  const neo = useMemo(buildNeovessels, []);

  return (
    <svg className="retina-svg" viewBox="0 0 600 600" role="img" aria-label={`Illustrated retina at ICDR grade ${stage}`}>
      <defs>
        <radialGradient id="fundus" cx="45%" cy="50%" r="60%">
          <stop offset="0%" stopColor="#e2763c" />
          <stop offset="55%" stopColor="#c4502a" />
          <stop offset="100%" stopColor="#5e160c" />
        </radialGradient>
        <radialGradient id="disc" cx="45%" cy="45%" r="55%">
          <stop offset="0%" stopColor="#fff4d6" />
          <stop offset="60%" stopColor="#f6c27a" />
          <stop offset="100%" stopColor="#e1904a" />
        </radialGradient>
        <radialGradient id="macula">
          <stop offset="0%" stopColor="#5a1208" stopOpacity="0.7" />
          <stop offset="100%" stopColor="#5a1208" stopOpacity="0" />
        </radialGradient>
        <radialGradient id="vitreousBleed">
          <stop offset="0%" stopColor="#3b0703" stopOpacity="0.85" />
          <stop offset="100%" stopColor="#3b0703" stopOpacity="0" />
        </radialGradient>
        <filter id="soft" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="3" />
        </filter>
        <clipPath id="fundusClip">
          <circle cx="300" cy="300" r="286" />
        </clipPath>
      </defs>

      <g clipPath="url(#fundusClip)">
        <rect width="600" height="600" fill="url(#fundus)" />
        <circle cx={MACULA.x} cy={MACULA.y} r="70" fill="url(#macula)" />

        <g className="retina-vessels">
          {vessels.map((v, i) => (
            <motion.path
              key={i}
              d={v.d}
              fill="none"
              stroke="#7c150c"
              strokeWidth={v.w}
              strokeLinecap="round"
              style={{ pathLength: drawProgress }}
            />
          ))}
        </g>

        <circle cx={DISC.x} cy={DISC.y} r="40" fill="url(#disc)" />
        <circle cx={DISC.x - 4} cy={DISC.y - 2} r="15" fill="#fffaf0" opacity="0.7" />

        {lesions.map((l, i) => {
          const on = stage >= l.stage;
          const style = { transitionDelay: on ? `${(i % 16) * 35}ms` : '0ms' };
          const cls = `lesion lesion-${l.type}${on ? ' on' : ''}`;
          if (l.type === 'ma' || l.type === 'ex') {
            return <circle key={i} className={cls} style={style} cx={l.x} cy={l.y} r={l.r} />;
          }
          // Rotation lives on the group so the CSS scale-in transform doesn't override it
          return (
            <g key={i} transform={`rotate(${l.rot} ${l.x} ${l.y})`}>
              <ellipse
                className={cls}
                style={style}
                cx={l.x}
                cy={l.y}
                rx={l.rx}
                ry={l.ry}
                filter={l.type === 'cws' ? 'url(#soft)' : undefined}
              />
            </g>
          );
        })}

        <g className={`lesion-neo${stage >= 4 ? ' on' : ''}`}>
          {neo.map((d, i) => (
            <path key={i} d={d} fill="none" stroke="#d6331f" strokeWidth="1.3" strokeLinecap="round" />
          ))}
          <ellipse cx="330" cy="470" rx="190" ry="120" fill="url(#vitreousBleed)" />
        </g>

        {/* What VITREOUS flags: rings around each visible lesion */}
        <g className={`ai-rings${showAi && stage >= 1 ? ' on' : ''}`} aria-hidden="true">
          {lesions
            .filter((l) => l.type !== 'ex' && stage >= l.stage)
            .map((l, i) => (
              <circle
                key={i}
                cx={l.x}
                cy={l.y}
                r={(l.r || Math.max(l.rx, l.ry)) + 7}
                fill="none"
                stroke="#ffffff"
                strokeWidth="1.4"
              />
            ))}
        </g>
      </g>

      <circle cx="300" cy="300" r="286" fill="none" stroke="rgba(11,18,32,0.9)" strokeWidth="4" />
    </svg>
  );
}

/* ─── Sourced figures under the story ─── */
function Stat({ end, prefix = '', suffix = '', label, source }) {
  const [ref, visible] = useReveal({ threshold: 0.4 });
  const count = useCountUp(end, visible, 1600);
  return (
    <div className={`qp-stat${visible ? ' visible' : ''}`} ref={ref}>
      <div className="qp-stat-num">
        {prefix}
        {count.toLocaleString('en-IN')}
        {suffix}
      </div>
      <p className="qp-stat-label">{label}</p>
      <p className="qp-stat-source">{source}</p>
    </div>
  );
}

export default function QuietProblem() {
  const trackRef = useRef(null);
  const [stage, setStage] = useState(0);
  const [showAi, setShowAi] = useState(true);

  const { scrollYProgress } = useScroll({ target: trackRef, offset: ['start start', 'end end'] });
  const { scrollYProgress: enterProgress } = useScroll({ target: trackRef, offset: ['start end', 'start start'] });
  const drawProgress = useTransform(enterProgress, [0.2, 1], [0, 1]);
  const retinaScale = useTransform(enterProgress, [0, 1], [0.82, 1]);
  const retinaRotate = useTransform(scrollYProgress, [0, 1], [-8, 8]);

  useMotionValueEvent(scrollYProgress, 'change', (p) => {
    let next = 0;
    STAGE_AT.forEach((t, i) => {
      if (p >= t) next = i;
    });
    setStage((prev) => (prev === next ? prev : next));
  });

  const jumpTo = (i) => {
    const el = trackRef.current;
    if (!el) return;
    const top = el.getBoundingClientRect().top + window.scrollY;
    const range = el.offsetHeight - window.innerHeight;
    window.scrollTo({ top: top + (STAGE_AT[i] + 0.08) * range, behavior: 'smooth' });
  };

  const current = STAGES[stage];

  return (
    <section className="quiet-section" id="quiet-problem" aria-labelledby="quiet-h2">
      <div className="qp-track" ref={trackRef}>
        <div className="qp-sticky">
          <div className="qp-grid">
            <div className="qp-copy">
              <div className="section-label">
                <span className="dot" aria-hidden="true" />
                The quiet problem
              </div>

              <SplitReveal
                className="quiet-h2"
                id="quiet-h2"
                lines={['It rarely hurts.', "That's what makes it dangerous."]}
              />

              <ol className="qp-stages">
                {STAGES.map((s, i) => (
                  <li key={s.grade} className={`qp-stage${i === stage ? ' active' : ''}${i < stage ? ' past' : ''}`}>
                    <button type="button" onClick={() => jumpTo(i)} aria-current={i === stage ? 'step' : undefined}>
                      <span className="qp-stage-grade">{s.grade}</span>
                      <span className="qp-stage-name">{s.name}</span>
                    </button>
                    <div className="qp-stage-desc">
                      <p>{s.desc}</p>
                    </div>
                  </li>
                ))}
              </ol>

              <div className="qp-meters">
                <div className="qp-meter">
                  <div className="qp-meter-head">
                    <span>Damage to the retina</span>
                  </div>
                  <div className="qp-meter-track">
                    <div className="qp-meter-fill damage" style={{ transform: `scaleX(${DAMAGE[stage] / 100})` }} />
                  </div>
                </div>
                <div className="qp-meter">
                  <div className="qp-meter-head">
                    <span>What the patient feels</span>
                    <strong className={stage === 4 ? 'alarm' : ''}>{current.feels}</strong>
                  </div>
                  <div className="qp-meter-track">
                    <div className="qp-meter-fill felt" style={{ transform: `scaleX(${FELT[stage] / 100})` }} />
                  </div>
                </div>
              </div>
            </div>

            <div className="qp-visual">
              <motion.div className="qp-retina-wrap" style={{ scale: retinaScale, rotate: retinaRotate }}>
                <Retina stage={stage} drawProgress={drawProgress} showAi={showAi} />
              </motion.div>

              <div className="qp-hud" aria-live="polite">
                <span className={`qp-hud-dot g${stage}`} />
                <span className="qp-hud-text">
                  {stage === 0 ? 'No signs of retinopathy' : `Grade ${stage} · ${current.name}`}
                </span>
                <button
                  type="button"
                  className={`qp-ai-toggle${showAi ? ' on' : ''}`}
                  onClick={() => setShowAi((v) => !v)}
                  aria-pressed={showAi}
                >
                  {showAi ? 'Hide' : 'Show'} what VITREOUS flags
                </button>
              </div>

              <p className="qp-caption">
                {stage === 0
                  ? 'Keep scrolling to watch the disease progress.'
                  : stage < 4
                    ? 'Caught at this point, treatment can prevent vision loss.'
                    : 'By the time it is felt, the damage may be permanent.'}
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="qp-stats">
        <Stat
          end={93}
          suffix=" million"
          label="people worldwide are living with diabetic retinopathy."
          source="Yau et al., Diabetes Care, 2012"
        />
        <Stat
          end={3}
          prefix="1 in "
          label="people with diabetes has some degree of retinopathy."
          source="Yau et al., Diabetes Care, 2012"
        />
        <Stat
          end={74}
          suffix=" million"
          label="adults in India are living with diabetes."
          source="IDF Diabetes Atlas, 10th edition, 2021"
        />
      </div>
    </section>
  );
}
