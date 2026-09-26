import React, { useRef, useState } from 'react';
import { motion, AnimatePresence, useInView } from 'framer-motion';
import { Hospital, Bus, Stethoscope, Users, Building2, MonitorSmartphone, ArrowUpRight } from 'lucide-react';
import SplitReveal from './SplitReveal';

const FILTERS = ['All', 'Community', 'Primary care', 'Specialist'];

const PLACES = [
  {
    icon: Hospital,
    name: 'Village health centre',
    desc: 'Bring screening to the most remote communities, with one photo and a phone line.',
    tag: 'Community',
    tagClass: 'tag-community',
  },
  {
    icon: Bus,
    name: 'Mobile eye camp',
    desc: 'A portable camera, a laptop, and VITREOUS. Eye camps now screen more people in a day.',
    tag: 'Community',
    tagClass: 'tag-community',
  },
  {
    icon: Stethoscope,
    name: 'Diabetes clinic',
    desc: 'People already coming for diabetes care get an eye check without a separate trip.',
    tag: 'Primary care',
    tagClass: 'tag-primary',
  },
  {
    icon: Users,
    name: 'Community screening drive',
    desc: 'Local volunteers run a screening day. VITREOUS handles the analysis; a doctor reviews remotely.',
    tag: 'Community',
    tagClass: 'tag-community',
  },
  {
    icon: Building2,
    name: 'District hospital',
    desc: 'Ophthalmologists get pre-screened cases with highlights, so they spend time where it matters.',
    tag: 'Specialist',
    tagClass: 'tag-specialist',
  },
  {
    icon: MonitorSmartphone,
    name: 'Tele-eye consultation',
    desc: 'A doctor reviews photos from anywhere, signs off on a report, and sends it back to the clinic.',
    tag: 'Specialist',
    tagClass: 'tag-specialist',
  },
];

export default function PlacesGrid() {
  const [filter, setFilter] = useState('All');
  const gridRef = useRef(null);
  const inView = useInView(gridRef, { once: true, amount: 0.15 });

  const shown = filter === 'All'
    ? PLACES
    : PLACES.filter(p => p.tag === filter);

  return (
    <section
      className="places-section"
      id="places"
      aria-labelledby="places-h2"
    >
      <div className="places-inner">
        <div className="section-label">
          <span className="dot" aria-hidden="true" />
          Where it works
        </div>

        <SplitReveal className="places-h2" id="places-h2" lines={['Made for the places', 'people already go.']} />
        <p className="places-sub">
          VITREOUS fits into the care that already exists — no new buildings, no new journeys.
        </p>

        <div className="filter-tabs" role="tablist" aria-label="Filter by care type">
          {FILTERS.map(f => (
            <button
              key={f}
              className={`filter-tab${filter === f ? ' active' : ''}`}
              role="tab"
              aria-selected={filter === f}
              onClick={() => setFilter(f)}
            >
              {filter === f && (
                <motion.span layoutId="placesFilter" className="filter-tab-bg" transition={{ type: 'spring', stiffness: 400, damping: 34 }} />
              )}
              <span>{f}</span>
            </button>
          ))}
        </div>

        <motion.div className="places-grid" ref={gridRef} layout>
          <AnimatePresence mode="popLayout">
            {shown.map((place, i) => (
              <motion.div
                className="place-card-wrap"
                key={place.name}
                layout
                initial={{ opacity: 0, y: 40, scale: 0.96 }}
                animate={inView ? { opacity: 1, y: 0, scale: 1 } : { opacity: 0, y: 40, scale: 0.96 }}
                exit={{ opacity: 0, scale: 0.92, transition: { duration: 0.2 } }}
                transition={{ type: 'spring', stiffness: 260, damping: 28, delay: inView ? i * 0.06 : 0 }}
              >
                <div className="place-card" tabIndex={0}>
                  <span className="place-fill" aria-hidden="true" />
                  <div>
                    <span className={`place-tag ${place.tagClass}`}>{place.tag}</span>
                    <div className="place-icon" aria-hidden="true"><place.icon size={26} strokeWidth={1.6} /></div>
                  </div>
                  <div>
                    <h3 className="place-name">{place.name}</h3>
                    <p className="place-desc">{place.desc}</p>
                  </div>
                  <span className="place-arrow" aria-hidden="true"><ArrowUpRight size={22} /></span>
                </div>
              </motion.div>
            ))}
          </AnimatePresence>
        </motion.div>

        <div className="places-footer">
          <p className="places-footer-text">
            Running a clinic or camp? We'd love to hear from you.
          </p>
          {/* [contact@team.example] placeholder */}
          <button className="btn-contact">
            Get in touch
          </button>
        </div>
      </div>
    </section>
  );
}
