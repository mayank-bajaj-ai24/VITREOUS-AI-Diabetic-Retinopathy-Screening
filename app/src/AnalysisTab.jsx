import React, { useCallback, useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence, useReducedMotion } from 'framer-motion';
import {
  Upload, Play, Pause, ChevronLeft, ChevronRight, RotateCcw, Check, X,
  AlertTriangle, Loader2, Cpu, Brain, FileImage, FileText, Download, ImagePlus,
} from 'lucide-react';
import { addScreening } from './dashboard/screeningStore';
import { API, useBackendHealth } from './dashboard/useBackendHealth';

/* ═══════════════════════════════════════════════════════════════
   Stage model — mirrors the MATLAB walkthrough, one screen per step
   ═══════════════════════════════════════════════════════════════ */
const STEPS = [
  { id: 'input', group: 'Input', kicker: 'Stage 0 · Input', title: 'Raw fundus capture', stage: 'input',
    desc: 'The colour retinal photograph exactly as the camera produced it, before any processing.' },
  { id: 'quality', group: 'Quality', kicker: 'Phase 1 · Quality gate', title: 'Is this image gradeable?', stage: 'quality',
    desc: 'Focus, exposure and field of view are measured before any AI runs. A failed capture is sent back for a retake instead of being graded.' },
  { id: 'crop', group: 'Enhancement', kicker: 'Phase 2a · Enhancement', title: 'Crop to the retina', stage: 'enhancement',
    desc: 'The black camera surround is trimmed so every later step works only on retinal tissue.' },
  { id: 'clahe', group: 'Enhancement', kicker: 'Phase 2b · Enhancement', title: 'Adaptive contrast (CLAHE)', stage: 'enhancement',
    desc: 'The measured noise level picks an enhancement profile. CLAHE on the green channel brings out vessels and lesions. Drag the divider to compare.' },
  { id: 'denoise', group: 'Enhancement', kicker: 'Phase 2c · Enhancement', title: 'Non-local means denoising', stage: 'enhancement',
    desc: 'Removes sensor grain while keeping fine vessel edges and small lesions sharp. Hover the image to inspect detail.' },
  { id: 'canvas', group: 'Enhancement', kicker: 'Phase 2d · Enhancement', title: 'Standardised canvas', stage: 'enhancement',
    desc: 'Letterboxed onto a fixed square canvas so every model sees the same geometry.' },
  { id: 'vessels', group: 'Segmentation', kicker: 'Phase 3a · Segmentation', title: 'Retinal vessel map', stage: 'vessels',
    desc: 'Multiscale Frangi vesselness traces the vascular tree. It also stops a vessel being mistaken for a haemorrhage.' },
  { id: 'anatomy', group: 'Segmentation', kicker: 'Phase 3b · Segmentation', title: 'Optic disc & fovea', stage: 'anatomy',
    desc: 'Anatomical landmarks. The disc zone is excluded so its brightness is not mistaken for exudate.' },
  { id: 'lesions', group: 'Segmentation', kicker: 'Phase 3c · Segmentation', title: 'Lesion segmentation', stage: 'lesions',
    desc: 'A U-Net++ model labels every pixel with a diabetic retinopathy lesion type.' },
  { id: 'overlay', group: 'Segmentation', kicker: 'Phase 3d · Result', title: 'Clinical overlay', stage: 'lesions',
    desc: 'Vessels, landmarks and lesions combined into one view a clinician can read at a glance.' },
  { id: 'grade', group: 'Grade', kicker: 'Phase 4 · Classification', title: 'DR severity grade', stage: 'grading',
    desc: 'The trained grading network predicts the ICDR grade (0–4) from the enhanced image.' },
  { id: 'explain', group: 'Explain', kicker: 'Phase 5 · Explainability', title: 'Where the model looked', stage: 'explain',
    desc: 'Two independent attention maps. When gradient-based Grad-CAM and gradient-free Score-CAM agree, the finding rests on real image evidence.' },
];

const BACKEND_ORDER = ['input', 'quality', 'enhancement', 'vessels', 'anatomy', 'lesions', 'grading', 'explain'];
const GROUPS = ['Input', 'Quality', 'Enhancement', 'Segmentation', 'Grade', 'Explain'];
const STEP_MS = 4800;

const SAMPLES = [
  { file: '000c1434d8d7.png', label: 'Sample A' },
  { file: '001639a390f0.png', label: 'Sample B' },
  { file: '0024cdab0c1e.png', label: 'Sample C' },
  { file: 'blurred_input.png', label: 'Blurred', note: 'should be rejected' },
];

const fmt = (v, d = 2) => (typeof v === 'number' ? v.toFixed(d) : '—');

// Browsers report an empty or odd MIME type for some photos (TIFF, files from
// camera software), so accept by extension as well as by type.
const IMAGE_EXT = /\.(jpe?g|png|tiff?|bmp)$/i;
const isImageFile = (f) => !!f && (f.type?.startsWith('image/') || IMAGE_EXT.test(f.name || ''));

/* ═══════════════════════════════════════════════════════════════
   Viewer pieces
   ═══════════════════════════════════════════════════════════════ */

/** New image wipes in over the previous one, led by a thin scan line. */
function WipeImage({ src, alt }) {
  const reduce = useReducedMotion();
  const [layers, setLayers] = useState(() => (src ? [{ src, key: 0 }] : []));
  const counter = useRef(0);

  useEffect(() => {
    if (!src) return;
    setLayers((prev) => {
      if (prev.length && prev[prev.length - 1].src === src) return prev;
      counter.current += 1;
      return [...prev.slice(-1), { src, key: counter.current }];
    });
  }, [src]);

  return (
    <div className="an-wipe">
      {layers.map((l, i) => {
        const top = i === layers.length - 1 && layers.length > 1;
        return (
          <motion.div
            key={l.key}
            className="an-wipe-layer"
            initial={top && !reduce ? { clipPath: 'inset(0 100% 0 0)' } : false}
            animate={{ clipPath: 'inset(0 0% 0 0)' }}
            transition={{ duration: 0.9, ease: [0.65, 0, 0.35, 1] }}
          >
            <img src={l.src} alt={alt} draggable={false} />
            {top && !reduce && (
              <motion.span
                className="an-wipe-line"
                initial={{ left: '0%', opacity: 1 }}
                animate={{ left: '100%', opacity: 0 }}
                transition={{ duration: 0.9, ease: [0.65, 0, 0.35, 1] }}
              />
            )}
          </motion.div>
        );
      })}
    </div>
  );
}

/** Before/after divider for CLAHE. */
function CompareSlider({ before, after }) {
  const [pos, setPos] = useState(50);
  const ref = useRef(null);
  const drag = useRef(false);

  const update = (clientX) => {
    const r = ref.current.getBoundingClientRect();
    setPos(Math.min(100, Math.max(0, ((clientX - r.left) / r.width) * 100)));
  };

  return (
    <div
      className="an-compare"
      ref={ref}
      onPointerDown={(e) => {
        drag.current = true;
        e.currentTarget.setPointerCapture(e.pointerId);
        update(e.clientX);
      }}
      onPointerMove={(e) => drag.current && update(e.clientX)}
      onPointerUp={() => (drag.current = false)}
    >
      <img src={before} alt="Before contrast enhancement" draggable={false} />
      <img src={after} alt="After CLAHE" draggable={false} style={{ clipPath: `inset(0 ${100 - pos}% 0 0)` }} />
      <span className="an-compare-tag left">After</span>
      <span className="an-compare-tag right">Before</span>
      <div className="an-compare-bar" style={{ left: `${pos}%` }}>
        <span />
      </div>
      <input
        type="range"
        min="0"
        max="100"
        value={pos}
        onChange={(e) => setPos(Number(e.target.value))}
        aria-label="Compare before and after contrast enhancement"
        className="an-sr-range"
      />
    </div>
  );
}

/** Magnifier lens for the denoising step. */
function LoupeImage({ src }) {
  const [lens, setLens] = useState(null);
  return (
    <div
      className="an-loupe"
      onPointerMove={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        setLens({ x: e.clientX - r.left, y: e.clientY - r.top, w: r.width, h: r.height });
      }}
      onPointerLeave={() => setLens(null)}
    >
      <img src={src} alt="Denoised retina" draggable={false} />
      {lens && (
        <span
          className="an-loupe-lens"
          style={{
            left: lens.x,
            top: lens.y,
            backgroundImage: `url(${src})`,
            backgroundSize: `${lens.w * 3}px ${lens.h * 3}px`,
            backgroundPosition: `${-lens.x * 3 + 70}px ${-lens.y * 3 + 70}px`,
          }}
        />
      )}
    </div>
  );
}

/** Canvas image with labelled landmark markers (coordinates are canvas pixels). */
function AnatomyImage({ src, anatomy, size }) {
  const pct = (v) => `${(v / size) * 100}%`;
  return (
    <div className="an-anatomy">
      <WipeImage src={src} alt="Optic disc and fovea" />
      {anatomy.disc_center?.length === 2 && (
        <motion.span
          className="an-marker disc"
          style={{ left: pct(anatomy.disc_center[0]), top: pct(anatomy.disc_center[1]) }}
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.8, type: 'spring', stiffness: 260, damping: 18 }}
        >
          <i />
          <b>Optic disc</b>
        </motion.span>
      )}
      {anatomy.fovea_found && anatomy.fovea_center?.length === 2 && (
        <motion.span
          className="an-marker fovea"
          style={{ left: pct(anatomy.fovea_center[0]), top: pct(anatomy.fovea_center[1]) }}
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 1, type: 'spring', stiffness: 260, damping: 18 }}
        >
          <i />
          <b>Fovea</b>
        </motion.span>
      )}
    </div>
  );
}

function ExplainViewer({ explain }) {
  const [mode, setMode] = useState(explain.gradcam_image ? 'grad' : 'score');
  const both = explain.gradcam_image && explain.scorecam_image;
  return (
    <div className="an-explain">
      {mode === 'both' && both ? (
        <div className="an-explain-pair">
          <figure>
            <img src={explain.gradcam_image} alt="Grad-CAM attention" />
            <figcaption>Grad-CAM · gradient-based</figcaption>
          </figure>
          <figure>
            <img src={explain.scorecam_image} alt="Score-CAM attention" />
            <figcaption>Score-CAM · gradient-free</figcaption>
          </figure>
        </div>
      ) : (
        <WipeImage
          src={mode === 'score' ? explain.scorecam_image : explain.gradcam_image}
          alt={mode === 'score' ? 'Score-CAM attention' : 'Grad-CAM attention'}
        />
      )}
      {both && (
        <div className="an-seg" role="tablist" aria-label="Attention method">
          {[['grad', 'Grad-CAM'], ['score', 'Score-CAM'], ['both', 'Side by side']].map(([id, label]) => (
            <button key={id} type="button" role="tab" aria-selected={mode === id} className={mode === id ? 'active' : ''} onClick={() => setMode(id)}>
              {mode === id && <motion.span layoutId="anExplainSeg" className="an-seg-bg" transition={{ type: 'spring', stiffness: 420, damping: 36 }} />}
              <span>{label}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function StageViewer({ step, result }) {
  const e = result.enhancement;
  const size = e?.canvas_size || 512;
  switch (step.id) {
    case 'input':
      return <WipeImage src={result.input.image} alt="Raw fundus capture" />;
    case 'quality':
      return <WipeImage src={result.quality.image} alt="Quality gate field of view" />;
    case 'crop':
      return <WipeImage src={e.crop_image} alt="Cropped retina" />;
    case 'clahe':
      return <CompareSlider before={e.crop_image} after={e.clahe_image} />;
    case 'denoise':
      return <LoupeImage src={e.denoised_image} />;
    case 'canvas':
      return (
        <div className="an-canvas">
          <WipeImage src={e.canvas_image} alt="Standardised canvas" />
          <span className="an-canvas-dim">{size} × {size} px</span>
        </div>
      );
    case 'vessels':
      return <WipeImage src={result.vessels.image} alt="Vessel map" />;
    case 'anatomy':
      return <AnatomyImage src={result.anatomy.image} anatomy={result.anatomy} size={size} />;
    case 'lesions':
      return <WipeImage src={result.lesions.image} alt="Lesion segmentation" />;
    case 'overlay':
    case 'grade':
      return <WipeImage src={result.lesions.overlay_image} alt="Clinical overlay" />;
    case 'explain':
      return <ExplainViewer explain={result.explain} />;
    default:
      return null;
  }
}

/* ═══════════════════════════════════════════════════════════════
   Stage detail cards
   ═══════════════════════════════════════════════════════════════ */
function Metrics({ rows }) {
  return (
    <dl className="an-metrics">
      {rows.map(([label, value, state]) => (
        <div key={label} className={state === false ? 'fail' : ''}>
          <dt>{label}</dt>
          <dd>
            <span>{value}</span>
            {state === true && <Check size={14} className="an-ok" />}
            {state === false && <X size={14} className="an-bad" />}
          </dd>
        </div>
      ))}
    </dl>
  );
}

function checkRow(c) {
  const value =
    c.op === 'in'
      ? `${fmt(c.value, 1)}  in ${c.limit[0]}–${c.limit[1]}`
      : `${fmt(c.value, c.value > 20 ? 1 : 3)}  ${c.op === '>=' ? '≥' : '≤'} ${c.limit}`;
  return [c.label, value, c.passed];
}

function GradeDetails({ grading }) {
  const short = ['No DR', 'Mild', 'Moderate', 'Severe', 'Proliferative'];
  const conf = grading.confidence * 100;
  const C = 2 * Math.PI * 26;
  return (
    <>
      <div className="an-probs">
        {grading.probabilities.map((p, i) => (
          <div key={i} className={`an-prob${i === grading.grade ? ' top' : ''}`}>
            <span className="an-prob-val">{(p * 100).toFixed(0)}%</span>
            <div className="an-prob-track">
              <motion.span
                initial={{ scaleY: 0 }}
                animate={{ scaleY: Math.max(p, 0.015) }}
                transition={{ duration: 0.9, delay: 0.2 + i * 0.07, ease: [0.16, 1, 0.3, 1] }}
              />
            </div>
            <span className="an-prob-label">G{i}</span>
            <span className="an-prob-name">{short[i]}</span>
          </div>
        ))}
      </div>
      <motion.div
        className="an-grade"
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.7 }}
      >
        <div>
          <p className="an-grade-title">Grade {grading.grade} · {grading.grade_name}</p>
          <p className={`an-grade-ref ${grading.referable ? 'yes' : 'no'}`}>
            {grading.referable ? 'Referable — refer to an ophthalmologist' : 'Not referable — routine rescreening'}
          </p>
        </div>
        <svg viewBox="0 0 64 64" className="an-grade-ring" aria-label={`Confidence ${conf.toFixed(0)} percent`}>
          <circle cx="32" cy="32" r="26" className="bg" />
          <motion.circle
            cx="32" cy="32" r="26" className="fg"
            strokeDasharray={C}
            initial={{ strokeDashoffset: C }}
            animate={{ strokeDashoffset: C * (1 - grading.confidence) }}
            transition={{ duration: 1.1, delay: 0.8, ease: [0.16, 1, 0.3, 1] }}
            transform="rotate(-90 32 32)"
          />
          <text x="32" y="36" textAnchor="middle">{conf.toFixed(0)}%</text>
        </svg>
      </motion.div>
      <p className="an-note">Model: {grading.mode} network. Confidence is the raw softmax probability, not calibrated.</p>
    </>
  );
}

function StageDetails({ step, result, jobId, report }) {
  const e = result.enhancement;
  switch (step.id) {
    case 'input':
      return (
        <Metrics rows={[
          ['Resolution', `${result.input.width} × ${result.input.height} px`],
          ['Format', `RGB, ${result.input.bit_depth}-bit`],
        ]} />
      );
    case 'quality': {
      const q = result.quality;
      return (
        <>
          <Metrics rows={[...q.checks.map(checkRow), ['Exposure entropy', fmt(q.entropy)]]} />
          <p className={`an-verdict ${q.passed ? 'pass' : 'fail'}`}>
            {q.passed ? 'Pass · gradeable' : `Fail · ${q.fail_codes.join(', ')}`}
          </p>
          {!q.passed && (
            <div className="an-recapture">
              <p>{q.message}</p>
              <ul>{q.actions.map((a) => <li key={a}>{a}</li>)}</ul>
            </div>
          )}
        </>
      );
    }
    case 'crop':
      return <Metrics rows={[['Retina ROI', `${e.crop_width} × ${e.crop_height} px`], ['Bounding box', `[${e.bbox.join(' ')}]`]]} />;
    case 'clahe':
      return (
        <Metrics rows={[
          ['Noise σ', fmt(e.noise_sigma)],
          ['Profile selected', e.profile],
          ['CLAHE channel', e.clahe_mode],
          ['Clip limit', fmt(e.clahe_clip, 1)],
          ['Tile grid', `${e.clahe_tiles} × ${e.clahe_tiles}`],
        ]} />
      );
    case 'denoise':
      return <Metrics rows={[['NLM strength', e.nlm_strength], ['Search window', `${e.nlm_search} px`]]} />;
    case 'canvas':
      return (
        <Metrics rows={[
          ['Canvas', `${e.canvas_size} × ${e.canvas_size}`],
          ['Scale', fmt(e.scale, 4)],
          ['Letterbox padding', `${fmt(e.padding_pct, 1)} %`],
        ]} />
      );
    case 'vessels':
      return <Metrics rows={[['Vessel density', `${fmt(result.vessels.density_pct)} % of FOV`], ['Mean calibre', `${fmt(result.vessels.mean_width_px, 1)} px`]]} />;
    case 'anatomy': {
      const a = result.anatomy;
      return (
        <Metrics rows={[
          ['Disc centre', `(${a.disc_center.join(', ')})`],
          ['Disc radius', `${fmt(a.disc_radius, 1)} px`],
          ['Localisation confidence', fmt(a.disc_confidence)],
          ['Detector', a.method],
          ['Fovea', a.fovea_found ? `${a.fovea_side} of disc` : 'not determined'],
        ]} />
      );
    }
    case 'lesions':
      return (
        <ul className="an-lesions">
          {result.lesions.classes.map((c, i) => (
            <motion.li
              key={c.name}
              initial={{ opacity: 0, x: 12 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.15 + i * 0.08 }}
            >
              <i style={{ background: c.color }} />
              <span className="an-lesion-name">{c.name.replace('_', ' ')}</span>
              <span className="an-lesion-abbr">{c.abbrev}</span>
              <b>{c.regions}</b>
              <span className="an-lesion-unit">regions</span>
            </motion.li>
          ))}
        </ul>
      );
    case 'overlay':
      return (
        <>
          <p className="an-callout">
            <b>{result.lesions.total_regions}</b> lesion regions found
          </p>
          <Metrics rows={[['Bright lesion suppressed at disc', `${result.lesions.disc_suppressed_px} px`]]} />
        </>
      );
    case 'grade':
      return <GradeDetails grading={result.grading} />;
    case 'explain': {
      const x = result.explain;
      return (
        <>
          <div className="an-agree">
            <div className="an-agree-head">
              <span>Grad-CAM ↔ Score-CAM agreement</span>
              <b>{typeof x.agreement_pct === 'number' ? `${x.agreement_pct.toFixed(1)} %` : '—'}</b>
            </div>
            <div className="an-agree-track">
              <motion.span
                initial={{ scaleX: 0 }}
                animate={{ scaleX: (x.agreement_pct || 0) / 100 }}
                transition={{ duration: 1.1, delay: 0.3, ease: [0.16, 1, 0.3, 1] }}
              />
            </div>
            <p>Pearson correlation between the two attention maps.</p>
          </div>
          {x.lesion_evidence && (
            <Metrics rows={[
              ['Attention on lesion regions', `${fmt(x.lesion_evidence.near_lesion_pct, 1)} %`],
              ['Expected by chance (control)', `${fmt(x.lesion_evidence.control_pct, 1)} %`],
              ['Lift over chance', `${x.lesion_evidence.lift_pts >= 0 ? '+' : ''}${fmt(x.lesion_evidence.lift_pts, 1)} pts`],
              ['Attention–lesion correlation', fmt(x.lesion_evidence.correlation)],
            ]} />
          )}
          {(x.gradcam_note || x.scorecam_note) && (
            <p className="an-note">{x.gradcam_note || x.scorecam_note}</p>
          )}
          <ReportCard jobId={jobId} report={report} />
        </>
      );
    }
    default:
      return null;
  }
}

/** Phase 5 clinical PDF: rendered in MATLAB after the results come back. */
function ReportCard({ jobId, report }) {
  const base = `${API}/api/jobs/${jobId}/report`;
  return (
    <div className="an-report">
      <span className="an-report-icon"><FileText size={20} /></span>
      <div className="an-report-body">
        <p className="an-report-title">Explainable AI report</p>
        <p className="an-report-text">
          {report.ready
            ? 'One-page clinical PDF: grade, marked lesions, attention map and recommendation.'
            : report.pending
              ? 'MATLAB is rendering the one-page clinical PDF…'
              : report.note || 'The report could not be generated.'}
        </p>
      </div>
      {report.ready ? (
        <div className="an-report-actions">
          <a className="an-btn primary" href={base} target="_blank" rel="noopener noreferrer">Open</a>
          <a className="an-btn" href={`${base}?download=1`} aria-label="Download PDF report"><Download size={14} /></a>
        </div>
      ) : report.pending ? (
        <Loader2 size={18} className="spin an-report-wait" />
      ) : null}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════
   Main tab
   ═══════════════════════════════════════════════════════════════ */
export default function AnalysisTab() {
  const [health] = useBackendHealth(4000);
  const reduce = useReducedMotion();
  const fileInputRef = useRef(null);
  const [dragging, setDragging] = useState(false);

  const [file, setFile] = useState(null); // { name, url, dataUrl }
  const [phase, setPhase] = useState('idle'); // idle | ready | sending | queued | running | done | rejected | error
  const [backendStage, setBackendStage] = useState(null);
  const [log, setLog] = useState([]);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [jobId, setJobId] = useState(null);
  const [report, setReport] = useState({ ready: false, pending: false, note: '' });
  const [noPreview, setNoPreview] = useState(false);

  const [active, setActive] = useState(0);
  const [dir, setDir] = useState(1);
  const [playing, setPlaying] = useState(false);
  const pollRef = useRef(null);

  const reportPollRef = useRef(null);
  const stopPolling = () => {
    if (pollRef.current) clearTimeout(pollRef.current);
    if (reportPollRef.current) clearTimeout(reportPollRef.current);
    pollRef.current = null;
    reportPollRef.current = null;
  };

  // The PDF renders after the results arrive; poll until it is ready
  const pollReport = useCallback((id) => {
    const tick = async () => {
      try {
        const r = await fetch(`${API}/api/jobs/${id}/report/status`);
        const st = await r.json();
        setReport(st);
        if (st.pending) reportPollRef.current = setTimeout(tick, 2000);
      } catch {
        setReport({ ready: false, pending: false, note: 'Lost contact with the analysis server.' });
      }
    };
    setReport({ ready: false, pending: true, note: '' });
    tick();
  }, []);
  useEffect(() => stopPolling, []);

  const loadFile = useCallback((f, name) => {
    if (!isImageFile(f)) {
      setError(`“${f?.name || 'That file'}” is not an image VITREOUS can read. Use a JPG, PNG, TIFF or BMP fundus photograph.`);
      setPhase((p) => (p === 'idle' ? 'idle' : 'error'));
      return;
    }
    stopPolling();
    setNoPreview(false);
    setPlaying(false);
    setActive(0);
    setJobId(null);
    setReport({ ready: false, pending: false, note: '' });
    const reader = new FileReader();
    reader.onerror = () => {
      setError('The browser could not read that file.');
      setPhase('error');
    };
    reader.onload = () => {
      setFile({ name: name || f.name, url: URL.createObjectURL(f), dataUrl: reader.result });
      setPhase('ready');
      setResult(null);
      setError(null);
      setLog([]);
    };
    reader.readAsDataURL(f);
  }, []);

  const pickSample = async (s) => {
    const res = await fetch(`/samples/${s.file}`);
    const blob = await res.blob();
    loadFile(new File([blob], s.file, { type: blob.type }), s.file);
  };

  const reset = () => {
    stopPolling();
    setFile(null);
    setPhase('idle');
    setResult(null);
    setError(null);
    setLog([]);
    setPlaying(false);
    setActive(0);
  };

  const finish = useCallback((data, name, id) => {
    setResult(data);
    if (data.status === 'Complete') {
      pollReport(id);
      const g = data.grading;
      addScreening({
        outcome: 'graded',
        filename: name,
        grade: g.grade,
        confidence: Math.round(g.confidence * 1000) / 10,
        focus: data.quality.checks[0]?.value,
        agreement: typeof data.explain.agreement_pct === 'number' ? Math.round(data.explain.agreement_pct * 10) / 10 : undefined,
        lesions: data.lesions.total_regions,
        durationMs: data.total_ms,
      });
      setPhase('done');
      setActive(0);
      setDir(1);
      setPlaying(true);
    } else if (data.status === 'Rejected') {
      addScreening({
        outcome: 'rejected',
        filename: name,
        focus: data.quality.checks[0]?.value,
        reason: data.quality.fail_codes.join(', '),
        durationMs: data.total_ms,
      });
      setPhase('rejected');
      setActive(1);
      setPlaying(false);
    } else {
      setError(data.message || 'The analysis failed.');
      setPhase('error');
    }
  }, [pollReport]);

  const run = async () => {
    if (!file) return;
    setPhase('sending');
    setError(null);
    setLog([]);
    setBackendStage(null);
    try {
      const res = await fetch(`${API}/api/analyze`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: file.dataUrl, filename: file.name }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'The server rejected the request.');
      setPhase('queued');
      setJobId(data.job_id);
      const started = performance.now();
      const poll = async () => {
        try {
          const r = await fetch(`${API}/api/jobs/${data.job_id}`);
          const d = await r.json();
          if (d.status === 'Running') {
            setPhase('running');
            if (d.stage) {
              setBackendStage(d.stage);
              setLog((l) => (l.length && l[l.length - 1].stage === d.stage ? l : [...l, { stage: d.stage, t: performance.now() - started }]));
            }
          }
          if (d.status === 'Complete' || d.status === 'Rejected' || d.status === 'Error') {
            finish(d, file.name, data.job_id);
            return;
          }
          pollRef.current = setTimeout(poll, 600);
        } catch {
          setError('Lost contact with the analysis server.');
          setPhase('error');
        }
      };
      poll();
    } catch (err) {
      setError(
        err.message === 'Failed to fetch'
          ? 'Cannot reach the analysis server. Start it with `python3 server.py` in the project folder (it launches MATLAB).'
          : err.message
      );
      setPhase('error');
    }
  };

  const visibleSteps = phase === 'rejected' ? STEPS.slice(0, 2) : STEPS;

  // Autoplay through the stages after a result arrives
  useEffect(() => {
    if (!playing || phase !== 'done') return;
    if (active >= STEPS.length - 1) {
      setPlaying(false);
      return;
    }
    const id = setTimeout(() => {
      setDir(1);
      setActive((a) => a + 1);
    }, STEP_MS);
    return () => clearTimeout(id);
  }, [playing, active, phase]);

  const goTo = useCallback(
    (i) => {
      if (i < 0 || i >= visibleSteps.length) return;
      setDir(i > active ? 1 : -1);
      setActive(i);
    },
    [active, visibleSteps.length]
  );

  useEffect(() => {
    if (phase !== 'done' && phase !== 'rejected') return;
    const onKey = (e) => {
      if (e.target.closest?.('input, textarea')) return;
      if (e.key === 'ArrowRight') { setPlaying(false); goTo(active + 1); }
      if (e.key === 'ArrowLeft') { setPlaying(false); goTo(active - 1); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [phase, active, goTo]);

  const busy = phase === 'sending' || phase === 'queued' || phase === 'running';
  const hasResult = (phase === 'done' || phase === 'rejected') && result;
  const stageIdx = backendStage ? BACKEND_ORDER.indexOf(backendStage) : -1;

  const stepState = (s, i) => {
    if (hasResult) {
      if (phase === 'rejected') return i === 1 ? 'failed' : i < 1 ? 'done' : 'skipped';
      return 'done';
    }
    if (!busy) return 'pending';
    const k = BACKEND_ORDER.indexOf(s.stage);
    if (k < stageIdx) return 'done';
    if (k === stageIdx) return 'running';
    return 'pending';
  };

  const engine = health.info?.worker;
  const step = visibleSteps[Math.min(active, visibleSteps.length - 1)];

  const openPicker = () => fileInputRef.current?.click();
  const onRootDragOver = (e) => {
    if (busy) return;
    e.preventDefault();
    if (!dragging) setDragging(true);
  };
  const onRootDrop = (e) => {
    e.preventDefault();
    setDragging(false);
    if (busy) return;
    const f = e.dataTransfer.files?.[0];
    if (f) loadFile(f);
  };

  return (
    <div
      className={`an${dragging && phase !== 'idle' ? ' an-dropping' : ''}`}
      onDragOver={onRootDragOver}
      onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget)) setDragging(false); }}
      onDrop={onRootDrop}
    >
      {/* One file input for the whole tab, outside any clickable area so a
          click never re-triggers it (some browsers then refuse to open it) */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*,.jpg,.jpeg,.png,.tif,.tiff,.bmp"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = '';
          if (f) loadFile(f);
        }}
      />
      <header className="an-head">
        <div>
          <h1 className="an-title">AI Analysis</h1>
          <p className="an-sub">Every phase from capture to explanation, computed by the trained VITREOUS models in MATLAB.</p>
        </div>
        <div className="an-engine">
          <span className={`an-engine-dot ${health.status}`} />
          <Cpu size={15} />
          <span>
            {health.status === 'online' || health.status === 'busy'
              ? `MATLAB ${engine?.matlab?.match(/R\d{4}[ab]/)?.[0] || ''} · ${health.info?.model || 'model'} · ${health.status === 'busy' ? 'busy' : 'ready'}`
              : health.status === 'loading'
                ? 'MATLAB loading models…'
                : health.status === 'checking'
                  ? 'Checking engine…'
                  : 'Engine offline'}
          </span>
        </div>
      </header>

      <AnimatePresence mode="wait">
        {phase === 'idle' && (
          <motion.section
            key="idle"
            className="an-intake"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
          >
            <div
              className={`an-drop${dragging ? ' dragging' : ''}`}
              onClick={openPicker}
              role="button"
              tabIndex={0}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  openPicker();
                }
              }}
            >
              <span className="an-drop-icon"><Upload size={26} /></span>
              <h3>Drop a fundus photograph</h3>
              <p>or click to browse · JPG, PNG, TIFF or BMP · a full fundus photo works best</p>
            </div>

            {error && (
              <p className="an-inline-error" role="alert"><AlertTriangle size={15} /> {error}</p>
            )}

            <div className="an-samples">
              <p>Or try a sample from the dataset</p>
              <div className="an-samples-row">
                {SAMPLES.map((s, i) => (
                  <motion.button
                    key={s.file}
                    type="button"
                    className="an-sample"
                    onClick={() => pickSample(s)}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.1 + i * 0.06 }}
                  >
                    <img src={`/samples/${s.file.replace('.png', '_thumb.jpg')}`} alt="" />
                    <span>{s.label}</span>
                    {s.note && <em>{s.note}</em>}
                  </motion.button>
                ))}
              </div>
            </div>
          </motion.section>
        )}

        {phase !== 'idle' && (
          <motion.section
            key="study"
            className="an-study"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
          >
            {/* Viewer */}
            <div className="an-viewer">
              <div className="an-viewer-bar">
                <span className="an-file"><FileImage size={14} /> {file?.name}</span>
                <div className="an-viewer-actions">
                  <button type="button" className="an-btn ghost" onClick={openPicker} disabled={busy}>
                    <ImagePlus size={14} /> Upload another
                  </button>
                  <button type="button" className="an-btn ghost" onClick={reset} disabled={busy}>
                    <RotateCcw size={14} /> New scan
                  </button>
                </div>
              </div>

              <div className="an-frame">
                {hasResult ? (
                  <StageViewer step={step} result={result} />
                ) : (
                  <div className="an-wipe">
                    <div className="an-wipe-layer">
                      {noPreview ? (
                        <p className="an-nopreview">This browser can’t preview this file type, but MATLAB can read it.</p>
                      ) : (
                        <img src={file?.url} alt="Selected fundus" onError={() => setNoPreview(true)} />
                      )}
                    </div>
                  </div>
                )}

                {busy && (
                  <div className="an-scan" aria-hidden="true">
                    <span className="an-scan-beam" />
                  </div>
                )}

                {busy && (
                  <span className="an-live">
                    <i />
                    {phase === 'sending'
                      ? 'Uploading'
                      : phase === 'queued'
                        ? 'Waiting for MATLAB'
                        : STEPS.find((s) => s.stage === backendStage)?.kicker.split(' · ')[1] || 'Starting'}
                  </span>
                )}
              </div>
            </div>

            {/* Right column: live log while running, stage card stack when done */}
            <div className="an-side">
              {phase === 'ready' && (
                <div className="an-card an-ready">
                  <p className="an-kicker">Ready</p>
                  <h3>Run the photo through all five phases</h3>
                  <p>Quality gate, enhancement, segmentation, grading and explainability run in MATLAB on the trained models. It takes about 30 seconds; each stage appears here as it completes.</p>
                  {health.status === 'offline' && (
                    <p className="an-warn"><AlertTriangle size={14} /> The engine is offline. Start it with <code>python3 server.py</code>.</p>
                  )}
                  {health.status === 'loading' && (
                    <p className="an-warn"><Loader2 size={14} className="spin" /> MATLAB is loading the models; the run starts as soon as it is ready.</p>
                  )}
                  <button type="button" className="an-run" onClick={run} disabled={health.status === 'offline'}>
                    <Brain size={18} />
                    <span>Run full analysis</span>
                    <ChevronRight size={16} />
                  </button>
                </div>
              )}

              {busy && (
                <div className="an-card an-console">
                  <p className="an-kicker">Running in MATLAB</p>
                  <ol>
                    {BACKEND_ORDER.map((st, i) => {
                      const s = STEPS.find((x) => x.stage === st);
                      const entry = log.find((l) => l.stage === st);
                      const state = i < stageIdx ? 'done' : i === stageIdx ? 'running' : 'pending';
                      return (
                        <li key={st} className={state}>
                          <span className="an-console-icon">
                            {state === 'done' ? <Check size={13} /> : state === 'running' ? <Loader2 size={13} className="spin" /> : null}
                          </span>
                          <span>{s.kicker.split(' · ')[1] || s.title}</span>
                          <span className="an-console-t">{entry ? `${(entry.t / 1000).toFixed(1)} s` : ''}</span>
                        </li>
                      );
                    })}
                  </ol>
                  <p className="an-console-note">Score-CAM runs 24 masked forward passes, so Phase 5 takes the longest.</p>
                </div>
              )}

              {phase === 'error' && (
                <div className="an-card an-error" role="alert">
                  <AlertTriangle size={18} />
                  <div>
                    <h3>Analysis could not run</h3>
                    <p>{error}</p>
                    <div className="an-error-actions">
                      {file && <button type="button" className="an-btn" onClick={() => setPhase('ready')}>Try again</button>}
                      <button type="button" className="an-btn" onClick={openPicker}>Choose another photo</button>
                    </div>
                  </div>
                </div>
              )}

              {phase === 'rejected' && (
                <div className="an-rejected" role="status">
                  <AlertTriangle size={16} />
                  <span>This photo failed the quality gate, so it was not graded. VITREOUS never grades an ungradeable capture; retake it using the steps below.</span>
                </div>
              )}

              {hasResult && (
                <div className="an-stack">
                  {visibleSteps.length - active > 2 && <div className="an-stack-ghost g2" aria-hidden="true" />}
                  {visibleSteps.length - active > 1 && <div className="an-stack-ghost g1" aria-hidden="true" />}
                  <AnimatePresence initial={false} custom={dir} mode="popLayout">
                    <motion.article
                      key={step.id}
                      className="an-card an-stage"
                      custom={dir}
                      variants={{
                        enter: (d) => ({ opacity: 0, x: reduce ? 0 : d * 40, rotate: reduce ? 0 : d * 1.5 }),
                        center: { opacity: 1, x: 0, rotate: 0 },
                        exit: (d) => ({ opacity: 0, x: reduce ? 0 : d * -60, rotate: reduce ? 0 : d * -2 }),
                      }}
                      initial="enter"
                      animate="center"
                      exit="exit"
                      transition={{ type: 'spring', stiffness: 260, damping: 28 }}
                    >
                      <p className="an-kicker">{step.kicker}</p>
                      <h3>{step.title}</h3>
                      <p className="an-desc">{step.desc}</p>
                      <StageDetails step={step} result={result} jobId={jobId} report={report} />
                    </motion.article>
                  </AnimatePresence>
                </div>
              )}
            </div>

            {/* Stage rail */}
            {(busy || hasResult) && (
              <div className="an-rail">
                <div className="an-rail-controls">
                  <button type="button" onClick={() => { setPlaying(false); goTo(active - 1); }} disabled={!hasResult || active === 0} aria-label="Previous stage">
                    <ChevronLeft size={16} />
                  </button>
                  <button
                    type="button"
                    className="an-play"
                    onClick={() => {
                      if (active >= visibleSteps.length - 1) setActive(0);
                      setPlaying((p) => !p);
                    }}
                    disabled={phase !== 'done'}
                    aria-label={playing ? 'Pause walkthrough' : 'Play walkthrough'}
                  >
                    {playing ? <Pause size={15} /> : <Play size={15} />}
                  </button>
                  <button type="button" onClick={() => { setPlaying(false); goTo(active + 1); }} disabled={!hasResult || active >= visibleSteps.length - 1} aria-label="Next stage">
                    <ChevronRight size={16} />
                  </button>
                </div>

                <div className="an-rail-track">
                  {GROUPS.map((g) => {
                    const members = STEPS.map((s, i) => ({ s, i })).filter(({ s }) => s.group === g);
                    return (
                      <div key={g} className="an-rail-group" style={{ flexGrow: members.length }}>
                        <div className="an-rail-segs">
                          {members.map(({ s, i }) => {
                            const st = stepState(s, i);
                            const isActive = hasResult && i === active;
                            const clickable = hasResult && st !== 'skipped';
                            return (
                              <button
                                key={s.id}
                                type="button"
                                className={`an-seg-step ${st}${isActive ? ' active' : ''}`}
                                onClick={() => { if (clickable) { setPlaying(false); goTo(i); } }}
                                disabled={!clickable}
                                title={s.title}
                                aria-label={`${s.kicker}: ${s.title}`}
                              >
                                <span className="an-seg-fill">
                                  {isActive && playing && (
                                    <motion.span
                                      key={`p-${active}`}
                                      initial={{ scaleX: 0 }}
                                      animate={{ scaleX: 1 }}
                                      transition={{ duration: STEP_MS / 1000, ease: 'linear' }}
                                    />
                                  )}
                                </span>
                              </button>
                            );
                          })}
                        </div>
                        <span className={`an-rail-label${hasResult && step.group === g ? ' current' : ''}`}>{g}</span>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </motion.section>
        )}
      </AnimatePresence>
    </div>
  );
}
