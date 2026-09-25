import React from 'react';
import { useReveal } from '../hooks/useReveal';

const ROWS = [
  {
    icon: '👩‍⚕️',
    text: 'A doctor reviews every case that needs attention.',
  },
  {
    icon: '📷',
    text: "If a photo isn't clear enough, VITREOUS says so and asks for a new one instead of guessing.",
  },
  {
    icon: '🔍',
    text: 'VITREOUS shows where it looked, so a doctor can check its thinking.',
  },
];

export default function Trust() {
  const [ref, visible] = useReveal({ threshold: 0.15 });

  return (
    <section
      className="trust-section"
      id="trust"
      aria-labelledby="trust-h2"
    >
      <div className="trust-inner">
        <div className="section-label light">
          <span className="dot" aria-hidden="true" />
          Why you can trust it
        </div>

        <h2 className="trust-h2" id="trust-h2">
          A helper for the doctor.<br />Never a replacement.
        </h2>

        <div className="trust-rows" ref={ref}>
          {ROWS.map((row, i) => (
            <div
              key={i}
              className={`trust-row${visible ? ' visible' : ''}`}
            >
              <div className="trust-icon-wrap" aria-hidden="true">
                {row.icon}
              </div>
              <p className="trust-row-text">{row.text}</p>
            </div>
          ))}
        </div>

        <p className="trust-note">
          VITREOUS is a screening aid. It does not replace a medical diagnosis.
        </p>
      </div>
    </section>
  );
}
