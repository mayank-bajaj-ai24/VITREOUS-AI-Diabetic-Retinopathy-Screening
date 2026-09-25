import { useEffect, useRef, useState } from 'react';

/**
 * Returns [ref, isVisible]. When the element enters the viewport,
 * isVisible becomes true and stays true (one-shot).
 */
export function useReveal(options = {}) {
  const ref = useRef(null);
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsVisible(true);
          observer.unobserve(el);
        }
      },
      { threshold: 0.12, ...options }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return [ref, isVisible];
}

/**
 * useCountUp — animates a number from 0 to `end` when `trigger` is true.
 */
export function useCountUp(end, trigger, duration = 1800) {
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (!trigger) return;
    let frame;
    const startTime = performance.now();
    const animate = (now) => {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      // ease out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      setCount(Math.round(eased * end));
      if (progress < 1) frame = requestAnimationFrame(animate);
    };
    frame = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(frame);
  }, [trigger, end, duration]);

  return count;
}
