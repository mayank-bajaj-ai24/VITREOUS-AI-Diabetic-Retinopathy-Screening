import React from 'react';
import { useReveal } from '../hooks/useReveal';

/* ─── Tiny live widgets ─── */

function TimerRing() {
  const circumference = 2 * Math.PI * 30;
  const offset = circumference * (1 - 0.78); // ~78% filled

  return (
    <div className="widget-ring">
      <svg viewBox="0 0 76 76" aria-hidden="true">
        <circle
          cx="38" cy="38" r="30"
          fill="none" stroke="#E3E8EE" strokeWidth="4"
        />
        <circle
          cx="38" cy="38" r="30"
          fill="none" stroke="#0EA5A4" strokeWidth="4"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          transform="rotate(-90 38 38)"
        />
      </svg>
      <div className="ring-label">
        <span style={{ fontSize: '1rem', fontWeight: 800, color: '#0B1220' }}>~2</span>
        <span>min</span>
      </div>
    </div>
  );
}

function QueueWidget() {
  return (
    <div className="widget-queue" aria-hidden="true">
      <div className="q-item">
        <span className="q-badge q-badge-urgent">Urgent</span>
        <span>Sunita D.</span>
      </div>
      <div className="q-item">
        <span className="q-badge q-badge-wait">Waiting</span>
        <span>Ramesh K.</span>
      </div>
      <div className="q-item" style={{ opacity: 0.4 }}>
        <span className="q-badge q-badge-wait">Waiting</span>
        <span>Savitri B.</span>
      </div>
    </div>
  );
}

function ReportWidget() {
  return (
    <div className="widget-report" aria-hidden="true">
      <span className="rpt-light rpt-g" />
      <div>
        <p className="rpt-name">Eye check report</p>
        <p className="rpt-grade">No changes found</p>
      </div>
    </div>
  );
}

function RetakeWidget() {
  return (
    <div className="widget-retake" aria-hidden="true">
      <div className="rt-step faded">
        <span className="rt-icon" style={{ color: '#F5A524', borderColor: '#F5A524' }}>!</span>
        <span>A little blurry — retake</span>
      </div>
      <div className="rt-step done">
        <span className="rt-icon" style={{ color: '#2FA36B', borderColor: '#2FA36B' }}>✓</span>
        <span>Photo is clear</span>
      </div>
    </div>
  );
}

/* ─── Card data ─── */
const CARDS = [
  {
    widget: <TimerRing />,
    title: 'An answer in about two minutes',
    desc: 'VITREOUS aims to complete a check-up in under two minutes, from photo to result.',
  },
  {
    widget: <QueueWidget />,
    title: 'Urgent cases go first',
    desc: `Cases that need a doctor's attention are moved to the top of the queue automatically.`,
  },
  {
    widget: <ReportWidget />,
    title: 'A report you can hold',
    desc: 'A printed report with a clear result and next steps, ready to take home.',
  },
  {
    widget: <RetakeWidget />,
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
        <h2 className="bento-h2" id="bento-h2">
          Quick, clear, and built to get it right.
        </h2>
      </div>

      <div
        className={`bento-grid reveal-stagger ${visible ? 'visible' : ''}`}
        ref={ref}
      >
        {CARDS.map((card, i) => (
          <div className="bento-card" key={i}>
            <div className="bento-widget">{card.widget}</div>
            <h3 className="bento-title">{card.title}</h3>
            <p className="bento-desc">{card.desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
