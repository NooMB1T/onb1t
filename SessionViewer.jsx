import { useState } from 'react';

const TITLES = {
  browser: { icon: '🌐', name: 'Cloud Browser', sub: 'Chromium' },
  desktop: { icon: '🖥️', name: 'Cloud PC', sub: 'Ubuntu Linux' },
  phone:   { icon: '📱', name: 'Cloud Phone', sub: 'Android' },
};

export default function SessionViewer({ type, url, onBack }) {
  const [loaded, setLoaded] = useState(false);
  const info = TITLES[type] || TITLES.browser;

  return (
    <div style={styles.root}>
      {/* Toolbar */}
      <div style={styles.toolbar}>
        <button style={styles.backBtn} onClick={onBack}>
          ← Назад
        </button>
        <div style={styles.sessionInfo}>
          <span style={styles.sessionIcon}>{info.icon}</span>
          <div>
            <div style={styles.sessionName}>{info.name}</div>
            <div style={styles.sessionSub}>{info.sub}</div>
          </div>
        </div>
        <div style={styles.statusPill}>
          <span style={styles.statusDot} />
          Активна сесія
        </div>
        <button
          style={styles.fullscreenBtn}
          onClick={() => {
            const el = document.querySelector('iframe');
            if (el?.requestFullscreen) el.requestFullscreen();
          }}
          title="Повний екран"
        >
          ⛶
        </button>
      </div>

      {/* Viewer */}
      <div style={styles.viewerWrap}>
        {!loaded && (
          <div style={styles.loadingScreen}>
            <div style={styles.loadSpinner} />
            <p style={styles.loadText}>Запускаємо сесію...</p>
            <p style={styles.loadSub}>Зазвичай займає 10–25 секунд</p>
          </div>
        )}
        {url && (
          <iframe
            src={url}
            style={{ ...styles.frame, opacity: loaded ? 1 : 0 }}
            onLoad={() => setLoaded(true)}
            allow="clipboard-read; clipboard-write"
            title={info.name}
          />
        )}
      </div>

      <style>{`
        @keyframes spinIt {
          to { transform: rotate(360deg); }
        }
        @keyframes statusPulse {
          0%,100% { box-shadow: 0 0 0 0 rgba(16,185,129,0.5); }
          50% { box-shadow: 0 0 0 5px rgba(16,185,129,0); }
        }
      `}</style>
    </div>
  );
}

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    height: '100vh',
    background: '#06060f',
    fontFamily: "'Space Grotesk', sans-serif",
    color: '#fff',
  },
  toolbar: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    padding: '10px 20px',
    background: 'rgba(255,255,255,0.03)',
    borderBottom: '1px solid rgba(255,255,255,0.07)',
    flexShrink: 0,
  },
  backBtn: {
    background: 'rgba(255,255,255,0.07)',
    border: '1px solid rgba(255,255,255,0.1)',
    color: '#fff',
    padding: '7px 14px',
    borderRadius: 8,
    cursor: 'pointer',
    fontSize: 13,
    fontFamily: "'Space Grotesk', sans-serif",
    fontWeight: 500,
    transition: 'background 0.2s',
  },
  sessionInfo: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    gap: 10,
  },
  sessionIcon: { fontSize: 22 },
  sessionName: { fontSize: 14, fontWeight: 600 },
  sessionSub: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.35)',
    fontFamily: "'Inter', sans-serif",
  },
  statusPill: {
    display: 'flex',
    alignItems: 'center',
    gap: 7,
    fontSize: 12,
    color: 'rgba(255,255,255,0.45)',
    fontFamily: "'Inter', sans-serif",
  },
  statusDot: {
    display: 'inline-block',
    width: 8, height: 8,
    background: '#10b981',
    borderRadius: '50%',
    animation: 'statusPulse 2.5s ease-in-out infinite',
  },
  fullscreenBtn: {
    background: 'rgba(255,255,255,0.07)',
    border: '1px solid rgba(255,255,255,0.1)',
    color: '#fff',
    width: 34, height: 34,
    borderRadius: 8,
    cursor: 'pointer',
    fontSize: 16,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  viewerWrap: {
    flex: 1,
    position: 'relative',
    overflow: 'hidden',
  },
  loadingScreen: {
    position: 'absolute',
    inset: 0,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    background: '#06060f',
    zIndex: 5,
  },
  loadSpinner: {
    width: 48, height: 48,
    border: '3px solid rgba(255,255,255,0.08)',
    borderTopColor: '#818cf8',
    borderRadius: '50%',
    animation: 'spinIt 0.9s linear infinite',
  },
  loadText: {
    fontSize: 18,
    fontWeight: 600,
    color: 'rgba(255,255,255,0.8)',
  },
  loadSub: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.28)',
    fontFamily: "'Inter', sans-serif",
  },
  frame: {
    position: 'absolute',
    inset: 0,
    width: '100%',
    height: '100%',
    border: 'none',
    transition: 'opacity 0.4s ease',
  },
};
