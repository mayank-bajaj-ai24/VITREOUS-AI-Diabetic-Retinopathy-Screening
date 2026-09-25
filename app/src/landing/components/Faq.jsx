import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronDown, Mail, HelpCircle, ArrowRight } from 'lucide-react';

const FAQ_DATA = [
  {
    q: 'Does VITREOUS replace an ophthalmologist or eye doctor?',
    a: 'No. VITREOUS is a frontline screening and clinical triage decision-support tool. It identifies early indicators of diabetic retinopathy in rural clinics where eye doctors are unavailable, and immediately routes suspicious or high-grade scans to certified ophthalmologists for final review and sign-off.',
  },
  {
    q: 'Do patients need to install any mobile app or software?',
    a: 'Not at all. The community health worker (ANM/ASHA) or clinic nurse handles the entire process using the clinic tablet or workstation. The patient simply sits comfortably and looks into the fundus camera for 3 to 5 seconds. No pupil dilation drops are needed in most cases.',
  },
  {
    q: 'How long does a complete check-up take from start to finish?',
    a: 'The AI inference and image quality check complete in less than 48 milliseconds on edge hardware. The entire patient visit—from registration to capturing the photo and receiving an immediate triage recommendation—takes under 5 minutes.',
  },
  {
    q: 'What happens if a photo is blurry, dark, or poorly centered?',
    a: 'VITREOUS features a mandatory pre-inference automated quality gate. If the image lacks optical clarity, is out of focus, or misses the macula/optic disc, VITREOUS immediately prompts the health worker to retake the photo with helpful guidance, preventing false positives and ungrounded AI guesses.',
  },
  {
    q: 'What happens if diabetic retinopathy or retinal changes are detected?',
    a: 'The encrypted scan and automated severity grade (ICDR Scale 0–4) are immediately prioritized in the district tele-ophthalmology queue. A retinal specialist reviews the scan, confirms the findings, and generates a signed referral letter with recommended follow-up instructions for the patient.',
  },
  {
    q: 'How is patient medical data and retinal imagery protected?',
    a: 'VITREOUS is designed in full compliance with the Digital Personal Data Protection (DPDP) Act 2023 and Ayushman Bharat Digital Mission (ABDM) standards. Images are processed locally on-device via SQLite Edge, and tele-referral data is end-to-end encrypted in transit and at rest.',
  },
  {
    q: 'Can VITREOUS function in remote rural PHCs with no internet connectivity?',
    a: 'Yes. VITREOUS is built offline-first. The AI model runs entirely on local edge hardware without requiring cloud connectivity. Screenings are stored securely in local database tables and automatically synchronize with the central district registry whenever connectivity is restored.',
  },
];

export default function Faq() {
  const [openIdx, setOpenIdx] = useState(0); // First item open by default

  const toggle = (i) => setOpenIdx((prev) => (prev === i ? null : i));

  return (
    <section className="faq-section" id="faq" aria-labelledby="faq-heading">
      <div className="faq-inner">
        {/* Left Column: Heading & Contact Card */}
        <div className="faq-left">
          <div className="section-label">
            <span className="dot" aria-hidden="true" />
            <span>Clear Answers</span>
          </div>

          <h2 className="faq-heading" id="faq-heading">
            Questions,<br />answered simply.
          </h2>

          <p className="faq-intro">
            Everything here is written in plain, transparent language. If you have questions
            regarding clinical deployment, AI validation, or patient privacy, our team is ready to assist.
          </p>

          <div className="faq-contact-card">
            <div className="faq-contact-icon">
              <Mail size={22} />
            </div>
            <div className="faq-contact-info">
              <h4>Have another question?</h4>
              <p>Speak with the Team ByteCrew engineering and medical team.</p>
              <a 
                href="mailto:contact@vitreous-health.org" 
                className="faq-contact-btn"
                aria-label="Send email to VITREOUS team"
              >
                <span>Send us an email</span>
                <ArrowRight size={14} />
              </a>
            </div>
          </div>
        </div>

        {/* Right Column: Accordion List */}
        <div className="faq-accordion-list" role="list">
          {FAQ_DATA.map((item, i) => {
            const isOpen = openIdx === i;
            return (
              <div
                key={i}
                className={`faq-card ${isOpen ? 'active' : ''}`}
                role="listitem"
              >
                <button
                  type="button"
                  className="faq-trigger"
                  onClick={() => toggle(i)}
                  aria-expanded={isOpen}
                  aria-controls={`faq-answer-${i}`}
                  id={`faq-question-${i}`}
                >
                  <span className="faq-question-text">{item.q}</span>
                  <div className={`faq-chevron-circle ${isOpen ? 'rotated' : ''}`}>
                    <ChevronDown size={18} />
                  </div>
                </button>

                <AnimatePresence initial={false}>
                  {isOpen && (
                    <motion.div
                      id={`faq-answer-${i}`}
                      role="region"
                      aria-labelledby={`faq-question-${i}`}
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.28, ease: [0.16, 1, 0.3, 1] }}
                      style={{ overflow: 'hidden' }}
                    >
                      <div className="faq-body-content">
                        <p>{item.a}</p>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
