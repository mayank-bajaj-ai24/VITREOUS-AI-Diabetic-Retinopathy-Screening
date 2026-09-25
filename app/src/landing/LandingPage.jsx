import React, { useCallback } from 'react';
import './landing.css';

import AnnouncementBar from './components/AnnouncementBar';
import Nav from './components/Nav';
import Hero from './components/Hero';
import QuietProblem from './components/QuietProblem';
import Tutorial from './components/Tutorial';
import Trust from './components/Trust';
import AfterBento from './components/AfterBento';
import PlacesGrid from './components/PlacesGrid';
import Faq from './components/Faq';
import FinalCta from './components/FinalCta';
import Footer from './components/Footer';

export default function LandingPage() {
  const scrollToTutorial = useCallback(() => {
    document.getElementById('tutorial')?.scrollIntoView({ behavior: 'smooth' });
  }, []);

  return (
    <div className="landing-root">
      <AnnouncementBar />
      <Nav onCta={scrollToTutorial} />
      <Hero onCta={scrollToTutorial} />
      <QuietProblem />
      <Tutorial />
      <Trust />
      <AfterBento />
      <PlacesGrid />
      <Faq />
      <FinalCta onCta={scrollToTutorial} />
      <Footer />
    </div>
  );
}
