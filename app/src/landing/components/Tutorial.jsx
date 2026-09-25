import React, { useState, useRef, useEffect } from 'react';
import { motion } from 'framer-motion';
import { 
  Play, Pause, Volume2, VolumeX, Maximize2, 
  RotateCcw, Sparkles, Activity, ShieldCheck, 
  UserCheck, ArrowRight, Eye, Layers, CheckCircle2
} from 'lucide-react';

const CHAPTERS = [
  { id: 'onboarding', label: 'Patient Ingestion', time: 0, desc: 'Rural clinic check-in & non-mydriatic fundus capture' },
  { id: 'quality', label: 'Quality Assessment', time: 14, desc: 'Automated BRISQUE & focus sharpness gate' },
  { id: 'enhance', label: 'CLAHE Enhancement', time: 27, desc: 'Contrast-limited adaptive histogram equalization' },
  { id: 'triage', label: 'Multi-Task AI Triage', time: 42, desc: 'ResNet-18 ICDR DR classification (Grade 0–4)' },
  { id: 'explain', label: 'Dual-CAM Attribution', time: 55, desc: 'Grad-CAM & Score-CAM spatial consensus' },
];

export default function Tutorial() {
  const videoRef = useRef(null);
  const containerRef = useRef(null);
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
      { threshold: 0.35 }
    );

    if (containerRef.current) {
      observer.observe(containerRef.current);
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

          <h2 className="tutorial-h2" id="tutorial-h2">
            Three people. One seamless journey.
          </h2>

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
                <span className="chapter-pill-num">0{idx + 1}</span>
                <span className="chapter-pill-label">{ch.label}</span>
                {activeChapterIdx === idx && (
                  <motion.div 
                    className="chapter-pill-indicator" 
                    layoutId="activeChapterPill"
                    transition={{ type: "spring", stiffness: 350, damping: 30 }}
                  />
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Laptop Frame Mockup Showcase */}
        <div className="laptop-showcase-stage">
          <div className="laptop-ambient-glow" />

          <div className="laptop-mockup-frame">
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
                        background: `linear-gradient(to right, #2dd4bf ${(currentTime / duration) * 100}%, rgba(255,255,255,0.2) ${(currentTime / duration) * 100}%)`
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
          </div>
        </div>

        {/* 3 Step Persona Narrative Cards Underneath */}
        <div className="walkthrough-narrative-cards">
          <div className="narrative-card">
            <div className="narrative-icon-wrap patient-theme">
              <UserCheck size={20} />
            </div>
            <div className="narrative-content">
              <h4>1. Rural Clinic Patient</h4>
              <p>Non-invasive, dilation-free screening completed in under 3 minutes at any primary health centre (PHC).</p>
            </div>
          </div>

          <div className="narrative-card highlight">
            <div className="narrative-icon-wrap ai-theme">
              <Sparkles size={20} />
            </div>
            <div className="narrative-content">
              <h4>2. VITREOUS AI Engine</h4>
              <p>Automated BRISQUE quality gating, CLAHE enhancement, and multi-lesion diabetic retinopathy classification.</p>
            </div>
          </div>

          <div className="narrative-card">
            <div className="narrative-icon-wrap doctor-theme">
              <ShieldCheck size={20} />
            </div>
            <div className="narrative-content">
              <h4>3. Retinal Specialist</h4>
              <p>Dual-CAM explainability (Grad-CAM & Score-CAM) ensuring high clinical reliability with 1-click tele-ophthalmology signoff.</p>
            </div>
          </div>
        </div>

        {/* Direct Action Callout */}
        <div className="walkthrough-action-banner">
          <div className="action-text">
            <h3>Ready to test the live diagnostic pipeline?</h3>
            <p>Upload your own fundus photographs and inspect the real-time AI grading, CLAHE enhancement, and dual-CAM heatmaps.</p>
          </div>
          <a href="#/dashboard/analysis" className="walkthrough-cta-btn">
            <span>Launch Diagnostic Suite</span>
            <ArrowRight size={17} />
          </a>
        </div>
      </div>
    </section>
  );
}
