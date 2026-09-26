import React from 'react';
import { motion, useReducedMotion } from 'framer-motion';

/**
 * Headline that rises word-by-word out of a mask when it scrolls into view.
 * `lines` is an array of strings; each renders on its own line.
 * A line may also be { text, className } to style one line (e.g. an accent).
 */
export default function SplitReveal({ as = 'h2', lines, className, id, delay = 0 }) {
  const Tag = motion[as];
  const reduce = useReducedMotion();
  let wordIdx = 0;

  return (
    <Tag
      className={className}
      id={id}
      initial="hidden"
      whileInView="show"
      viewport={{ once: true, amount: 0.5 }}
    >
      {lines.map((line, li) => {
        const text = typeof line === 'string' ? line : line.text;
        const lineClass = typeof line === 'string' ? '' : line.className;
        return (
          <span className={`split-line ${lineClass || ''}`} key={li}>
            {text.split(' ').map((word, wi) => {
              const i = wordIdx++;
              return (
                <React.Fragment key={wi}>
                  <span className="split-mask">
                    <motion.span
                      className="split-word"
                      variants={{
                        hidden: { y: reduce ? 0 : '105%', opacity: reduce ? 0 : 1 },
                        show: {
                          y: 0,
                          opacity: 1,
                          transition: { duration: 0.85, ease: [0.16, 1, 0.3, 1], delay: delay + i * 0.05 },
                        },
                      }}
                    >
                      {word}
                    </motion.span>
                  </span>{' '}
                </React.Fragment>
              );
            })}
          </span>
        );
      })}
    </Tag>
  );
}
