import React, { useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence, useInView, animate } from 'framer-motion';
import { useReveal } from '../hooks/useReveal';
import SplitReveal from './SplitReveal';

/* ─── Tiny live widgets: each one plays out the claim on its card ─── */

function useLoop(active, steps, interval) {
  const [step, setStep] = useState(0);
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setStep((s) => (s + 1) % steps), interval);
    return () => clearInterval(id);
  }, [active, steps, interval]);
  return step;
}

function TimerRing({ active }) {
  const circumference = 2 * Math.PI * 30;
  const [secs, setSecs] = useState(0);

  useEffect(() => {
    if (!active) return;
    const controls = animate(0, 120, {
      duration: 2.2,
      ease: [0.16, 1, 0.3, 1],
      onUpdate: (v) => setSecs(Math.round(v)),
    });
    return () => controls.stop();
  }, [active]);

  return (
    <div className="widget-ring">
      <svg viewBox="0 0 76 76" aria-hidden="true">
        <circle cx="38" cy="38" r="30" fill="none" stroke="#E3E8EE" strokeWidth="4" />
        <circle
          cx="38" cy="38" r="30"
          fill="none" stroke="#0B1220" strokeWidth="4"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - (secs / 120) * 0.92)}
          transform="rotate(-90 38 38)"
        />
      </svg>
      <div className="ring-label">
        <span className="ring-time">{Math.floor(secs / 60)}:{String(secs % 60).padStart(2, '0')}</span>
        <span>min</span>
      </div>
    </div>
  );
}

const PATIENTS = {
  ramesh: { name: 'Ramesh K.', urgent: false },
  savitri: { name: 'Savitri B.', urgent: false },
  sunita: { name: 'Sunita D.', urgent: true },
};
// 0: normal queue · 1: an urgent case arrives at the back · 2: it jumps to the front
const QUEUE_STEPS = [
  ['ramesh', 'savitri'],
  ['ramesh', 'savitri', 'sunita'],
  ['sunita', 'ramesh', 'savitri'],
  ['sunita', 'ramesh', 'savitri'],
];

function QueueWidget({ active }) {
  const step = useLoop(active, QUEUE_STEPS.length, 1300);
  return (
    <div className="widget-queue" aria-hidden="true">
      <AnimatePresence initial={false}>
        {QUEUE_STEPS[step].map((id) => {
          const p = PATIENTS[id];
          return (
            <motion.div
              key={id}
              layout
              className={`q-item${p.urgent ? ' urgent' : ''}`}
              initial={{ opacity: 0, x: 30 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -30 }}
              transition={{ type: 'spring', stiffness: 320, damping: 30 }}
            >
              <span className={`q-badge ${p.urgent ? 'q-badge-urgent' : 'q-badge-wait'}`}>
                {p.urgent ? 'Urgent' : 'Waiting'}
              </span>
              <span>{p.name}</span>
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>
  );
}

function ReportWidget({ active }) {
  return (
    <div className="widget-printer" aria-hidden="true">
      <div className="printer-slot" />
      <div className="printer-paper-clip">
        <motion.div
          className="widget-report"
          initial={{ y: '-105%' }}
          animate={active ? { y: 0 } : { y: '-105%' }}
          transition={{ duration: 1.6, delay: 0.3, ease: [0.45, 0, 0.2, 1] }}
        >
          <span className={`rpt-light rpt-g${active ? ' pulse' : ''}`} />
          <div>
            <p className="rpt-name">Eye check report</p>
            <p className="rpt-grade">No changes found</p>
          </div>
        </motion.div>
      </div>
    </div>
  );
}

function RetakeWidget({ active }) {
  // 0: blurry capture flagged · 1: retaken, clear
  const step = useLoop(active, 2, 2200);
  const clear = active && step === 1;

  return (
    <div className="widget-retake" aria-hidden="true">
      <img
        className="rt-thumb"
        src="/retina_fundus.jpg"
        alt=""
        style={{ filter: clear ? 'blur(0)' : 'blur(3px)' }}
      />
      <div className="rt-steps">
        <motion.div
          className={`rt-step${clear ? ' faded' : ''}`}
          animate={!clear && active ? { x: [0, -5, 5, -3, 3, 0] } : { x: 0 }}
          transition={{ duration: 0.45, delay: 0.2 }}
        >
          <span className="rt-icon" style={{ color: '#F5A524', borderColor: '#F5A524' }}>!</span>
          <span>A little blurry — retake</span>
        </motion.div>
        <div className={`rt-step rt-step-ok${clear ? ' done' : ''}`}>
          <span className="rt-icon" style={{ color: '#2FA36B', borderColor: '#2FA36B' }}>✓</span>
          <span>Photo is clear</span>
        </div>
      </div>
    </div>
  );
}

function LiveWidget({ Widget }) {
  const ref = useRef(null);
  const inView = useInView(ref, { amount: 0.6 });
  return (
    <div className="bento-widget" ref={ref}>
      <Widget active={inView} />
    </div>
  );
}

/* ─── Card data ─── */
const CARDS = [
  {
    widget: TimerRing,
    title: 'An answer in about two minutes',
    desc: 'VITREOUS aims to complete a check-up in under two minutes, from photo to result.',
  },
  {
    widget: QueueWidget,
    title: 'Urgent cases go first',
    desc: `Cases that need a doctor's attention are moved to the top of the queue automatically.`,
  },
  {
    widget: ReportWidget,
    title: 'A report you can hold',
    desc: 'A printed report with a clear result and next steps, ready to take home.',
  },
  {
    widget: RetakeWidget,
    title: 'Clear photos, every time',
    desc: `If a photo isn't sharp enough, VITREOUS catches it right away and guides the retake.`,
  },
];

export default function AfterBento() {
  const [ref, visible] = useReveal({ threshold: 0.08 });

  return (
    <section className="bento-section" aria-labelledby="bento-h2">
      <div className="bento-header">
        <div className="section-label">
          <span className="dot" aria-hidden="true" />
          What happens after
        </div>
        <SplitReveal className="bento-h2" id="bento-h2" lines={['Quick, clear, and built', 'to get it right.']} />
      </div>

      <div
        className={`bento-grid reveal-stagger ${visible ? 'visible' : ''}`}
        ref={ref}
      >
        {CARDS.map((card, i) => (
          <div className="bento-card" key={i}>
            <LiveWidget Widget={card.widget} />
            <h3 className="bento-title">{card.title}</h3>
            <p className="bento-desc">{card.desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
