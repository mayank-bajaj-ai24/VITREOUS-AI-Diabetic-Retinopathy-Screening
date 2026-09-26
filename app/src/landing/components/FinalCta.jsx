import React, { useRef } from 'react';
import { motion, useScroll, useTransform, useSpring, useMotionValue, useReducedMotion } from 'framer-motion';
import { ArrowRight, ShieldCheck, CheckCircle2, Stethoscope } from 'lucide-react';
import SplitReveal from './SplitReveal';

/* An eye that opens as the card scrolls in; the pupil follows the pointer */
function OpeningEye({ open, lookX, lookY }) {
  const lid = useTransform(open, (o) => `M10 60 Q120 ${60 - 58 * o} 230 60 Q120 ${60 + 58 * o} 10 60 Z`);
  const lashLine = useTransform(open, (o) => `M10 60 Q120 ${60 - 58 * o} 230 60`);

  return (
    <svg className="cta-eye" viewBox="0 0 240 120" aria-hidden="true">
      <defs>
        <clipPath id="ctaEyeClip">
          <motion.path d={lid} />
        </clipPath>
        <radialGradient id="ctaIris">
          <stop offset="0%" stopColor="#374151" />
          <stop offset="55%" stopColor="#9ca3af" />
          <stop offset="100%" stopColor="#111827" />
        </radialGradient>
      </defs>

      <g clipPath="url(#ctaEyeClip)">
        <rect width="240" height="120" fill="#f8fafc" />
        <motion.g style={{ x: lookX, y: lookY }}>
          <circle cx="120" cy="60" r="34" fill="url(#ctaIris)" />
          {Array.from({ length: 18 }, (_, i) => {
            const a = (i / 18) * Math.PI * 2;
            return (
              <line
                key={i}
                x1={120 + Math.cos(a) * 15}
                y1={60 + Math.sin(a) * 15}
                x2={120 + Math.cos(a) * 32}
                y2={60 + Math.sin(a) * 32}
                stroke="#ffffff"
                strokeOpacity="0.28"
                strokeWidth="1.2"
              />
            );
          })}
          <circle cx="120" cy="60" r="14" fill="#070b10" />
          <circle cx="112" cy="52" r="5" fill="#fff" opacity="0.85" />
        </motion.g>
      </g>
      <motion.path d={lashLine} fill="none" stroke="#f5f5f7" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  );
}

export default function FinalCta({ onCta }) {
  const cardRef = useRef(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: cardRef, offset: ['start end', 'start 0.25'] });
  const open = useTransform(scrollYProgress, [0.35, 1], reduce ? [1, 1] : [0.02, 1]);
  const cardScale = useTransform(scrollYProgress, [0, 1], reduce ? [1, 1] : [0.9, 1]);
  const radius = useTransform(scrollYProgress, [0, 1], reduce ? [44, 44] : [120, 44]);

  const px = useMotionValue(0);
  const py = useMotionValue(0);
  const lookX = useSpring(px, { stiffness: 120, damping: 18 });
  const lookY = useSpring(py, { stiffness: 120, damping: 18 });
  const glowTarget = useMotionValue(0);
  const glowX = useSpring(glowTarget, { stiffness: 60, damping: 20 });

  const handlePointer = (e) => {
    if (reduce) return;
    const rect = cardRef.current.getBoundingClientRect();
    const nx = (e.clientX - rect.left) / rect.width - 0.5;
    const ny = (e.clientY - rect.top) / rect.height - 0.5;
    px.set(nx * 44);
    py.set(ny * 22);
    glowTarget.set(nx * 360);
  };

  const handleLeave = () => {
    px.set(0);
    py.set(0);
    glowTarget.set(0);
  };

  return (
    <section className="final-cta-section" id="cta" aria-labelledby="final-cta-h2">
      <div className="final-cta-wrapper">
        <motion.div
          className="cta-card"
          ref={cardRef}
          style={{ scale: cardScale, borderRadius: radius }}
          onPointerMove={handlePointer}
          onPointerLeave={handleLeave}
        >
          {/* Glow drifts toward the pointer, like light entering the eye */}
          <motion.div className="cta-radial-glow" style={{ x: glowX }} />

          {/* Centered Content */}
          <div className="cta-content">
            <OpeningEye open={open} lookX={lookX} lookY={lookY} />

            <SplitReveal
              className="cta-h2"
              id="final-cta-h2"
              lines={['Catch it early.', { text: 'Keep the sight.', className: 'cta-h2-highlight' }]}
            />

            <p className="cta-sub">
              Over 80% of vision loss caused by diabetes can be prevented with a simple annual screening.
              VITREOUS brings specialist-grade triage to the primary health centres where rural communities already seek care.
            </p>

            <div className="cta-btns">
              <motion.button 
                className="btn-primary cta-btn-light" 
                onClick={onCta}
                whileHover={{ scale: 1.03 }}
                whileTap={{ scale: 0.98 }}
              >
                <span>See how it works</span>
                <ArrowRight size={18} />
              </motion.button>

              <motion.button 
                className="btn-secondary cta-btn-ghost" 
                onClick={() => document.getElementById('faq')?.scrollIntoView({ behavior: 'smooth' })}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
              >
                For clinics and doctors
              </motion.button>
            </div>

            {/* Reassurance Trust Row */}
            <div className="cta-trust-row">
              <div className="cta-trust-item">
                <CheckCircle2 size={16} className="trust-icon" />
                <span>Zero special patient training required</span>
              </div>
              <div className="cta-trust-dot">·</div>
              <div className="cta-trust-item">
                <ShieldCheck size={16} className="trust-icon" />
                <span>Works offline in remote sub-centres</span>
              </div>
              <div className="cta-trust-dot">·</div>
              <div className="cta-trust-item">
                <Stethoscope size={16} className="trust-icon" />
                <span>Human-in-the-loop doctor verification</span>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
