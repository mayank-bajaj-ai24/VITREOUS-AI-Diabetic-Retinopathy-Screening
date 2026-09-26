import React, { useCallback, useEffect, useState } from 'react';
import { motion, AnimatePresence, useReducedMotion } from 'framer-motion';
import { ChevronLeft, ChevronRight, RotateCw } from 'lucide-react';

/**
 * A stack of two-sided flash cards.
 *
 *   cards: [{ id, kicker, front: node, back: node }]
 *
 * Click (or Enter/Space) flips the top card. Arrows, the buttons, or a
 * horizontal drag move through the deck; the next cards peek out beneath
 * so it reads as a physical stack.
 */
export default function FlashDeck({ title, subtitle, cards, autoAdvanceMs = 0 }) {
  const [index, setIndex] = useState(0);
  const [dir, setDir] = useState(1);
  const [flipped, setFlipped] = useState(false);
  const [paused, setPaused] = useState(false);
  const reduce = useReducedMotion();
  const n = cards.length;

  const go = useCallback(
    (step) => {
      setDir(step);
      setFlipped(false);
      setIndex((i) => (i + step + n) % n);
    },
    [n]
  );

  // Optional slow auto-advance, paused while the reader is interacting
  useEffect(() => {
    if (!autoAdvanceMs || paused || flipped || n < 2) return;
    const id = setTimeout(() => go(1), autoAdvanceMs);
    return () => clearTimeout(id);
  }, [autoAdvanceMs, paused, flipped, index, go, n]);

  if (n === 0) return null;
  const card = cards[index];

  const onKey = (e) => {
    if (e.key === 'ArrowRight') go(1);
    else if (e.key === 'ArrowLeft') go(-1);
    else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      setFlipped((f) => !f);
    }
  };

  return (
    <section
      className="deck"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      aria-roledescription="flash card deck"
    >
      {(title || subtitle) && (
        <header className="deck-head">
          <div>
            {title && <h2>{title}</h2>}
            {subtitle && <p>{subtitle}</p>}
          </div>
          <div className="deck-nav">
            <span className="deck-count">
              {String(index + 1).padStart(2, '0')} / {String(n).padStart(2, '0')}
            </span>
            <button type="button" onClick={() => go(-1)} aria-label="Previous card">
              <ChevronLeft size={16} />
            </button>
            <button type="button" onClick={() => go(1)} aria-label="Next card">
              <ChevronRight size={16} />
            </button>
          </div>
        </header>
      )}

      <div className="deck-stage">
        {/* The two cards beneath, peeking out */}
        {n > 2 && <div className="deck-ghost g2" aria-hidden="true" />}
        {n > 1 && <div className="deck-ghost g1" aria-hidden="true" />}

        <AnimatePresence initial={false} custom={dir} mode="popLayout">
          <motion.div
            key={card.id}
            className="deck-card-wrap"
            custom={dir}
            variants={{
              enter: (d) => ({ x: reduce ? 0 : d * 60, opacity: 0, rotate: reduce ? 0 : d * 2 }),
              center: { x: 0, opacity: 1, rotate: 0 },
              exit: (d) => ({ x: reduce ? 0 : d * -120, opacity: 0, rotate: reduce ? 0 : d * -4 }),
            }}
            initial="enter"
            animate="center"
            exit="exit"
            transition={{ type: 'spring', stiffness: 260, damping: 28 }}
            drag={n > 1 ? 'x' : false}
            dragConstraints={{ left: 0, right: 0 }}
            dragElastic={0.6}
            onDragEnd={(_, info) => {
              if (info.offset.x < -70) go(1);
              else if (info.offset.x > 70) go(-1);
            }}
          >
            <motion.div
              className="deck-card"
              role="button"
              tabIndex={0}
              aria-label={flipped ? 'Show front of card' : 'Show back of card'}
              onClick={() => setFlipped((f) => !f)}
              onKeyDown={onKey}
              animate={{ rotateY: flipped ? 180 : 0 }}
              transition={{ duration: reduce ? 0 : 0.55, ease: [0.16, 1, 0.3, 1] }}
            >
              <div className="deck-face deck-front">
                {card.kicker && <p className="deck-kicker">{card.kicker}</p>}
                <div className="deck-body">{card.front}</div>
                <p className="deck-hint">
                  <RotateCw size={12} /> Tap to flip
                </p>
              </div>
              <div className="deck-face deck-back">
                {card.kicker && <p className="deck-kicker">{card.kicker}</p>}
                <div className="deck-body">{card.back}</div>
                <p className="deck-hint">
                  <RotateCw size={12} /> Tap to flip back
                </p>
              </div>
            </motion.div>
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="deck-dots" role="tablist" aria-label="Cards">
        {cards.map((c, i) => (
          <button
            key={c.id}
            type="button"
            role="tab"
            aria-selected={i === index}
            aria-label={`Card ${i + 1}`}
            className={i === index ? 'active' : ''}
            onClick={() => {
              setDir(i > index ? 1 : -1);
              setFlipped(false);
              setIndex(i);
            }}
          />
        ))}
      </div>
    </section>
  );
}
