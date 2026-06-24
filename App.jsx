import { useState, useEffect } from 'react';
import Dashboard from './components/Dashboard.jsx';
import SessionViewer from './components/SessionViewer.jsx';

export default function App() {
  const [activeSession, setActiveSession] = useState(null);
  const [sessionUrl, setSessionUrl] = useState(null);
  const [starting, setStarting] = useState(false);

  const handleStartSession = async (type) => {
    setStarting(type);
    const res = await fetch(`/api/sessions/start/${type}`, { method: 'POST' });
    const data = await res.json();
    if (!data.success) throw new Error(data.error || 'Помилка запуску');
    setSessionUrl(data.vncUrl);
    setActiveSession(type);
    setStarting(false);
  };

  const handleEndSession = async () => {
    if (activeSession) {
      await fetch(`/api/sessions/stop/${activeSession}`, { method: 'POST' });
    }
    setActiveSession(null);
    setSessionUrl(null);
  };

  return activeSession ? (
    <SessionViewer type={activeSession} url={sessionUrl} onBack={handleEndSession} />
  ) : (
    <Dashboard onStart={handleStartSession} starting={starting} />
  );
}
