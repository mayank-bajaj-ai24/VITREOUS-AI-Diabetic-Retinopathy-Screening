import React, { useState } from 'react';
import {
  User, Mail, Phone, Building2, Shield,
  Calendar, MapPin, Edit3, Save, X,
  BadgeCheck, Clock, FileText, Award
} from 'lucide-react';
import FlashDeck from './dashboard/FlashDeck';

/* ICDR grading quick reference (International Clinical Diabetic Retinopathy scale) */
const ICDR_CARDS = [
  { grade: 0, name: 'No apparent retinopathy', sign: 'No abnormalities.', action: 'Rescreen in 12 months.' },
  { grade: 1, name: 'Mild NPDR', sign: 'Microaneurysms only.', action: 'Rescreen in 9–12 months.' },
  { grade: 2, name: 'Moderate NPDR', sign: 'More than microaneurysms alone, but less than severe NPDR: haemorrhages, hard exudates, cotton-wool spots.', action: 'Refer to an ophthalmologist within 3–6 months.' },
  { grade: 3, name: 'Severe NPDR', sign: 'The 4-2-1 rule: >20 intraretinal haemorrhages in each of 4 quadrants, venous beading in 2+ quadrants, or prominent IRMA in 1+ quadrant — and no signs of PDR.', action: 'Urgent referral within 2–4 weeks.' },
  { grade: 4, name: 'Proliferative DR', sign: 'Neovascularisation and/or vitreous or preretinal haemorrhage.', action: 'Immediate referral for laser or anti-VEGF treatment.' },
].map((g) => ({
  id: `g${g.grade}`,
  kicker: `ICDR grade ${g.grade}`,
  front: (
    <>
      <p className="fc-big">G{g.grade}</p>
      <p className="fc-title">{g.name}</p>
      <p className="fc-text">What does it look like, and what happens next?</p>
    </>
  ),
  back: (
    <>
      <p className="fc-title">{g.name}</p>
      <p className="fc-text">{g.sign}</p>
      <p className="fc-text" style={{ marginTop: 8 }}><b>{g.action}</b></p>
    </>
  ),
}));

// Mock user data — in production, this comes from DB via API
const MOCK_USER = {
  name: 'Dr. Ananya Sharma',
  role: 'Doctor',
  email: 'ananya.sharma@vitreous-health.in',
  phone: '+91 98765 43210',
  staffId: 'DOC-2024-1187',
  department: 'Ophthalmology',
  facility: 'AIIMS New Delhi — Retinal Screening Unit',
  location: 'New Delhi, India',
  joinDate: '12 March 2024',
  lastLogin: '25 Sep 2026, 10:12 AM',
  scansReviewed: 347,
  certifications: ['ICDR Grading Certified', 'DR Screening Protocol v2.1'],
  avatar: null,
};

export default function AccountTab() {
  const [user] = useState(MOCK_USER);
  const [editing, setEditing] = useState(false);
  const [editData, setEditData] = useState({ ...MOCK_USER });

  const handleSave = () => {
    // In production: POST to API
    setEditing(false);
  };

  const handleCancel = () => {
    setEditData({ ...user });
    setEditing(false);
  };

  return (
    <div className="account-tab">
      {/* Profile Header Card */}
      <div className="account-profile-header">
        <div className="profile-avatar-section">
          <div className="profile-avatar">
            {user.avatar ? (
              <img src={user.avatar} alt={user.name} />
            ) : (
              <span>{user.name.split(' ').map(n => n[0]).join('').slice(0, 2)}</span>
            )}
            <div className="avatar-badge">
              <BadgeCheck size={16} />
            </div>
          </div>
          <div className="profile-identity">
            <h2>{user.name}</h2>
            <div className="profile-role-tag">
              <Shield size={14} />
              <span>{user.role}</span>
            </div>
            <p className="profile-id">Staff ID: {user.staffId}</p>
          </div>
        </div>
        <div className="profile-actions">
          {!editing ? (
            <button className="edit-profile-btn" onClick={() => setEditing(true)}>
              <Edit3 size={16} />
              Edit Profile
            </button>
          ) : (
            <div className="edit-action-group">
              <button className="save-btn" onClick={handleSave}>
                <Save size={16} />
                Save
              </button>
              <button className="cancel-btn" onClick={handleCancel}>
                <X size={16} />
                Cancel
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="account-body">
        {/* Personal Information */}
        <div className="account-section">
          <div className="section-heading">
            <User size={18} />
            <h3>Personal Information</h3>
          </div>
          <div className="info-grid">
            <InfoField
              icon={<User size={16} />}
              label="Full Name"
              value={editData.name}
              editing={editing}
              onChange={(v) => setEditData(d => ({ ...d, name: v }))}
            />
            <InfoField
              icon={<Mail size={16} />}
              label="Email Address"
              value={editData.email}
              editing={editing}
              onChange={(v) => setEditData(d => ({ ...d, email: v }))}
            />
            <InfoField
              icon={<Phone size={16} />}
              label="Phone Number"
              value={editData.phone}
              editing={editing}
              onChange={(v) => setEditData(d => ({ ...d, phone: v }))}
            />
            <InfoField
              icon={<Building2 size={16} />}
              label="Department"
              value={editData.department}
              editing={editing}
              onChange={(v) => setEditData(d => ({ ...d, department: v }))}
            />
            <InfoField
              icon={<MapPin size={16} />}
              label="Facility"
              value={editData.facility}
              editing={false}
            />
            <InfoField
              icon={<MapPin size={16} />}
              label="Location"
              value={editData.location}
              editing={false}
            />
          </div>
        </div>

        {/* Grading reference */}
        <div className="account-section account-deck">
          <FlashDeck
            title="ICDR grading reference"
            subtitle="Flip each grade for its signs and follow-up"
            cards={ICDR_CARDS}
          />
        </div>

        {/* Activity & Stats */}
        <div className="account-section">
          <div className="section-heading">
            <FileText size={18} />
            <h3>Activity & Statistics</h3>
          </div>
          <div className="activity-stats-grid">
            <div className="activity-stat-card">
              <div className="activity-stat-icon teal">
                <Calendar size={20} />
              </div>
              <div>
                <span className="activity-stat-label">Member Since</span>
                <span className="activity-stat-value">{user.joinDate}</span>
              </div>
            </div>
            <div className="activity-stat-card">
              <div className="activity-stat-icon blue">
                <Clock size={20} />
              </div>
              <div>
                <span className="activity-stat-label">Last Login</span>
                <span className="activity-stat-value">{user.lastLogin}</span>
              </div>
            </div>
            <div className="activity-stat-card">
              <div className="activity-stat-icon orange">
                <FileText size={20} />
              </div>
              <div>
                <span className="activity-stat-label">Scans Reviewed</span>
                <span className="activity-stat-value">{user.scansReviewed}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Certifications */}
        <div className="account-section">
          <div className="section-heading">
            <Award size={18} />
            <h3>Certifications</h3>
          </div>
          <div className="certifications-list">
            {user.certifications.map((cert, i) => (
              <div key={i} className="cert-badge">
                <BadgeCheck size={16} />
                <span>{cert}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function InfoField({ icon, label, value, editing, onChange }) {
  return (
    <div className="info-field">
      <div className="info-field-label">
        {icon}
        <span>{label}</span>
      </div>
      {editing ? (
        <input
          type="text"
          className="info-field-input"
          value={value}
          onChange={(e) => onChange?.(e.target.value)}
        />
      ) : (
        <div className="info-field-value">{value}</div>
      )}
    </div>
  );
}
