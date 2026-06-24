import { useState } from 'react';

export default function ServiceCard({ service, loading, onStart }) {
  const [hovered, setHovered] = useState(false);

  return (
    <div
      style={{
        ...styles.card,
        borderColor: hovered ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.07)',
        transform: hovered && !loading ? 'translateY(-5px)' : 'none',
        background: hovered
          ? 'rgba(255,255,255,0.06)'
          : 'rgba(255,255,255,0.03)',
      }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onClick={!loading ? onStart : undefined}
    >
      {/* Glow */}
      <div style={{
        ...styles.glow,
        background: service.glow,
        opacity: hovered ? 1 : 0.4,
      }} />

      {/* Top accent bar */}
      <div style={{
        ...styles.topBar,
        background: service.accent,
        opacity: hovered ? 1 : 0.6,
      }} />

      {/* Tag */}
      <div style={{
        ...styles.tag,
        background: `${service.accent}20`,
        borderColor: `${service.accent}40`,
        color: service.accent,
      }}>
        {service.tag}
      </div>

      {/* Icon */}
      <div style={styles.icon}>{service.icon}</div>

      {/* Text */}
      <h3 style={styles.label}>{service.label}</h3>
      <p style={styles.desc}>{service.desc}</p>

      {/* Button */}
      <button
        style={{
          ...styles.btn,
          background: hovered
            ? `${service.accent}30`
            : 'rgba(255,255,255,0.06)',
          borderColor: hovered
            ? `${service.accent}60`
            : 'rgba(255,255,255,0.1)',
          cursor: loading ? 'not-allowed' : 'pointer',
          opacity: loading ? 0.7 : 1,
        }}
        disabled={loading}
      >
        {loading ? (
          <span style={styles.spinner} />
        ) : (
          <>Запустити <span style={{ marginLeft: 4 }}>→</span></>
        )}
      </button>

      <style>{`
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}

const styles = {
  card: {
    position: 'relative',
    border: '1px solid rgba(255,255,255,0.07)',
    borderRadius: 20,
    padding: '28px 28px 24px',
    cursor: 'pointer',
    overflow: 'hidden',
    transition: 'all 0.28s ease',
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    fontFamily: "'Space Grotesk', sans-serif",
  },
  glow: {
    position: 'absolute',
    inset: -60,
    filter: 'blur(80px)',
    transition: 'opacity 0.3s',
    pointerEvents: 'none',
    zIndex: 0,
  },
  topBar: {
    position: 'absolute',
    top: 0, left: 0, right: 0,
    height: 2,
    transition: 'opacity 0.3s',
    zIndex: 1,
  },
  tag: {
    position: 'relative',
    zIndex: 1,
    display: 'inline-block',
    alignSelf: 'flex-start',
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '1px',
    textTransform: 'uppercase',
    border: '1px solid',
    padding: '3px 10px',
    borderRadius: 6,
    fontFamily: "'Inter', sans-serif",
  },
  icon: {
    position: 'relative',
    zIndex: 1,
    fontSize: 44,
    lineHeight: 1,
    marginTop: 4,
  },
  label: {
    position: 'relative',
    zIndex: 1,
    fontSize: 22,
    fontWeight: 700,
    letterSpacing: '-0.5px',
    color: '#fff',
    margin: 0,
  },
  desc: {
    position: 'relative',
    zIndex: 1,
    fontSize: 14,
    color: 'rgba(255,255,255,0.45)',
    lineHeight: 1.6,
    margin: 0,
    fontFamily: "'Inter', sans-serif",
    flexGrow: 1,
  },
  btn: {
    position: 'relative',
    zIndex: 1,
    marginTop: 8,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    padding: '12px 20px',
    border: '1px solid',
    borderRadius: 10,
    color: '#fff',
    fontSize: 14,
    fontWeight: 600,
    fontFamily: "'Space Grotesk', sans-serif",
    transition: 'all 0.2s ease',
    letterSpacing: '0.2px',
  },
  spinner: {
    display: 'inline-block',
    width: 16, height: 16,
    border: '2px solid rgba(255,255,255,0.2)',
    borderTopColor: '#fff',
    borderRadius: '50%',
    animation: 'spin 0.7s linear infinite',
  },
};
