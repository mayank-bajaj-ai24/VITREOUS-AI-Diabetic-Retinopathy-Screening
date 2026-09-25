import React from 'react';
import { HashRouter, Routes, Route } from 'react-router-dom';
import LandingPage from './landing/LandingPage';
import Login from './Login';
import Dashboard from './Dashboard';

export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/login" element={<Login />} />
        <Route path="/dashboard/*" element={<Dashboard />} />
        <Route path="*" element={<LandingPage />} />
      </Routes>
    </HashRouter>
  );
}
