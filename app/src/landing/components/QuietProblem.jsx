import React from 'react';
import { useReveal, useCountUp } from '../hooks/useReveal';

function Stat({ end, suffix = '', prefix = '', label, source }) {
  const [ref, visible] = useReveal();
  const count = useCountUp(end, visible, 1800);

  return (
    <div className="stat-block-lg" ref={ref}>
      <div className="stat-num-xl">
        {prefix}{count.toLocaleString('en-IN')}{suffix}
      </div>
      <p className="stat-context">{label}</p>
      {source && <p className="stat-source">{source}</p>}
    </div>
  );
}

export default function QuietProblem() {
  const [ref, visible] = useReveal({ threshold: 0.1 });

  return (
    <section
      className="quiet-section"
      id="quiet-problem"
      aria-labelledby="quiet-h2"
    >
      <div className="quiet-inner">
        <div ref={ref} className={`reveal-stagger ${visible ? 'visible' : ''}`}>
          <div className="section-label">
            <span className="dot" aria-hidden="true" />
            The quiet problem
          </div>

          <h2 className="quiet-h2" id="quiet-h2">
            It rarely hurts.<br />That's what makes it dangerous.
          </h2>

          <p className="quiet-copy">
            Diabetes can slowly damage the tiny blood vessels at the back of the
            eye. Most people feel nothing until the damage is serious. A simple
            check-up can catch it early — but for millions of people in rural
            India, the nearest eye specialist is a long journey away.
          </p>
        </div>

        <div className="stats-duo reveal" style={{ opacity: visible ? 1 : 0, transform: visible ? 'none' : 'translateY(18px)', transition: 'opacity 0.52s ease-out 0.2s, transform 0.52s ease-out 0.2s' }}>
          <Stat
            end={93}
            suffix=" million"
            label="People worldwide live with diabetic eye disease"
            source="[add source]"
          />
          <Stat
            end={70000}
            prefix="1 : "
            label="Roughly one eye doctor for every 70,000 people in rural India"
            source="[add source]"
          />
        </div>
      </div>
    </section>
  );
}
