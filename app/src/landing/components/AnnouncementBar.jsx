import React, { useState } from 'react';

export default function AnnouncementBar() {
  const [dismissed, setDismissed] = useState(false);
  if (dismissed) return null;

  return (
    <div className="ann-bar" role="banner">
      <span className="ann-pill">SIH 2026</span>
      <span className="ann-text">
        Built by Team ByteCrew · Problem Statement 26038 · MedTech / HealthTech
      </span>
      <button
        className="ann-dismiss"
        onClick={() => setDismissed(true)}
        aria-label="Dismiss announcement"
      >
        ×
      </button>
    </div>
  );
}
