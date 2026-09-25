import React, { useState } from 'react';
import { useReveal } from '../hooks/useReveal';

const FILTERS = ['All', 'Community', 'Primary care', 'Specialist'];

const PLACES = [
  {
    icon: '🏥',
    name: 'Village health centre',
    desc: 'Bring screening to the most remote communities, with one photo and a phone line.',
    tag: 'Community',
    tagClass: 'tag-community',
  },
  {
    icon: '🚐',
    name: 'Mobile eye camp',
    desc: 'A portable camera, a laptop, and VITREOUS. Eye camps now screen more people in a day.',
    tag: 'Community',
    tagClass: 'tag-community',
  },
  {
    icon: '🩺',
    name: 'Diabetes clinic',
    desc: 'People already coming for diabetes care get an eye check without a separate trip.',
    tag: 'Primary care',
    tagClass: 'tag-primary',
  },
  {
    icon: '👥',
    name: 'Community screening drive',
    desc: 'Local volunteers run a screening day. VITREOUS handles the analysis; a doctor reviews remotely.',
    tag: 'Community',
    tagClass: 'tag-community',
  },
  {
    icon: '🏢',
    name: 'District hospital',
    desc: 'Ophthalmologists get pre-screened cases with highlights, so they spend time where it matters.',
    tag: 'Specialist',
    tagClass: 'tag-specialist',
  },
  {
    icon: '💻',
    name: 'Tele-eye consultation',
    desc: 'A doctor reviews photos from anywhere, signs off on a report, and sends it back to the clinic.',
    tag: 'Specialist',
    tagClass: 'tag-specialist',
  },
];

export default function PlacesGrid() {
  const [filter, setFilter] = useState('All');
  const [ref, visible] = useReveal({ threshold: 0.08 });

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

        <h2 className="places-h2" id="places-h2">
          Made for the places people already go.
        </h2>
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
              {f}
            </button>
          ))}
        </div>

        <div
          className={`places-grid reveal-stagger ${visible ? 'visible' : ''}`}
          ref={ref}
        >
          {shown.map((place, i) => (
            <div className="place-card-wrap" key={place.name}>
              <div className="place-card" tabIndex={0}>
                <div>
                  <span className={`place-tag ${place.tagClass}`}>{place.tag}</span>
                  <div className="place-icon" aria-hidden="true">{place.icon}</div>
                </div>
                <div>
                  <h3 className="place-name">{place.name}</h3>
                  <p className="place-desc">{place.desc}</p>
                </div>
                <span className="place-arrow" aria-hidden="true">↗</span>
              </div>
            </div>
          ))}
        </div>

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
