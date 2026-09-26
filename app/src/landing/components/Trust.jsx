import React, { useEffect, useRef, useState } from 'react';
import { motion, useScroll, useTransform, useInView, useMotionValueEvent, AnimatePresence, animate } from 'framer-motion';
import { Check, RotateCcw, PenLine } from 'lucide-react';
import SplitReveal from './SplitReveal';

const FUNDUS = '/retina_fundus.jpg';
const FOCUS_MIN = 60;

/* ─── Demo 1: the quality gate refuses blurry photos ─── */
function GateDemo() {
  const ref = useRef(null);
  const inView = useInView(ref, { once: true, amount: 0.6 });
  const [focus, setFocus] = useState(22);
  const [touched, setTouched] = useState(false);

  // Once in view, sweep the focus up so the gate flips from reject to accept
  useEffect(() => {
    if (!inView || touched) return;
    const controls = animate(22, 88, {
      duration: 2.4,
      delay: 0.6,
      ease: [0.65, 0, 0.35, 1],
      onUpdate: (v) => setFocus(Math.round(v)),
    });
    return () => controls.stop();
  }, [inView, touched]);

  const ok = focus >= FOCUS_MIN;
  const blur = ((100 - focus) / 100) * 9;

  return (
    <div className="tdemo tdemo-gate" ref={ref}>
      <div className="tdemo-photo">
        <img src={FUNDUS} alt="Fundus photograph used in the quality gate demo" style={{ filter: `blur(${blur}px)` }} />
        <div className={`gate-verdict ${ok ? 'ok' : 'bad'}`} aria-live="polite">
          {ok ? 'Accepted — sent for grading' : 'Out of focus — please retake'}
        </div>
      </div>

      <label className="gate-slider">
        <span className="gate-slider-head">
          <span>Image sharpness</span>
          <span className="gate-slider-hint">Drag to try it</span>
        </span>
        <span className="gate-track">
          <input
            type="range"
            min="0"
            max="100"
            value={focus}
            onChange={(e) => {
              setTouched(true);
              setFocus(Number(e.target.value));
            }}
            style={{ '--fill': `${focus}%` }}
            className={ok ? 'ok' : 'bad'}
            aria-label="Image sharpness"
          />
          <span className="gate-threshold" style={{ left: `${FOCUS_MIN}%` }}>
            <span>minimum</span>
          </span>
        </span>
      </label>
    </div>
  );
}

/* ─── Demo 2: two independent heatmaps ─── */
const CAM_MODES = [
  { id: 'grad', label: 'Grad-CAM' },
  { id: 'score', label: 'Score-CAM' },
  { id: 'both', label: 'Overlap' },
];

function CamDemo() {
  const [mode, setMode] = useState('grad');

  return (
    <div className="tdemo tdemo-cam">
      <div className="tdemo-photo">
        <img src={FUNDUS} alt="Fundus photograph with an illustrative attention heatmap" />
        <div className={`cam-layer cam-grad${mode !== 'score' ? ' on' : ''}${mode === 'both' ? ' dim' : ''}`} />
        <div className={`cam-layer cam-score${mode !== 'grad' ? ' on' : ''}${mode === 'both' ? ' dim' : ''}`} />
        <div className={`cam-agree${mode === 'both' ? ' on' : ''}`}>
          <span>Both methods agree here</span>
        </div>
        <span className="tdemo-note">Illustrative heatmap</span>
      </div>

      <div className="cam-switch" role="tablist" aria-label="Explanation method">
        {CAM_MODES.map((m) => (
          <button
            key={m.id}
            type="button"
            role="tab"
            aria-selected={mode === m.id}
            className={mode === m.id ? 'active' : ''}
            onClick={() => setMode(m.id)}
          >
            {mode === m.id && <motion.span layoutId="camSwitch" className="cam-switch-bg" transition={{ type: 'spring', stiffness: 400, damping: 34 }} />}
            <span>{m.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ─── Demo 3: the doctor signs off ─── */
const REVIEW_STEPS = ['Photo passed quality gate', 'Graded by VITREOUS', 'Heatmaps attached'];

function SignoffDemo() {
  const [signed, setSigned] = useState(false);

  return (
    <div className="tdemo tdemo-sign">
      <div className="sign-card">
        <div className="sign-head">
          <div>
            <p className="sign-kicker">Example referral</p>
            <p className="sign-title">Grade 3 · Severe NPDR</p>
          </div>
          <span className={`sign-status${signed ? ' done' : ''}`}>{signed ? 'Signed' : 'Awaiting doctor'}</span>
        </div>

        <ul className="sign-steps">
          {REVIEW_STEPS.map((s) => (
            <li key={s}>
              <Check size={15} />
              {s}
            </li>
          ))}
          <li className={signed ? '' : 'pending'}>
            {signed ? <Check size={15} /> : <span className="sign-pending-dot" />}
            Reviewed by ophthalmologist
          </li>
        </ul>

        <AnimatePresence>
          {signed && (
            <motion.div
              className="sign-stamp"
              initial={{ opacity: 0, scale: 1.6, rotate: -18 }}
              animate={{ opacity: 1, scale: 1, rotate: -8 }}
              exit={{ opacity: 0, scale: 0.9 }}
              transition={{ type: 'spring', stiffness: 380, damping: 18 }}
            >
              Referral signed
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <button type="button" className={`sign-btn${signed ? ' reset' : ''}`} onClick={() => setSigned((v) => !v)}>
        {signed ? <RotateCcw size={16} /> : <PenLine size={16} />}
        <span>{signed ? 'Reset the example' : 'Sign as the doctor'}</span>
      </button>
    </div>
  );
}

const PANELS = [
  {
    kicker: 'Quality gate',
    title: "If the photo isn't clear, it won't guess.",
    body: 'Before any grading, VITREOUS checks focus, exposure and whether the retina is fully in frame. A poor photo is sent back for a retake while the patient is still in the chair.',
    Demo: GateDemo,
  },
  {
    kicker: 'Explainable',
    title: 'It shows where it looked.',
    body: 'Every result comes with two independent heatmaps, Grad-CAM and Score-CAM. When both point to the same place, the doctor can see the finding is grounded in the retina itself.',
    Demo: CamDemo,
  },
  {
    kicker: 'Doctor in the loop',
    title: 'A doctor has the final word.',
    body: 'Cases that need attention go to an ophthalmologist, who reviews the photo and heatmaps before signing the referral. VITREOUS never issues a diagnosis on its own.',
    Demo: SignoffDemo,
  },
];

function Panel({ panel, index, total, progress, active }) {
  const ref = useRef(null);
  // Earlier panels shrink back slightly as later ones stack over them
  const scale = useTransform(progress, [index / total, 1], [1, 1 - (total - 1 - index) * 0.045]);
  const { Demo } = panel;

  // Feed the pointer position to CSS so the glow behind the glass follows it
  const handlePointer = (e) => {
    // The rect is scaled; divide back out so the glow lands under the pointer
    const r = ref.current.getBoundingClientRect();
    const k = scale.get();
    ref.current.style.setProperty('--mx', `${(e.clientX - r.left) / k}px`);
    ref.current.style.setProperty('--my', `${(e.clientY - r.top) / k}px`);
  };

  return (
    <div className="trust-panel-slot" style={{ top: `calc(var(--nav-h) + 32px + ${index * 26}px)` }}>
      <motion.article
        ref={ref}
        className={`glass-window trust-window${active ? ' active' : ''}`}
        style={{ scale }}
        onPointerMove={handlePointer}
      >
        <div className="glass-sheen" aria-hidden="true" />

        <div className="trust-panel">
          <div className="trust-panel-copy">
            <p className="trust-panel-kicker">{panel.kicker}</p>
            <h3 className="trust-panel-title">{panel.title}</h3>
            <p className="trust-panel-body">{panel.body}</p>
          </div>
          <Demo />
        </div>
      </motion.article>
    </div>
  );
}

export default function Trust() {
  const stackRef = useRef(null);
  const { scrollYProgress } = useScroll({ target: stackRef, offset: ['start start', 'end end'] });
  const [activeIdx, setActiveIdx] = useState(0);

  // The topmost panel in the stack is the "focused" window
  useMotionValueEvent(scrollYProgress, 'change', (p) => {
    const next = Math.min(PANELS.length - 1, Math.floor(p * PANELS.length));
    setActiveIdx((prev) => (prev === next ? prev : next));
  });

  return (
    <section className="trust-section" id="trust" aria-labelledby="trust-h2">
      <div className="trust-inner">
        <div className="section-label light">
          <span className="dot" aria-hidden="true" />
          Why you can trust it
        </div>

        <SplitReveal className="trust-h2" id="trust-h2" lines={['A helper for the doctor.', 'Never a replacement.']} />

        <div className="trust-stack" ref={stackRef}>
          {PANELS.map((p, i) => (
            <Panel key={p.kicker} panel={p} index={i} total={PANELS.length} progress={scrollYProgress} active={i === activeIdx} />
          ))}
        </div>

        <p className="trust-note">VITREOUS is a screening aid. It does not replace a medical diagnosis.</p>
      </div>
    </section>
  );
}
