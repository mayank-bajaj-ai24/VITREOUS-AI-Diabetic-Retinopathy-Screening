import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';

const LOGO = '/vitreous_logo.png';

export default function Nav({ onCta }) {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <nav
      className={`l-nav${scrolled ? ' scrolled' : ''}`}
      role="navigation"
      aria-label="Main navigation"
    >
      <div className="l-nav-inner">
        <a href="#top" className="nav-logo" aria-label="VITREOUS">
          <img src={LOGO} alt="" aria-hidden="true" />
          VITREOUS
        </a>

        <div className="nav-links" role="list">
          <a href="#quiet-problem" role="listitem" onClick={(e) => { e.preventDefault(); document.getElementById('quiet-problem')?.scrollIntoView({ behavior: 'smooth' }); }}>The story</a>
          <a href="#tutorial" role="listitem" onClick={(e) => { e.preventDefault(); document.getElementById('tutorial')?.scrollIntoView({ behavior: 'smooth' }); }}>How it works</a>
          <a href="#trust" role="listitem" onClick={(e) => { e.preventDefault(); document.getElementById('trust')?.scrollIntoView({ behavior: 'smooth' }); }}>Trust</a>
          <a href="#faq" role="listitem" onClick={(e) => { e.preventDefault(); document.getElementById('faq')?.scrollIntoView({ behavior: 'smooth' }); }}>FAQ</a>
        </div>

        <Link to="/login" style={{ textDecoration: 'none' }}>
          <button
            className="nav-cta"
            aria-label="Login to VITREOUS Dashboard"
          >
            Login to Dashboard
          </button>
        </Link>
      </div>
    </nav>
  );
}
