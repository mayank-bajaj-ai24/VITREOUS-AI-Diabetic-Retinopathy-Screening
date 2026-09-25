import React from 'react';
import { motion } from 'framer-motion';
import { ArrowRight, ShieldCheck, CheckCircle2, Stethoscope, Sparkles } from 'lucide-react';

export default function FinalCta({ onCta }) {
  return (
    <section className="final-cta-section" id="cta" aria-labelledby="final-cta-h2">
      <div className="final-cta-wrapper">
        <motion.div 
          className="cta-card"
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-60px" }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
        >
          {/* Subtle Ambient Radial Glow */}
          <div className="cta-radial-glow" />

          {/* Centered Content */}
          <div className="cta-content">
            <div className="cta-eyebrow">
              <Sparkles size={14} className="cta-eyebrow-icon" />
              <span>PREVENTION AT THE FRONTLINE</span>
            </div>

            <h2 className="cta-h2" id="final-cta-h2">
              Catch it early.<br />
              <span className="cta-h2-highlight">Keep the sight.</span>
            </h2>

            <p className="cta-sub">
              Over 80% of vision loss caused by diabetes can be prevented with a simple annual screening.
              VITREOUS brings specialist-grade triage to the primary health centres where rural communities already seek care.
            </p>

            <div className="cta-btns">
              <motion.button 
                className="btn-primary cta-btn-teal" 
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
