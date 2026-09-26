import React, { useMemo, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, Mail, ArrowRight, Search, X } from 'lucide-react';
import SplitReveal from './SplitReveal';

const FAQ_DATA = [
  {
    cat: 'Clinical',
    q: 'Does VITREOUS replace an ophthalmologist or eye doctor?',
    a: 'No. VITREOUS is a frontline screening and clinical triage decision-support tool. It identifies early indicators of diabetic retinopathy in rural clinics where eye doctors are unavailable, and immediately routes suspicious or high-grade scans to certified ophthalmologists for final review and sign-off.',
  },
  {
    cat: 'Patients',
    q: 'Do patients need to install any mobile app or software?',
    a: 'Not at all. The community health worker (ANM/ASHA) or clinic nurse handles the entire process using the clinic tablet or workstation. The patient simply sits comfortably and looks into the fundus camera for 3 to 5 seconds. No pupil dilation drops are needed in most cases.',
  },
  {
    cat: 'Patients',
    q: 'How long does a complete check-up take from start to finish?',
    a: 'The AI inference and image quality check complete in less than 48 milliseconds on edge hardware. The entire patient visit—from registration to capturing the photo and receiving an immediate triage recommendation—takes under 5 minutes.',
  },
  {
    cat: 'Technology',
    q: 'What happens if a photo is blurry, dark, or poorly centered?',
    a: 'VITREOUS features a mandatory pre-inference automated quality gate. If the image lacks optical clarity, is out of focus, or misses the macula/optic disc, VITREOUS immediately prompts the health worker to retake the photo with helpful guidance, preventing false positives and ungrounded AI guesses.',
  },
  {
    cat: 'Clinical',
    q: 'What happens if diabetic retinopathy or retinal changes are detected?',
    a: 'The encrypted scan and automated severity grade (ICDR Scale 0–4) are immediately prioritized in the district tele-ophthalmology queue. A retinal specialist reviews the scan, confirms the findings, and generates a signed referral letter with recommended follow-up instructions for the patient.',
  },
  {
    cat: 'Privacy',
    q: 'How is patient medical data and retinal imagery protected?',
    a: 'VITREOUS is designed in full compliance with the Digital Personal Data Protection (DPDP) Act 2023 and Ayushman Bharat Digital Mission (ABDM) standards. Images are processed locally on-device via SQLite Edge, and tele-referral data is end-to-end encrypted in transit and at rest.',
  },
  {
    cat: 'Technology',
    q: 'Can VITREOUS function in remote rural PHCs with no internet connectivity?',
    a: 'Yes. VITREOUS is built offline-first. The AI model runs entirely on local edge hardware without requiring cloud connectivity. Screenings are stored securely in local database tables and automatically synchronize with the central district registry whenever connectivity is restored.',
  },
];

const CATEGORIES = ['All', 'Clinical', 'Patients', 'Technology', 'Privacy'];

function Highlight({ text, query }) {
  if (!query) return text;
  const lower = text.toLowerCase();
  const q = query.toLowerCase();
  const out = [];
  let from = 0;
  let hit = lower.indexOf(q, from);
  while (hit !== -1) {
    if (hit > from) out.push(text.slice(from, hit));
    out.push(<mark key={hit}>{text.slice(hit, hit + q.length)}</mark>);
    from = hit + q.length;
    hit = lower.indexOf(q, from);
  }
  out.push(text.slice(from));
  return out;
}

export default function Faq() {
  const [openIdx, setOpenIdx] = useState(0);
  const [category, setCategory] = useState('All');
  const [query, setQuery] = useState('');

  const q = query.trim();
  const items = useMemo(
    () =>
      FAQ_DATA.map((item, i) => ({ ...item, i })).filter((item) => {
        if (category !== 'All' && item.cat !== category) return false;
        if (!q) return true;
        const needle = q.toLowerCase();
        return item.q.toLowerCase().includes(needle) || item.a.toLowerCase().includes(needle);
      }),
    [category, q]
  );

  const toggle = (i) => setOpenIdx((prev) => (prev === i ? null : i));

  return (
    <section className="faq-section" id="faq" aria-labelledby="faq-heading">
      <div className="faq-inner">
        <div className="faq-left">
          <div className="section-label">
            <span className="dot" aria-hidden="true" />
            <span>Clear answers</span>
          </div>

          <SplitReveal className="faq-heading" id="faq-heading" lines={['Questions,', 'answered simply.']} />

          <p className="faq-intro">
            Plain answers about clinical use, patients, the technology and privacy. Search, or pick a topic.
          </p>

          <div className="faq-contact-card">
            <div className="faq-contact-icon">
              <Mail size={22} />
            </div>
            <div className="faq-contact-info">
              <h4>Have another question?</h4>
              <p>Speak with the Team ByteCrew engineering and medical team.</p>
              <a href="mailto:contact@vitreous-health.org" className="faq-contact-btn">
                <span>Send us an email</span>
                <ArrowRight size={14} />
              </a>
            </div>
          </div>
        </div>

        <div className="faq-right">
          <div className="faq-tools">
            <div className="faq-search">
              <Search size={18} aria-hidden="true" />
              <input
                type="search"
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setOpenIdx(null);
                }}
                placeholder="Search questions, e.g. internet, dilation, data"
                aria-label="Search frequently asked questions"
              />
              {query && (
                <button type="button" className="faq-search-clear" onClick={() => setQuery('')} aria-label="Clear search">
                  <X size={16} />
                </button>
              )}
            </div>

            <div className="faq-cats" role="tablist" aria-label="Filter questions by topic">
              {CATEGORIES.map((c) => {
                const count = c === 'All' ? FAQ_DATA.length : FAQ_DATA.filter((f) => f.cat === c).length;
                return (
                  <button
                    key={c}
                    type="button"
                    role="tab"
                    aria-selected={category === c}
                    className={`faq-cat${category === c ? ' active' : ''}`}
                    onClick={() => setCategory(c)}
                  >
                    {category === c && (
                      <motion.span layoutId="faqCat" className="faq-cat-bg" transition={{ type: 'spring', stiffness: 400, damping: 34 }} />
                    )}
                    <span>{c}</span>
                    <span className="faq-cat-count">{count}</span>
                  </button>
                );
              })}
            </div>
          </div>

          <motion.ul className="faq-accordion-list" layout>
            <AnimatePresence initial={false} mode="popLayout">
              {items.map((item) => {
                const isOpen = openIdx === item.i || (q !== "" && items.length === 1);
                return (
                  <motion.li
                    key={item.i}
                    layout
                    initial={{ opacity: 0, y: 16 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, scale: 0.97 }}
                    transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
                    className={`faq-card${isOpen ? ' active' : ''}`}
                  >
                    <button
                      type="button"
                      className="faq-trigger"
                      onClick={() => toggle(item.i)}
                      aria-expanded={isOpen}
                      aria-controls={`faq-answer-${item.i}`}
                      id={`faq-question-${item.i}`}
                    >
                      <span className="faq-num">{String(item.i + 1).padStart(2, '0')}</span>
                      <span className="faq-question-text">
                        <Highlight text={item.q} query={q} />
                      </span>
                      <span className="faq-toggle-icon" aria-hidden="true">
                        <Plus size={18} />
                      </span>
                    </button>

                    <AnimatePresence initial={false}>
                      {isOpen && (
                        <motion.div
                          id={`faq-answer-${item.i}`}
                          role="region"
                          aria-labelledby={`faq-question-${item.i}`}
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: 'auto', opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}
                          style={{ overflow: 'hidden' }}
                        >
                          <div className="faq-body-content">
                            <span className="faq-body-cat">{item.cat}</span>
                            <p>
                              <Highlight text={item.a} query={q} />
                            </p>
                          </div>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </motion.li>
                );
              })}
            </AnimatePresence>
          </motion.ul>

          {items.length === 0 && (
            <div className="faq-empty">
              <p>No questions match “{q}”.</p>
              <button
                type="button"
                onClick={() => {
                  setQuery('');
                  setCategory('All');
                }}
              >
                Show all questions
              </button>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
