import React from 'react';
import { motion } from 'framer-motion';
import { 
  ShieldCheck, Activity, CheckCircle2, 
  ArrowRight
} from 'lucide-react';

export default function Hero({ onCta }) {
  return (
    <section className="landing-hero-wrapper" id="top" aria-labelledby="hero-h1">
      {/* Dynamic Cinematic Medical Video Background */}
      <div className="hero-video-backdrop" aria-hidden="true">
        <video
          autoPlay
          loop
          muted
          playsInline
          className="hero-background-video"
          poster="/hero_video_thumb.jpg"
        >
          <source src="/hero_bg.mp4" type="video/mp4" />
          <source src="/Create_a_premium_medical_visua.mp4" type="video/mp4" />
        </video>
        <div className="hero-video-overlay" />
      </div>

      <div className="landing-hero landing-hero-centered">
        {/* Centered Content: Magnified Headline & Story Copy */}
        <motion.div 
          className="hero-content hero-content-centered"
          initial={{ opacity: 0, y: 28 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
        >
          <motion.div 
            className="hero-eyebrow" 
            aria-hidden="true"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
          >
            <span className="dot" />
            <span>Eye check-ups for people with diabetes</span>
          </motion.div>

          <h1 className="hero-h1" id="hero-h1">
            A photo of the eye.<br />
            A clear answer, <span className="hero-h1-accent">in minutes.</span>
          </h1>

          <p className="hero-sub">
            VITREOUS brings hospital-grade diabetic eye screening to primary health centres across India.
            Non-invasive, fast, and reviewed by ophthalmologists when it counts.
          </p>

          <div className="hero-btns">
            <motion.button 
              className="btn-primary" 
              onClick={onCta}
              whileHover={{ scale: 1.03 }}
              whileTap={{ scale: 0.98 }}
            >
              <span>See how it works</span>
              <ArrowRight size={18} />
            </motion.button>
            
            <motion.button 
              className="btn-secondary" 
              onClick={() => document.getElementById('faq')?.scrollIntoView({ behavior: 'smooth' })}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
            >
              For clinics and doctors
            </motion.button>
          </div>

          {/* Clinical Metric Pill Group */}
          <div className="hero-trust-pills">
            <div className="hero-pill-item">
              <CheckCircle2 size={16} className="pill-icon teal" />
              <span>ICDR 5-Grade Standard</span>
            </div>
            <div className="hero-pill-divider" />
            <div className="hero-pill-item">
              <Activity size={16} className="pill-icon blue" />
              <span>&lt;48ms On-Device Triage</span>
            </div>
            <div className="hero-pill-divider" />
            <div className="hero-pill-item">
              <ShieldCheck size={16} className="pill-icon green" />
              <span>DPDP Act 2023 Compliant</span>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
