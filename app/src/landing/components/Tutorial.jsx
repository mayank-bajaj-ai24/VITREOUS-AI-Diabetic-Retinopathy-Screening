import React, { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence, useScroll, useTransform, useReducedMotion } from 'framer-motion';
import SplitReveal from './SplitReveal';
import { 
  Play, Pause, Volume2, VolumeX, Maximize2, 
  RotateCcw, Sparkles, ShieldCheck,
  UserCheck, Check, ArrowRight
} from 'lucide-react';

const CHAPTERS = [
  { id: 'onboarding', label: 'Patient Ingestion', time: 0, desc: 'Rural clinic check-in & non-mydriatic fundus capture' },
  { id: 'quality', label: 'Quality Assessment', time: 14, desc: 'Automated BRISQUE & focus sharpness gate' },
  { id: 'enhance', label: 'CLAHE Enhancement', time: 27, desc: 'Contrast-limited adaptive histogram equalization' },
  { id: 'triage', label: 'Multi-Task AI Triage', time: 42, desc: 'ResNet-18 ICDR DR classification (Grade 0–4)' },
  { id: 'explain', label: 'Dual-CAM Attribution', time: 55, desc: 'Grad-CAM & Score-CAM spatial consensus' },
];

/* The three people in the video.
   `chapters` are the video chapters where that person is on screen. */
const ROLES = [
  {
    id: 'patient',
    Icon: UserCheck,
    title: 'Rural clinic patient',
    text: 'Non-invasive, dilation-free screening in under 3 minutes at any primary health centre.',
    steps: ['Registered at the PHC', 'Fundus photo captured', 'Result explained'],
    chapters: [0],
    jumpTo: 0,
  },
  {
    id: 'ai',
    Icon: Sparkles,
    title: 'VITREOUS AI engine',
    text: 'Quality gating, CLAHE enhancement and ICDR grading of diabetic retinopathy.',
    steps: ['Quality gate passed', 'Contrast enhanced', 'Graded on ICDR 0–4'],
    chapters: [1, 2, 3],
    jumpTo: 14,
  },
  {
    id: 'doctor',
    Icon: ShieldCheck,
    title: 'Retinal specialist',
    text: 'Reviews Grad-CAM and Score-CAM heatmaps, then signs off remotely in one click.',
    steps: ['Heatmaps compared', 'Findings confirmed', 'Referral signed'],
    chapters: [4],
    jumpTo: 55,
  },
];

function RoleCard({ role, index, active, progress, onOpen }) {
  const { Icon } = role;

  return (
    <motion.div
      className={`role-card${active ? ' active' : ''}`}
      role="button"
      tabIndex={0}
      aria-label={`${role.title}: jump to this part of the walkthrough`}
      onClick={onOpen}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onOpen();
        }
      }}
      initial={{ opacity: 0, y: 60 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.4 }}
      transition={{ duration: 0.9, ease: [0.16, 1, 0.3, 1], delay: index * 0.12 }}
    >
      {/* Ink rises to fill the card while this person is on screen */}
      <span className="role-ink" aria-hidden="true" />

      <div className="role-top">
        <span className="role-icon"><Icon size={20} /></span>
        <span className="role-index">0{index + 1}</span>
      </div>

      <h4 className="role-title">{role.title}</h4>
      <p className="role-text">{role.text}</p>

      <ul className="role-steps">
        {role.steps.map((step, i) => (
          <li key={step} style={{ transitionDelay: active ? `${0.35 + i * 0.3}s` : '0s' }}>
            <span className="role-check"><Check size={11} strokeWidth={3} /></span>
            {step}
          </li>
        ))}
      </ul>

      <span className="role-progress" aria-hidden="true">
        <span style={{ transform: `scaleX(${active ? progress : 0})` }} />
      </span>
    </motion.div>
  );
}

export default function Tutorial() {
  const videoRef = useRef(null);
  const containerRef = useRef(null);
  const stageRef = useRef(null);
  const reduceMotion = useReducedMotion();
  const { scrollYProgress: stageProgress } = useScroll({ target: stageRef, offset: ['start end', 'start 0.2'] });
  const laptopTilt = useTransform(stageProgress, [0, 1], reduceMotion ? [0, 0] : [32, 0]);
  const laptopScale = useTransform(stageProgress, [0, 1], reduceMotion ? [1, 1] : [0.84, 1]);
  const laptopLift = useTransform(stageProgress, [0, 1], reduceMotion ? [0, 0] : [80, 0]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isMuted, setIsMuted] = useState(true);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(69);
  const [showControls, setShowControls] = useState(true);
  const controlsTimeoutRef = useRef(null);

  // Auto-play when scrolled into view
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && videoRef.current) {
            videoRef.current.play()
              .then(() => setIsPlaying(true))
              .catch(() => {
                // Autoplay blocked by browser policy until interaction
                setIsPlaying(false);
              });
          } else if (!entry.isIntersecting && videoRef.current) {
            videoRef.current.pause();
            setIsPlaying(false);
          }
        });
      },
      { threshold: 0.5 }
    );

    if (stageRef.current) {
      observer.observe(stageRef.current);
    }

    return () => {
      observer.disconnect();
    };
  }, []);

  const handleTimeUpdate = () => {
    if (videoRef.current) {
      setCurrentTime(videoRef.current.currentTime);
    }
  };

  const handleLoadedMetadata = () => {
    if (videoRef.current) {
      setDuration(videoRef.current.duration || 69);
    }
  };

  const togglePlay = () => {
    if (!videoRef.current) return;
    if (isPlaying) {
      videoRef.current.pause();
      setIsPlaying(false);
    } else {
      videoRef.current.play()
        .then(() => setIsPlaying(true))
        .catch(() => {});
    }
  };

  const toggleMute = () => {
    if (!videoRef.current) return;
    videoRef.current.muted = !isMuted;
    setIsMuted(!isMuted);
  };

  const handleSeek = (e) => {
    const targetTime = parseFloat(e.target.value);
    if (videoRef.current) {
      videoRef.current.currentTime = targetTime;
      setCurrentTime(targetTime);
    }
  };

  const seekDelta = (seconds) => {
    if (!videoRef.current) return;
    const newTime = Math.max(0, Math.min(duration, videoRef.current.currentTime + seconds));
    videoRef.current.currentTime = newTime;
    setCurrentTime(newTime);
  };

  const jumpToChapter = (time) => {
    if (!videoRef.current) return;
    videoRef.current.currentTime = time;
    setCurrentTime(time);
    if (!isPlaying) {
      videoRef.current.play()
        .then(() => setIsPlaying(true))
        .catch(() => {});
    }
  };

  const toggleFullscreen = () => {
    if (!videoRef.current) return;
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    } else {
      if (videoRef.current.requestFullscreen) {
        videoRef.current.requestFullscreen();
      } else if (videoRef.current.webkitRequestFullscreen) {
        videoRef.current.webkitRequestFullscreen();
      }
    }
  };

  const handleMouseMove = () => {
    setShowControls(true);
    if (controlsTimeoutRef.current) clearTimeout(controlsTimeoutRef.current);
    controlsTimeoutRef.current = setTimeout(() => {
      if (isPlaying) setShowControls(false);
    }, 2800);
  };

  const formatTime = (secs) => {
    if (isNaN(secs)) return '0:00';
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  // Determine active chapter based on currentTime
  const activeChapterIdx = CHAPTERS.reduce((acc, curr, idx) => {
    return currentTime >= curr.time ? idx : acc;
  }, 0);
  const chapterEnd = CHAPTERS[activeChapterIdx + 1]?.time ?? duration;
  const chapterStart = CHAPTERS[activeChapterIdx].time;
  const chapterProgress = Math.min(1, Math.max(0, (currentTime - chapterStart) / Math.max(1, chapterEnd - chapterStart)));

  return (
    <section 
      className="tutorial-section laptop-walkthrough-section" 
      id="tutorial" 
      ref={containerRef}
      aria-labelledby="tutorial-h2"
    >
      <div className="laptop-walkthrough-container">
        {/* Section Header */}
        <div className="tutorial-header">
          <div className="section-label">
            <span className="dot" aria-hidden="true" />
            <span>Interactive Workflow Walkthrough</span>
          </div>

          <SplitReveal
            className="tutorial-h2"
            id="tutorial-h2"
            lines={['Three people.', 'One seamless journey.']}
          />

          <p className="tutorial-sub">
            Follow how VITREOUS functions in reality — from a rural clinic to specialist sign-off.
          </p>

          {/* Interactive Chapter Quick-Select Pills */}
          <div className="walkthrough-chapter-bar">
            {CHAPTERS.map((ch, idx) => (
              <button
                key={ch.id}
                className={`chapter-pill ${activeChapterIdx === idx ? 'active' : ''}`}
                onClick={() => jumpToChapter(ch.time)}
                type="button"
              >
                {activeChapterIdx === idx && (
                  <motion.span
                    className="chapter-pill-indicator"
                    layoutId="activeChapterPill"
                    transition={{ type: "spring", stiffness: 350, damping: 30 }}
                  >
                    <span
                      className="chapter-pill-progress"
                      style={{ transform: `scaleX(${chapterProgress})` }}
                    />
                  </motion.span>
                )}
                <span className="chapter-pill-num">0{idx + 1}</span>
                <span className="chapter-pill-label">{ch.label}</span>
              </button>
            ))}
          </div>

          <div className="chapter-desc" aria-live="polite">
            <AnimatePresence mode="wait">
              <motion.p
                key={CHAPTERS[activeChapterIdx].id}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.25 }}
              >
                {CHAPTERS[activeChapterIdx].desc}
              </motion.p>
            </AnimatePresence>
          </div>
        </div>

        {/* Laptop Frame Mockup Showcase */}
        <div className="laptop-showcase-stage" ref={stageRef}>
          <div className="laptop-ambient-glow" />

          <motion.div
            className="laptop-mockup-frame"
            style={{ rotateX: laptopTilt, scale: laptopScale, y: laptopLift, transformPerspective: 1600 }}
          >
            {/* Top Display Lid */}
            <div className="laptop-lid-chassis">
              {/* Top Bezel with Camera Notch & Indicator */}
              <div className="laptop-top-bezel">
                <div className="laptop-webcam-notch">
                  <span className="camera-lens" />
                  <span className="camera-sensor-led" />
                </div>
              </div>

              {/* 16:9 Inner Screen with Video Player */}
              <div 
                className="laptop-screen-viewport" 
                onMouseMove={handleMouseMove}
                onMouseLeave={() => isPlaying && setShowControls(false)}
                onClick={togglePlay}
              >
                <video
                  ref={videoRef}
                  src="/vitreous_walkthrough.mp4"
                  playsInline
                  muted={isMuted}
                  loop
                  onTimeUpdate={handleTimeUpdate}
                  onLoadedMetadata={handleLoadedMetadata}
                  onEnded={() => setIsPlaying(false)}
                  className="laptop-video-stream"
                />

                {/* Subtle Glass Reflection Glare */}
                <div className="laptop-screen-glare" />

                {/* Center Big Play Button Overlay */}
                {!isPlaying && (
                  <div className="laptop-big-play-overlay">
                    <div className="big-play-pulse-ring" />
                    <button 
                      className="big-play-btn" 
                      onClick={(e) => { e.stopPropagation(); togglePlay(); }}
                      aria-label="Play Project Walkthrough"
                    >
                      <Play size={32} fill="currentColor" />
                    </button>
                    <span className="big-play-caption">Click to Watch Full System Walkthrough</span>
                  </div>
                )}

                {/* Floating Modern HUD Video Controls */}
                <div 
                  className={`laptop-video-hud ${showControls || !isPlaying ? 'active' : ''}`}
                  onClick={(e) => e.stopPropagation()}
                >
                  <div className="hud-progress-track">
                    <input
                      type="range"
                      min="0"
                      max={duration || 100}
                      step="0.1"
                      value={currentTime}
                      onChange={handleSeek}
                      className="hud-scrubber-slider"
                      style={{
                        background: `linear-gradient(to right, #ffffff ${(currentTime / duration) * 100}%, rgba(255,255,255,0.2) ${(currentTime / duration) * 100}%)`
                      }}
                    />
                  </div>

                  <div className="hud-controls-row">
                    <div className="hud-left-group">
                      <button 
                        className="hud-ctrl-btn" 
                        onClick={togglePlay}
                        title={isPlaying ? 'Pause' : 'Play'}
                      >
                        {isPlaying ? <Pause size={17} /> : <Play size={17} fill="currentColor" />}
                      </button>

                      <button 
                        className="hud-ctrl-btn" 
                        onClick={() => seekDelta(-10)} 
                        title="Rewind 10 seconds"
                      >
                        <RotateCcw size={15} />
                      </button>

                      <button 
                        className="hud-ctrl-btn" 
                        onClick={toggleMute} 
                        title={isMuted ? 'Unmute' : 'Mute'}
                      >
                        {isMuted ? <VolumeX size={17} /> : <Volume2 size={17} />}
                      </button>

                      <span className="hud-time-display">
                        {formatTime(currentTime)} / {formatTime(duration)}
                      </span>
                    </div>

                    <div className="hud-right-group">
                      <div className="hud-status-badge">
                        <span className="hud-pulse-dot" />
                        <span>VITREOUS v2.4 Live Demo</span>
                      </div>

                      <button 
                        className="hud-ctrl-btn" 
                        onClick={toggleFullscreen} 
                        title="Toggle Fullscreen"
                      >
                        <Maximize2 size={16} />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Laptop Base / Keyboard Chassis Edge */}
            <div className="laptop-keyboard-lip">
              <div className="laptop-thumb-notch" />
            </div>

            {/* Bottom Surface Shadow */}
            <div className="laptop-ambient-shadow" />
          </motion.div>
        </div>

        {/* 3 Step Persona Narrative Cards Underneath */}
        <div className="walkthrough-narrative-cards">
          {ROLES.map((role, i) => {
            const start = CHAPTERS[role.chapters[0]].time;
            const end = CHAPTERS[role.chapters[role.chapters.length - 1] + 1]?.time ?? duration;
            return (
              <RoleCard
                key={role.id}
                role={role}
                index={i}
                active={role.chapters.includes(activeChapterIdx)}
                progress={Math.min(1, Math.max(0, (currentTime - start) / Math.max(1, end - start)))}
                onOpen={() => jumpToChapter(role.jumpTo)}
              />
            );
          })}
        </div>

        {/* Launch into the live dashboard */}
        <motion.div
          className="launch-banner"
          initial={{ opacity: 0, y: 30, scale: 0.96 }}
          whileInView={{ opacity: 1, y: 0, scale: 1 }}
          viewport={{ once: true, amount: 0.6 }}
          transition={{ type: 'spring', stiffness: 160, damping: 22 }}
        >
          <div className="launch-banner-text">
            <h3>Ready to test the live diagnostic pipeline?</h3>
            <p>Upload your own fundus photographs and inspect real-time AI grading, CLAHE enhancement and dual-CAM heatmaps.</p>
          </div>
          <a href="#/dashboard/analysis" className="launch-banner-btn">
            <span>Launch Diagnostic Suite</span>
            <ArrowRight size={17} />
          </a>
        </motion.div>
      </div>
    </section>
  );
}
