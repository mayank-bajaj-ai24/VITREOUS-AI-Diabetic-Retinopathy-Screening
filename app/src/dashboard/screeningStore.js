/**
 * Screening history kept in this browser (localStorage), so the Overview can
 * summarise what the AI Analysis tab has actually processed on this device.
 */
const KEY = 'vitreous.screenings.v2';
const EVENT = 'vitreous:screenings';

export const GRADES = [
  { grade: 0, short: 'No DR', name: 'No apparent retinopathy', color: '#3f8f5b', action: 'Rescreen in 12 months' },
  { grade: 1, short: 'Mild', name: 'Mild NPDR', color: '#8a9a2e', action: 'Rescreen in 9–12 months' },
  { grade: 2, short: 'Moderate', name: 'Moderate NPDR', color: '#c29a1c', action: 'Refer within 3–6 months' },
  { grade: 3, short: 'Severe', name: 'Severe NPDR', color: '#c9692a', action: 'Urgent referral, 2–4 weeks' },
  { grade: 4, short: 'Proliferative', name: 'Proliferative DR', color: '#b42318', action: 'Immediate referral' },
];

function read() {
  try {
    const raw = localStorage.getItem(KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function write(records) {
  try {
    localStorage.setItem(KEY, JSON.stringify(records));
  } catch {
    // Storage full or blocked; the in-memory event still updates open views
  }
  window.dispatchEvent(new CustomEvent(EVENT));
}

export function getScreenings() {
  return read();
}

let counter = 0;
function nextId() {
  counter += 1;
  return `SCR-${Date.now().toString(36).slice(-4).toUpperCase()}${counter}`;
}

/**
 * Record one pipeline run.
 * outcome: 'graded' (grade, confidence…) or 'rejected' (failed the quality gate).
 * Any sample records are dropped as soon as real data arrives.
 */
export function addScreening(entry) {
  const records = read().filter((r) => !r.sample);
  records.unshift({ id: nextId(), time: Date.now(), ...entry });
  write(records.slice(0, 200));
}

export function clearScreenings() {
  write([]);
}

export function subscribe(fn) {
  const onStorage = (e) => {
    if (e.key === KEY) fn();
  };
  window.addEventListener(EVENT, fn);
  window.addEventListener('storage', onStorage);
  return () => {
    window.removeEventListener(EVENT, fn);
    window.removeEventListener('storage', onStorage);
  };
}

/* Deterministic sample set so the Overview can be previewed before any scans */
export function loadSampleScreenings() {
  let seed = 7;
  const rand = () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
  const gradeFor = (r) => (r < 0.46 ? 0 : r < 0.68 ? 1 : r < 0.84 ? 2 : r < 0.94 ? 3 : 4);
  const now = Date.now();
  const records = [];

  for (let i = 0; i < 24; i++) {
    const time = now - Math.round((i * 17 + rand() * 12) * 60 * 1000);
    const base = { id: `PT-${String(1040 + 24 - i).padStart(4, '0')}`, time, sample: true, filename: `fundus_${i + 1}.jpg` };
    if (rand() < 0.12) {
      records.push({
        ...base,
        outcome: 'rejected',
        focus: Math.round((0.4 + rand() * 2.2) * 100) / 100,
        reason: rand() < 0.5 ? 'Out of focus' : 'Poor illumination',
        durationMs: Math.round(300 + rand() * 400),
      });
      continue;
    }
    records.push({
      ...base,
      outcome: 'graded',
      grade: gradeFor(rand()),
      confidence: Math.round(78 + rand() * 20),
      focus: Math.round((3.5 + rand() * 9) * 100) / 100,
      agreement: Math.round(70 + rand() * 26),
      durationMs: Math.round(1400 + rand() * 1800),
    });
  }
  write(records);
}
