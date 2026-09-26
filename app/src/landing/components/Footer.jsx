import React from 'react';
import { Shield, Heart, ExternalLink, ArrowUp } from 'lucide-react';

const LOGO = '/vitreous_logo.png';

export default function Footer() {
  const scrollToTop = () => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <footer className="l-footer" role="contentinfo">
      <div className="footer-inner">
        {/* Top 4-Column Grid */}
        <div className="footer-top-grid">
          {/* Column 1: Brand & Mission */}
          <div className="footer-brand-col">
            <div className="footer-brand-header">
              <img src={LOGO} alt="VITREOUS Logo" className="footer-logo-img" />
              <span className="footer-brand-title">VITREOUS</span>
            </div>
            <p className="footer-brand-tagline">
              AI-Driven Diabetic Retinopathy Screening &amp; Clinical Triage.
            </p>
            <p className="footer-brand-description">
              Bringing specialist-grade diabetic retinopathy triage to frontline Indian health centres,
              detecting preventable vision loss early.
            </p>
            <div className="footer-badge-pill">
              <span>🇮🇳 Built for Smart India Hackathon 2026</span>
            </div>
          </div>

          {/* Column 2: Navigation */}
          <div className="footer-links-col">
            <h4 className="footer-heading">Product &amp; Flow</h4>
            <ul className="footer-nav-list">
              <li><a href="#quiet-problem">The Story</a></li>
              <li><a href="#tutorial">How It Works</a></li>
              <li><a href="#trust">Clinical Trust</a></li>
              <li><a href="#places">Care Settings</a></li>
              <li><a href="#faq">Frequently Asked Questions</a></li>
            </ul>
          </div>

          {/* Column 3: Clinical Standards */}
          <div className="footer-links-col">
            <h4 className="footer-heading">Clinical Standards</h4>
            <ul className="footer-nav-list">
              <li><span className="footer-spec-text">ICDR 5-Stage Protocol</span></li>
              <li><span className="footer-spec-text">Pre-Inference Quality Gate</span></li>
              <li><span className="footer-spec-text">Offline SQLite Edge Inference</span></li>
              <li><span className="footer-spec-text">DPDP Act 2023 Compliant</span></li>
              <li><span className="footer-spec-text">Tele-Ophthalmology Link</span></li>
            </ul>
          </div>

          {/* Column 4: Hackathon & Team */}
          <div className="footer-links-col">
            <h4 className="footer-heading">Team ByteCrew</h4>
            <ul className="footer-nav-list">
              <li><span className="footer-spec-text">Smart India Hackathon 2026</span></li>
              <li><span className="footer-spec-text">Problem Statement 26038</span></li>
              <li><span className="footer-spec-text">MedTech / HealthTech Track</span></li>
              <li><a href="https://github.com/mayank-bajaj-ai24/VITREOUS-AI-Diabetic-Retinopathy-Screening" target="_blank" rel="noopener noreferrer" className="footer-ext-link">GitHub Repository <ExternalLink size={12} /></a></li>
            </ul>
          </div>
        </div>

        {/* Bottom Bar: Disclaimer & Copyright */}
        <div className="footer-bottom-bar">
          <p className="footer-disclaimer-text">
            <strong>Medical Disclaimer:</strong> VITREOUS is a clinical decision-support and screening aid
            engineered to assist trained primary healthcare workers in rural settings. It does not replace a comprehensive
            dilated ophthalmic examination. All treatment and clinical determinations require verification and sign-off
            by a licensed medical practitioner.
          </p>

          <div className="footer-legal-row">
            <span>© 2026 Team ByteCrew. All rights reserved.</span>
            <button 
              type="button" 
              onClick={scrollToTop} 
              className="footer-back-to-top"
              aria-label="Back to top"
            >
              <span>Back to top</span>
              <ArrowUp size={14} />
            </button>
          </div>
        </div>
      </div>
    </footer>
  );
}
