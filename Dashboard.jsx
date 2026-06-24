import { useState } from 'react';
import ServiceCard from './ServiceCard.jsx';

const SERVICES = [
  {
    id: 'browser',
    label: 'Cloud Browser',
    desc: 'Chromium у хмарі. Ніякого навантаження на твій девайс.',
    icon: '🌐',
    accent: '#4f46e5',
    glow: 'rgba(79,70,229,0.35)',
    tag: 'Готово',
  },
  {
    id: 'desktop',
    label: 'Cloud PC',
    desc: 'Ubuntu Linux + XFCE. Повноцінний робочий стіл у браузері.',
    icon: '🖥️',
    accent: '#ea580c',
    glow: 'rgba(234,88,12,0.35)',
    tag: 'Готово',
  },
  {
    id: 'phone',
    label: 'Cloud Phone',
    desc: 'Android-емулятор. Потрібна KVM підтримка на сервері.',
    icon: '📱',
    accent: '#10b981',
    glow: 'rgba(16,185,129,0.35)',
    tag: 'KVM',
  },
];

export default function Dashboard({ onStart, starting }) {
  const [error, setError] = useState(null);

  const handleStart = async (service) => {
    setError(null);
    try {
      await onStart(service.id);
    } catch (e) {
      setError(e.message || 'Не вдалось запустити сесію');
      setTimeout(() => setError(null), 5000);
    }
  };

  return (
    <div style={styles.root}>
      {/* Ambient orbs */}
      <div style={{ ...styles.orb, ...styles.orb1 }} />
      <div style={{ ...styles.orb, ...styles.orb2 }} />
      <div style={{ ...styles.orb, ...styles.orb3 }} />

      {/* Header */}
      <header style={styles.header}>
        <div style={styles.logo}>
          <span style={styles.logoIcon}>⚡</span>
          <span style={styles.logoText}>CloudPlay</span>
        </div>
        <div style={styles.pill}>
          <span style={styles.dot} />
          Онлайн
        </div>
      </header>

      {/* Content */}
      <main style={styles.main}>
        <div style={styles.hero}>
          <p style={styles.eyebrow}>Особистий хмарний сервер</p>
          <h1 style={styles.title}>
            Все що треба —<br />
            <span style={styles.grad}>прямо в браузері</span>
          </h1>
          <p style={styles.sub}>
            Запускай браузер, Linux або Android у хмарі.<br />
            Твій девайс — тільки екран.
          </p>
        </div>

        {error && (
          <div style={styles.errorBox}>⚠️ {error}</div>
        )}

        <div style={styles.grid}>
          {SERVICES.map(s => (
            <ServiceCard
              key={s.id}
              service={s}
              loading={starting === s.id}
              onStart={() => handleStart(s)}
            />
          ))}
        </div>

        <p style={styles.footnote}>Приватний сервер · 2-3 користувачі</p>
      </main>

      <style>{`
        @keyframes orbFloat {
          0%,100%{transform:translate(0,0)scale(1);}
          33%{transform:translate(40px,-30px)scale(1.08);}
          66%{transform:translate(-25px,25px)scale(0.94);}
        }
        @keyframes dotPulse {
          0%,100%{opacity:1;}50%{opacity:0.4;}
        }
        @keyframes gradShift {
          0%,100%{background-position:0% 50%;}
          50%{background-position:100% 50%;}
        }
      `}</style>
    </div>
  );
}

const styles = {
  root: {
    minHeight: '100vh',
    background: '#06060f',
    fontFamily: "'Space Grotesk', sans-serif",
    color: '#fff',
    position: 'relative',
    overflow: 'hidden',
  },
  orb: {
    position: 'fixed',
    borderRadius: '50%',
    filter: 'blur(120px)',
    pointerEvents: 'none',
    animation: 'orbFloat 9s ease-in-out infinite',
  },
  orb1: {
    width: 700, height: 700,
    background: '#4f46e5',
    opacity: 0.1,
    top: -300, right: -200,
    animationDelay: '0s',
  },
  orb2: {
    width: 600, height: 600,
    background: '#7c3aed',
    opacity: 0.09,
    bottom: -200, left: -200,
    animationDelay: '-4s',
  },
  orb3: {
    width: 400, height: 400,
    background: '#10b981',
    opacity: 0.06,
    top: '40%', left: '40%',
    animationDelay: '-7s',
  },
  header: {
    position: 'relative',
    zIndex: 10,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '22px 48px',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
    backdropFilter: 'blur(12px)',
  },
  logo: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    fontWeight: 700,
    fontSize: 20,
    letterSpacing: '-0.5px',
  },
  logoIcon: { fontSize: 26, filter: 'drop-shadow(0 0 10px rgba(255,200,0,0.7))' },
  logoText: { color: '#fff' },
  pill: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    fontSize: 13,
    color: 'rgba(255,255,255,0.55)',
    background: 'rgba(16,185,129,0.08)',
    border: '1px solid rgba(16,185,129,0.25)',
    padding: '6px 14px',
    borderRadius: 20,
    fontFamily: "'Inter', sans-serif",
  },
  dot: {
    display: 'inline-block',
    width: 7, height: 7,
    background: '#10b981',
    borderRadius: '50%',
    boxShadow: '0 0 8px #10b981',
    animation: 'dotPulse 2.2s ease-in-out infinite',
  },
  main: {
    position: 'relative',
    zIndex: 10,
    maxWidth: 1080,
    margin: '0 auto',
    padding: '72px 48px 60px',
  },
  hero: {
    marginBottom: 56,
    maxWidth: 640,
  },
  eyebrow: {
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: '2px',
    textTransform: 'uppercase',
    color: 'rgba(255,255,255,0.3)',
    marginBottom: 16,
    fontFamily: "'Inter', sans-serif",
  },
  title: {
    fontSize: 'clamp(38px, 6vw, 68px)',
    fontWeight: 700,
    lineHeight: 1.1,
    letterSpacing: '-2px',
    marginBottom: 20,
  },
  grad: {
    background: 'linear-gradient(135deg, #818cf8, #a78bfa, #34d399)',
    backgroundSize: '200% 200%',
    WebkitBackgroundClip: 'text',
    WebkitTextFillColor: 'transparent',
    animation: 'gradShift 5s ease infinite',
  },
  sub: {
    fontSize: 17,
    lineHeight: 1.65,
    color: 'rgba(255,255,255,0.45)',
    fontFamily: "'Inter', sans-serif",
    fontWeight: 400,
  },
  errorBox: {
    background: 'rgba(239,68,68,0.1)',
    border: '1px solid rgba(239,68,68,0.3)',
    color: '#f87171',
    padding: '14px 20px',
    borderRadius: 12,
    fontSize: 14,
    marginBottom: 24,
    fontFamily: "'Inter', sans-serif",
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(290px, 1fr))',
    gap: 20,
    marginBottom: 48,
  },
  footnote: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.18)',
    fontFamily: "'Inter', sans-serif",
    letterSpacing: '0.5px',
  },
};
