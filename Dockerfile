FROM ubuntu:22.04
# CloudPlay v1.2 — ONE FILE, все всередині
LABEL maintainer="CloudPlay"
ENV DEBIAN_FRONTEND=noninteractive TZ=UTC LANG=C.UTF-8 CLOUDPLAY_PASSWORD=cloudplay

# 1. Пакети
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc xauth dbus-x11 \
    openbox xfce4 xfce4-terminal \
    chromium-browser \
    python3 python3-pip \
    wget curl unzip supervisor nginx \
    net-tools procps fonts-liberation fontconfig libfontconfig1 \
    && pip3 install --no-cache-dir websockify \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. noVNC
RUN mkdir -p /opt/novnc \
    && wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
       | tar xz --strip-components=1 -C /opt/novnc \
    && ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# 4. Директорії
RUN mkdir -p /app/frontend/src/components /app/backend \
    && mkdir -p /var/log/supervisor /var/log/nginx /run/nginx \
    && mkdir -p /root/.config/openbox /root/.config/xfce4 \
    && rm -f /etc/nginx/sites-enabled/default

RUN cat > /app/frontend/package.json << 'CPEOF000'
{
  "name": "cloudplay-frontend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --port 5173",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  }
}

CPEOF000

RUN cat > /app/frontend/vite.config.js << 'CPEOF001'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:3001',
    },
  },
});

CPEOF001

RUN cat > /app/frontend/index.html << 'CPEOF002'
<!DOCTYPE html>
<html lang="uk">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>CloudPlay</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=Inter:wght@400;500&display=swap" rel="stylesheet" />
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body, #root { height: 100%; }
      body { background: #06060f; overflow-x: hidden; }
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>

CPEOF002

RUN cat > /app/frontend/src/main.jsx << 'CPEOF003'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

CPEOF003

RUN cat > /app/frontend/src/App.jsx << 'CPEOF004'
import { useState, useCallback, useEffect } from 'react';
import Login from './components/Login.jsx';
import Dashboard from './components/Dashboard.jsx';
import SessionViewer from './components/SessionViewer.jsx';
import Toast from './components/Toast.jsx';

const getToken = () => localStorage.getItem('cp_token');

export default function App() {
  const [authed, setAuthed]           = useState(!!getToken());
  const [activeSession, setActive]    = useState(null);
  const [sessionUrl, setUrl]          = useState(null);
  const [toasts, setToasts]           = useState([]);

  const toast = useCallback((msg, type = 'info') => {
    const id = Date.now() + Math.random();
    setToasts(t => [...t, { id, msg, type }]);
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 4000);
  }, []);

  const handleLogin = async (password) => {
    const res  = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password }),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error || 'Невірний пароль');
    localStorage.setItem('cp_token', data.token);
    setAuthed(true);
  };

  const handleLogout = () => {
    localStorage.removeItem('cp_token');
    setAuthed(false);
    setActive(null);
    setUrl(null);
  };

  const handleStart = async (type, options = {}) => {
    const res = await fetch(`/api/sessions/start/${type}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${getToken()}`,
      },
      body: JSON.stringify(options),
    });
    const data = await res.json();
    if (!data.success) throw new Error(data.error);
    setUrl(data.vncUrl);
    setActive(type);
    const icons = { browser: '🌐', desktop: '🖥️', phone: '📱' };
    toast(`${icons[type]} Сесія запущена!`, 'success');
  };

  const handleStop = async () => {
    if (activeSession) {
      await fetch(`/api/sessions/stop/${activeSession}`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${getToken()}` },
      });
      toast('Сесію завершено', 'info');
    }
    setActive(null);
    setUrl(null);
  };

  if (!authed)      return <><Login onLogin={handleLogin} /><Toast toasts={toasts} /></>;
  if (activeSession) return <><SessionViewer type={activeSession} url={sessionUrl} onBack={handleStop} /><Toast toasts={toasts} /></>;
  return <><Dashboard onStart={handleStart} onLogout={handleLogout} toast={toast} /><Toast toasts={toasts} /></>;
}

CPEOF004

RUN cat > /app/frontend/src/components/Login.jsx << 'CPEOF005'
import { useState } from 'react';

export default function Login({ onLogin }) {
  const [pw, setPw]         = useState('');
  const [err, setErr]       = useState('');
  const [loading, setLoad]  = useState(false);
  const [shake, setShake]   = useState(false);

  const submit = async () => {
    if (!pw) return;
    setLoad(true); setErr('');
    try {
      await onLogin(pw);
    } catch (e) {
      setErr(e.message);
      setShake(true);
      setTimeout(() => setShake(false), 500);
    } finally { setLoad(false); }
  };

  return (
    <div style={s.root}>
      <Aurora />
      <div style={{ ...s.card, animation: shake ? 'shake .4s ease' : 'none' }}>
        <div style={s.logoWrap}>
          <span style={s.logoIcon}>⚡</span>
          <span style={s.logoText}>CloudPlay</span>
          <span style={s.version}>v1.2</span>
        </div>
        <p style={s.hint}>Введи пароль для доступу</p>
        <input
          type="password"
          placeholder="••••••••"
          value={pw}
          onChange={e => setPw(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && submit()}
          style={s.input}
          autoFocus
        />
        {err && <p style={s.err}>⚠ {err}</p>}
        <button onClick={submit} disabled={loading} style={s.btn}>
          {loading ? <span style={s.spinner} /> : 'Увійти →'}
        </button>
        <p style={s.footer}>Особистий хмарний сервер</p>
      </div>
      <style>{`
        @keyframes shake {
          0%,100%{transform:translateX(0)} 20%{transform:translateX(-10px)}
          40%{transform:translateX(10px)} 60%{transform:translateX(-6px)}
          80%{transform:translateX(6px)}
        }
        @keyframes spinL { to{transform:rotate(360deg)} }
        @keyframes fadeIn { from{opacity:0;transform:translateY(20px)} to{opacity:1;transform:none} }
      `}</style>
    </div>
  );
}

function Aurora() {
  return (
    <div style={a.wrap}>
      <div style={{ ...a.orb, ...a.o1 }} />
      <div style={{ ...a.orb, ...a.o2 }} />
      <div style={{ ...a.orb, ...a.o3 }} />
      <div style={{ ...a.orb, ...a.o4 }} />
      <style>{`
        @keyframes a1{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(60px,-40px)scale(1.15)}}
        @keyframes a2{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(-50px,60px)scale(1.1)}}
        @keyframes a3{0%,100%{transform:translate(-50%,-50%)scale(1)}50%{transform:translate(-50%,-50%)scale(1.2)}}
        @keyframes a4{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(40px,50px)scale(0.9)}}
      `}</style>
    </div>
  );
}

const s = {
  root: { minHeight:'100vh', display:'flex', alignItems:'center', justifyContent:'center',
    background:'#030308', fontFamily:"'Space Grotesk',sans-serif", position:'relative' },
  card: { position:'relative', zIndex:10, width:360, padding:'40px 36px',
    background:'rgba(255,255,255,0.05)', backdropFilter:'blur(24px)',
    border:'1px solid rgba(255,255,255,0.1)',
    boxShadow:'0 0 0 1px rgba(255,255,255,0.04) inset, 0 40px 80px rgba(0,0,0,0.5)',
    borderRadius:24, animation:'fadeIn .5s ease' },
  logoWrap: { display:'flex', alignItems:'center', gap:10, marginBottom:28 },
  logoIcon: { fontSize:32, filter:'drop-shadow(0 0 12px rgba(255,200,0,.7))' },
  logoText: { fontSize:22, fontWeight:700, color:'#fff', letterSpacing:-0.5 },
  version: { fontSize:11, color:'rgba(255,255,255,.3)', border:'1px solid rgba(255,255,255,.1)',
    padding:'2px 7px', borderRadius:6, fontFamily:"'Inter',sans-serif" },
  hint: { fontSize:14, color:'rgba(255,255,255,.45)', marginBottom:20,
    fontFamily:"'Inter',sans-serif" },
  input: { width:'100%', padding:'14px 16px', background:'rgba(255,255,255,.07)',
    border:'1px solid rgba(255,255,255,.12)', borderRadius:12, color:'#fff',
    fontSize:16, outline:'none', boxSizing:'border-box', fontFamily:"'Space Grotesk',sans-serif",
    marginBottom:8 },
  err: { fontSize:13, color:'#f87171', margin:'4px 0 8px', fontFamily:"'Inter',sans-serif" },
  btn: { width:'100%', padding:'14px', background:'linear-gradient(135deg,#4f46e5,#7c3aed)',
    border:'none', borderRadius:12, color:'#fff', fontSize:15, fontWeight:600,
    cursor:'pointer', marginTop:8, fontFamily:"'Space Grotesk',sans-serif",
    boxShadow:'0 4px 24px rgba(79,70,229,.4)', transition:'opacity .2s' },
  spinner: { display:'inline-block', width:16, height:16,
    border:'2px solid rgba(255,255,255,.3)', borderTopColor:'#fff',
    borderRadius:'50%', animation:'spinL .7s linear infinite' },
  footer: { textAlign:'center', fontSize:12, color:'rgba(255,255,255,.18)',
    marginTop:24, fontFamily:"'Inter',sans-serif" },
};
const a = {
  wrap: { position:'fixed', inset:0, pointerEvents:'none', overflow:'hidden' },
  orb:  { position:'absolute', borderRadius:'50%', filter:'blur(100px)' },
  o1: { width:700, height:700, background:'#4f46e5', opacity:.12,
    top:-200, right:-100, animation:'a1 10s ease-in-out infinite' },
  o2: { width:600, height:600, background:'#7c3aed', opacity:.1,
    bottom:-150, left:-150, animation:'a2 13s ease-in-out infinite' },
  o3: { width:400, height:400, background:'#06b6d4', opacity:.07,
    top:'50%', left:'50%', animation:'a3 8s ease-in-out infinite' },
  o4: { width:300, height:300, background:'#10b981', opacity:.06,
    bottom:100, right:100, animation:'a4 11s ease-in-out infinite' },
};

CPEOF005

RUN cat > /app/frontend/src/components/Dashboard.jsx << 'CPEOF006'
import { useState, useEffect } from 'react';
import ServiceCard from './ServiceCard.jsx';
import StatsBar from './StatsBar.jsx';

const SERVICES = [
  { id:'browser', label:'Cloud Browser', icon:'🌐',
    desc:'Chromium у хмарі. Нічого не грузить твій девайс.',
    accent:'#4f46e5', gradient:'linear-gradient(135deg,#4f46e5,#7c3aed)', glow:'rgba(79,70,229,0.5)' },
  { id:'desktop', label:'Cloud PC', icon:'🖥️',
    desc:'Ubuntu Linux з XFCE. Повноцінний ПК у браузері.',
    accent:'#ea580c', gradient:'linear-gradient(135deg,#ea580c,#dc2626)', glow:'rgba(234,88,12,0.5)' },
  { id:'phone', label:'Cloud Phone', icon:'📱',
    desc:'Android 11 з swiftshader. Мобільні додатки у хмарі.',
    accent:'#10b981', gradient:'linear-gradient(135deg,#10b981,#0891b2)', glow:'rgba(16,185,129,0.5)' },
];

export default function Dashboard({ onStart, onLogout, toast }) {
  const [loading, setLoading]   = useState(null);
  const [statuses, setStatuses] = useState({});

  useEffect(() => {
    const poll = async () => {
      try {
        const r = await fetch('/api/sessions/status', {
          headers: { 'Authorization': `Bearer ${localStorage.getItem('cp_token')}` }
        });
        setStatuses(await r.json());
      } catch {}
    };
    poll();
    const id = setInterval(poll, 5000);
    return () => clearInterval(id);
  }, []);

  const handleStart = async (service) => {
    setLoading(service.id);
    try { await onStart(service.id); }
    catch (e) { toast(e.message, 'error'); }
    finally { setLoading(null); }
  };

  const handleReconnect = (type) => {
    onStart(type).catch(() => {});
  };

  const handleStop = async (type) => {
    await fetch(`/api/sessions/stop/${type}`, {
      method:'POST',
      headers:{ 'Authorization': `Bearer ${localStorage.getItem('cp_token')}` }
    });
    setStatuses(s => ({ ...s, [type]:{ running:false } }));
    toast('Сесію зупинено', 'info');
  };

  return (
    <div style={s.root}>
      <Aurora />
      <header style={s.header}>
        <div style={s.logo}>
          <span style={s.lIcon}>⚡</span>
          <span style={s.lName}>CloudPlay</span>
          <span style={s.ver}>v1.2</span>
        </div>
        <div style={{flex:1, display:'flex', justifyContent:'center'}}>
          <StatsBar statuses={statuses} />
        </div>
        <button style={s.logout} onClick={onLogout} title="Вийти">⏻</button>
      </header>

      <main style={s.main}>
        <div style={s.hero}>
          <p style={s.eye}>Особистий хмарний сервер</p>
          <h1 style={s.title}>Твоя хмара,<br /><span style={s.grad}>твої правила</span></h1>
          <p style={s.sub}>Запускай браузер, Linux або Android прямо у браузері телефону.</p>
        </div>

        <div style={s.grid}>
          {SERVICES.map(sv => (
            <ServiceCard key={sv.id} service={sv}
              status={statuses[sv.id]}
              loading={loading === sv.id}
              onStart={() => handleStart(sv)}
              onReconnect={() => handleReconnect(sv.id)}
              onStop={() => handleStop(sv.id)}
            />
          ))}
        </div>
        <p style={s.foot}>CloudPlay v1.2 · Приватний · 2-3 юзери</p>
      </main>

      <style>{`
        @keyframes a1{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(60px,-40px)scale(1.1)}}
        @keyframes a2{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(-50px,60px)scale(1.08)}}
        @keyframes a3{0%,100%{transform:translate(-50%,-50%)scale(1)}50%{transform:translate(-50%,-50%)scale(1.18)}}
        @keyframes gS{0%,100%{background-position:0% 50%}50%{background-position:100% 50%}}
        @keyframes fU{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}
      `}</style>
    </div>
  );
}

function Aurora() {
  return (
    <div style={{position:'fixed',inset:0,pointerEvents:'none',overflow:'hidden',zIndex:0}}>
      <div style={{position:'absolute',width:800,height:800,background:'#4f46e5',opacity:.1,top:-300,right:-200,borderRadius:'50%',filter:'blur(120px)',animation:'a1 11s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:700,height:700,background:'#7c3aed',opacity:.09,bottom:-200,left:-200,borderRadius:'50%',filter:'blur(120px)',animation:'a2 14s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:500,height:500,background:'#06b6d4',opacity:.07,top:'50%',left:'50%',borderRadius:'50%',filter:'blur(100px)',animation:'a3 9s ease-in-out infinite'}}/>
    </div>
  );
}

const s = {
  root:{minHeight:'100vh',background:'#030308',fontFamily:"'Space Grotesk',sans-serif",color:'#fff',position:'relative',overflow:'hidden'},
  header:{position:'relative',zIndex:10,display:'flex',alignItems:'center',gap:16,padding:'18px 40px',borderBottom:'1px solid rgba(255,255,255,0.06)',backdropFilter:'blur(12px)'},
  logo:{display:'flex',alignItems:'center',gap:10},
  lIcon:{fontSize:26,filter:'drop-shadow(0 0 10px rgba(255,200,0,.7))'},
  lName:{fontSize:20,fontWeight:700,letterSpacing:'-.5px'},
  ver:{fontSize:11,color:'rgba(255,255,255,.3)',border:'1px solid rgba(255,255,255,.1)',padding:'2px 8px',borderRadius:6,fontFamily:"'Inter',sans-serif"},
  logout:{background:'rgba(255,255,255,.06)',border:'1px solid rgba(255,255,255,.1)',color:'rgba(255,255,255,.5)',width:36,height:36,borderRadius:9,cursor:'pointer',fontSize:16},
  main:{position:'relative',zIndex:10,maxWidth:1080,margin:'0 auto',padding:'64px 40px 48px'},
  hero:{marginBottom:52,animation:'fU .6s ease'},
  eye:{fontSize:11,fontWeight:600,letterSpacing:'2.5px',textTransform:'uppercase',color:'rgba(255,255,255,.28)',marginBottom:16,fontFamily:"'Inter',sans-serif"},
  title:{fontSize:'clamp(36px,6vw,66px)',fontWeight:700,lineHeight:1.1,letterSpacing:'-2px',marginBottom:16},
  grad:{background:'linear-gradient(135deg,#818cf8,#a78bfa,#34d399)',backgroundSize:'200% 200%',WebkitBackgroundClip:'text',WebkitTextFillColor:'transparent',animation:'gS 5s ease infinite'},
  sub:{fontSize:16,lineHeight:1.65,color:'rgba(255,255,255,.42)',fontFamily:"'Inter',sans-serif"},
  grid:{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(290px,1fr))',gap:18,marginBottom:40},
  foot:{fontSize:12,color:'rgba(255,255,255,.16)',fontFamily:"'Inter',sans-serif",letterSpacing:'.5px'},
};

CPEOF006

RUN cat > /app/frontend/src/components/ServiceCard.jsx << 'CPEOF007'
import { useState, useEffect } from 'react';

const ICONS = { browser:'🌐', desktop:'🖥️', phone:'📱' };

export default function ServiceCard({ service, status, loading, onStart, onReconnect, onStop }) {
  const [hovered, setHovered] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const isRunning = status?.running;

  useEffect(() => {
    if (!isRunning || !status?.startTime) return;
    const tick = () => setElapsed(Math.floor((Date.now() - new Date(status.startTime)) / 1000));
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [isRunning, status?.startTime]);

  const fmt = s => {
    const h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
    if (h > 0) return `${h}:${String(m).padStart(2,'0')}:${String(sec).padStart(2,'0')}`;
    return `${m}:${String(sec).padStart(2,'0')}`;
  };

  return (
    <div
      style={{
        ...s.card,
        borderColor: isRunning
          ? `${service.accent}50`
          : hovered ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.07)',
        transform: hovered && !loading ? 'translateY(-6px)' : 'none',
        background: isRunning
          ? `${service.accent}0d`
          : hovered ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.03)',
        boxShadow: isRunning
          ? `0 0 0 1px ${service.accent}30 inset, 0 20px 60px ${service.accent}15`
          : hovered ? '0 20px 60px rgba(0,0,0,0.3)' : '0 4px 24px rgba(0,0,0,0.2)',
      }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {/* Top accent */}
      <div style={{
        ...s.topBar,
        background: service.gradient,
        opacity: isRunning ? 1 : hovered ? 0.8 : 0.4,
      }} />

      {/* Glow */}
      <div style={{
        ...s.glow,
        background: service.glow,
        opacity: isRunning ? 0.25 : hovered ? 0.15 : 0.06,
      }} />

      {/* Status badge */}
      <div style={{ ...s.badge, ...(isRunning ? s.badgeOn : s.badgeOff) }}>
        {isRunning
          ? <><span style={{ ...s.bdot, background:'#10b981', boxShadow:'0 0 6px #10b981' }} />Запущено</>
          : <><span style={{ ...s.bdot, background:'rgba(255,255,255,0.3)' }} />Очікує</>
        }
      </div>

      {/* Icon */}
      <div style={s.icon}>{service.icon}</div>

      {/* Name */}
      <h3 style={s.name}>{service.label}</h3>
      <p style={s.desc}>{service.desc}</p>

      {/* Timer (якщо running) */}
      {isRunning && (
        <div style={s.timer}>
          <span style={s.timerIcon}>⏱</span>
          <span style={s.timerVal}>{fmt(elapsed)}</span>
        </div>
      )}

      {/* Buttons */}
      <div style={s.btnRow}>
        {isRunning ? (
          <>
            <button style={{ ...s.btn, ...s.btnPrimary, background: service.gradient }}
              onClick={onReconnect}>
              ▶ Підключитись
            </button>
            <button style={{ ...s.btn, ...s.btnStop }} onClick={onStop} title="Зупинити">
              ⏹
            </button>
          </>
        ) : (
          <button
            style={{
              ...s.btn, ...s.btnLaunch,
              background: hovered ? `${service.accent}25` : 'rgba(255,255,255,0.06)',
              borderColor: hovered ? `${service.accent}60` : 'rgba(255,255,255,0.1)',
              cursor: loading ? 'wait' : 'pointer',
            }}
            onClick={onStart}
            disabled={loading}
          >
            {loading
              ? <><span style={s.spinner} /> Запускаємо...</>
              : <>🚀 Запустити</>
            }
          </button>
        )}
      </div>

      {/* Bottom border rim */}
      <div style={{ ...s.rimBottom, background: service.gradient, opacity: isRunning ? 0.5 : hovered ? 0.3 : 0.12 }} />

      <style>{`@keyframes sp{to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}

const s = {
  card: {
    position:'relative', borderRadius:20, padding:'24px 24px 20px',
    border:'1px solid', cursor:'default', overflow:'hidden',
    display:'flex', flexDirection:'column', gap:10,
    transition:'all .28s cubic-bezier(.4,0,.2,1)',
    backdropFilter:'blur(16px)',
    fontFamily:"'Space Grotesk',sans-serif",
  },
  topBar: { position:'absolute', top:0, left:0, right:0, height:2, zIndex:1 },
  glow: { position:'absolute', inset:-60, filter:'blur(80px)', pointerEvents:'none', transition:'opacity .3s' },
  badge: { position:'relative', zIndex:1, alignSelf:'flex-start', display:'flex',
    alignItems:'center', gap:6, fontSize:11, fontWeight:600, letterSpacing:'.8px',
    textTransform:'uppercase', padding:'4px 10px', borderRadius:6, border:'1px solid',
    fontFamily:"'Inter',sans-serif" },
  badgeOn:  { background:'rgba(16,185,129,.12)', borderColor:'rgba(16,185,129,.3)', color:'#10b981' },
  badgeOff: { background:'rgba(255,255,255,.05)', borderColor:'rgba(255,255,255,.1)', color:'rgba(255,255,255,.4)' },
  bdot: { display:'inline-block', width:6, height:6, borderRadius:'50%' },
  icon: { position:'relative', zIndex:1, fontSize:44, lineHeight:1, marginTop:4 },
  name: { position:'relative', zIndex:1, fontSize:21, fontWeight:700, letterSpacing:'-.5px', color:'#fff', margin:0 },
  desc: { position:'relative', zIndex:1, fontSize:13, color:'rgba(255,255,255,.45)',
    lineHeight:1.6, margin:0, fontFamily:"'Inter',sans-serif", flexGrow:1 },
  timer: { position:'relative', zIndex:1, display:'flex', alignItems:'center', gap:6,
    fontSize:13, color:'rgba(255,255,255,.5)', fontFamily:"'Inter',sans-serif" },
  timerIcon: { fontSize:12 },
  timerVal: { fontVariantNumeric:'tabular-nums', letterSpacing:'.5px', fontWeight:500 },
  btnRow: { position:'relative', zIndex:1, display:'flex', gap:8, marginTop:4 },
  btn: { display:'flex', alignItems:'center', justifyContent:'center', gap:8,
    padding:'11px 16px', borderRadius:10, fontSize:13, fontWeight:600,
    fontFamily:"'Space Grotesk',sans-serif", border:'1px solid', transition:'all .2s', cursor:'pointer' },
  btnPrimary: { flex:1, color:'#fff', borderColor:'transparent',
    boxShadow:'0 4px 16px rgba(0,0,0,.3)' },
  btnStop: { width:44, color:'#f87171', background:'rgba(239,68,68,.1)',
    borderColor:'rgba(239,68,68,.3)', flexShrink:0 },
  btnLaunch: { flex:1, color:'#fff', transition:'all .25s' },
  spinner: { display:'inline-block', width:13, height:13,
    border:'2px solid rgba(255,255,255,.2)', borderTopColor:'#fff',
    borderRadius:'50%', animation:'sp .7s linear infinite' },
  rimBottom: { position:'absolute', bottom:0, left:0, right:0, height:1, transition:'opacity .3s' },
};

CPEOF007

RUN cat > /app/frontend/src/components/SessionViewer.jsx << 'CPEOF008'
import { useState, useCallback } from 'react';

const META = {
  browser: { icon: '🌐', name: 'Cloud Browser', sub: 'Chromium' },
  desktop: { icon: '🖥️', name: 'Cloud PC',      sub: 'Ubuntu XFCE' },
  phone:   { icon: '📱', name: 'Cloud Phone',   sub: 'Android 11' },
};

// ── ADB helper ───────────────────────────────────────────────────
async function adbKey(keycode) {
  try {
    await fetch('/api/adb/keyevent', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ keycode }),
    });
  } catch {}
}

async function adbRotate(orientation) {
  try {
    await fetch('/api/adb/rotate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orientation }),
    });
  } catch {}
}

// ── Phone Frame ──────────────────────────────────────────────────
function PhoneFrame({ url, loaded, onLoad }) {
  const [landscape, setLandscape] = useState(false);
  const [volVisible, setVolVisible] = useState(false);

  const handleRotate = async () => {
    const next = !landscape;
    setLandscape(next);
    await adbRotate(next ? 1 : 0);
  };

  const W = landscape ? 720 : 340;
  const H = landscape ? 340 : 720;

  return (
    <div style={ph.wrapper}>
      {/* Controls left panel */}
      <div style={ph.leftPanel}>
        <ControlBtn icon="🔊" title="Гучніше" onClick={() => adbKey(24)} />
        <ControlBtn icon="🔉" title="Тихіше" onClick={() => adbKey(25)} />
        <div style={{ height: 16 }} />
        <ControlBtn icon="⏻" title="Живлення" onClick={() => adbKey(26)} />
        <div style={{ height: 16 }} />
        <ControlBtn icon={landscape ? '📱' : '🔄'} title="Повернути" onClick={handleRotate} />
      </div>

      {/* Phone device */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0 }}>
        <div style={{
          ...ph.device,
          width: W,
          height: H,
          transition: 'width 0.4s ease, height 0.4s ease',
        }}>
          {/* Side power button */}
          <div style={{
            ...ph.sideBtn,
            right: -5,
            top: landscape ? '35%' : '22%',
            height: landscape ? 40 : 60,
          }} />
          {/* Side vol buttons */}
          <div style={{
            ...ph.sideBtn,
            left: -5,
            top: landscape ? '28%' : '18%',
            height: landscape ? 28 : 42,
          }} />
          <div style={{
            ...ph.sideBtn,
            left: -5,
            top: landscape ? '48%' : '26%',
            height: landscape ? 28 : 42,
          }} />

          {/* Punch-hole camera */}
          {!landscape && (
            <div style={ph.camera} />
          )}
          {landscape && (
            <div style={{ ...ph.camera, top: '50%', left: 22, transform: 'translateY(-50%)' }} />
          )}

          {/* Screen */}
          <div style={ph.screen}>
            {!loaded && (
              <div style={ph.bootScreen}>
                <div style={ph.androidLogo}>🤖</div>
                <div style={ph.bootSpinner} />
                <p style={ph.bootText}>Android завантажується...</p>
                <p style={ph.bootSub}>Перший запуск займає 30-60 секунд</p>
                <div style={ph.bootBar}>
                  <div style={ph.bootBarFill} />
                </div>
              </div>
            )}
            {url && (
              <iframe
                src={url}
                style={{
                  ...ph.iframe,
                  opacity: loaded ? 1 : 0,
                }}
                onLoad={onLoad}
                title="Android Phone"
              />
            )}
          </div>

          {/* Android gesture bar */}
          <div style={ph.gestureBar} />
        </div>

        {/* Hardware nav buttons */}
        <div style={ph.navbar}>
          <NavBtn icon="◁" label="Назад" onClick={() => adbKey(4)} />
          <NavBtn icon="⬤" label="Додому" onClick={() => adbKey(3)} primary />
          <NavBtn icon="▣" label="Додатки" onClick={() => adbKey(187)} />
        </div>
      </div>

      {/* Controls right panel */}
      <div style={ph.rightPanel}>
        <ControlBtn icon="📸" title="Знімок" onClick={() => adbKey(26)} />
        <div style={{ height: 16 }} />
        <ControlBtn icon="🔒" title="Заблокувати" onClick={() => adbKey(26)} />
        <div style={{ height: 16 }} />
        <ControlBtn icon="🔍" title="Пошук" onClick={() => adbKey(84)} />
        <div style={{ height: 16 }} />
        <ControlBtn icon="📋" title="Меню" onClick={() => adbKey(82)} />
      </div>

      <style>{`
        @keyframes bootSpin {
          to { transform: rotate(360deg); }
        }
        @keyframes bootFill {
          0% { width: 0%; }
          20% { width: 30%; }
          50% { width: 60%; }
          80% { width: 85%; }
          100% { width: 95%; }
        }
      `}</style>
    </div>
  );
}

function ControlBtn({ icon, title, onClick }) {
  const [pressed, setPressed] = useState(false);
  return (
    <button
      title={title}
      style={{
        ...ph.ctrlBtn,
        background: pressed ? 'rgba(255,255,255,0.15)' : 'rgba(255,255,255,0.06)',
        transform: pressed ? 'scale(0.9)' : 'scale(1)',
      }}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => { setPressed(false); onClick(); }}
      onMouseLeave={() => setPressed(false)}
    >
      {icon}
    </button>
  );
}

function NavBtn({ icon, label, onClick, primary }) {
  const [pressed, setPressed] = useState(false);
  return (
    <button
      title={label}
      style={{
        ...ph.navBtn,
        background: pressed
          ? 'rgba(255,255,255,0.18)'
          : primary
            ? 'rgba(255,255,255,0.10)'
            : 'rgba(255,255,255,0.05)',
        transform: pressed ? 'scale(0.88)' : 'scale(1)',
        border: primary
          ? '1px solid rgba(255,255,255,0.2)'
          : '1px solid rgba(255,255,255,0.08)',
      }}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => { setPressed(false); onClick(); }}
      onMouseLeave={() => setPressed(false)}
    >
      <span style={{ fontSize: primary ? 20 : 16 }}>{icon}</span>
      <span style={ph.navLabel}>{label}</span>
    </button>
  );
}

// ── Main Viewer ───────────────────────────────────────────────────
export default function SessionViewer({ type, url, onBack }) {
  const [loaded, setLoaded] = useState(false);
  const meta = META[type] || META.browser;
  const isPhone = type === 'phone';

  const handleLoad = useCallback(() => setLoaded(true), []);

  return (
    <div style={s.root}>
      {/* Toolbar */}
      <div style={s.toolbar}>
        <button style={s.backBtn} onClick={onBack}>← Назад</button>
        <div style={s.sessionInfo}>
          <span style={{ fontSize: 20 }}>{meta.icon}</span>
          <div>
            <div style={s.sessionName}>{meta.name}</div>
            <div style={s.sessionSub}>{meta.sub}</div>
          </div>
        </div>
        <div style={s.statusPill}>
          <span style={s.dot} />
          {loaded ? 'Активна' : 'Завантаження...'}
        </div>
        {!isPhone && (
          <button
            style={s.fsBtn}
            title="Повний екран"
            onClick={() => {
              document.querySelector('iframe')?.requestFullscreen?.();
            }}
          >⛶</button>
        )}
      </div>

      {/* Content */}
      <div style={s.content}>
        {isPhone ? (
          <PhoneFrame url={url} loaded={loaded} onLoad={handleLoad} />
        ) : (
          <div style={s.frameWrap}>
            {!loaded && (
              <div style={s.loadScreen}>
                <div style={s.spinner} />
                <p style={s.loadText}>Запускаємо сесію...</p>
                <p style={s.loadSub}>10–25 секунд</p>
              </div>
            )}
            {url && (
              <iframe
                src={url}
                style={{ ...s.frame, opacity: loaded ? 1 : 0 }}
                onLoad={handleLoad}
                title={meta.name}
                allow="clipboard-read; clipboard-write"
              />
            )}
          </div>
        )}
      </div>

      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes dotPulse {
          0%,100%{box-shadow:0 0 0 0 rgba(16,185,129,.5);}
          50%{box-shadow:0 0 0 5px rgba(16,185,129,0);}
        }
      `}</style>
    </div>
  );
}

// ── Styles ────────────────────────────────────────────────────────
const s = {
  root: {
    display: 'flex', flexDirection: 'column',
    height: '100vh', background: '#06060f',
    fontFamily: "'Space Grotesk', sans-serif", color: '#fff',
  },
  toolbar: {
    display: 'flex', alignItems: 'center', gap: 12,
    padding: '10px 20px',
    background: 'rgba(255,255,255,0.03)',
    borderBottom: '1px solid rgba(255,255,255,0.07)',
    flexShrink: 0,
  },
  backBtn: {
    background: 'rgba(255,255,255,0.07)',
    border: '1px solid rgba(255,255,255,0.1)',
    color: '#fff', padding: '7px 14px',
    borderRadius: 8, cursor: 'pointer',
    fontSize: 13, fontFamily: "'Space Grotesk', sans-serif",
  },
  sessionInfo: {
    flex: 1, display: 'flex', alignItems: 'center', gap: 10,
  },
  sessionName: { fontSize: 14, fontWeight: 600 },
  sessionSub: {
    fontSize: 11, color: 'rgba(255,255,255,0.35)',
    fontFamily: "'Inter', sans-serif",
  },
  statusPill: {
    display: 'flex', alignItems: 'center', gap: 7,
    fontSize: 12, color: 'rgba(255,255,255,0.45)',
    fontFamily: "'Inter', sans-serif",
  },
  dot: {
    display: 'inline-block', width: 8, height: 8,
    background: '#10b981', borderRadius: '50%',
    animation: 'dotPulse 2.5s ease-in-out infinite',
  },
  fsBtn: {
    background: 'rgba(255,255,255,0.07)',
    border: '1px solid rgba(255,255,255,0.1)',
    color: '#fff', width: 34, height: 34,
    borderRadius: 8, cursor: 'pointer', fontSize: 16,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  },
  content: {
    flex: 1, position: 'relative', overflow: 'auto',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: 'radial-gradient(ellipse at center, #0d0d20 0%, #06060f 100%)',
  },
  frameWrap: { position: 'absolute', inset: 0 },
  frame: {
    position: 'absolute', inset: 0,
    width: '100%', height: '100%',
    border: 'none', transition: 'opacity 0.4s ease',
  },
  loadScreen: {
    position: 'absolute', inset: 0,
    display: 'flex', flexDirection: 'column',
    alignItems: 'center', justifyContent: 'center', gap: 16,
  },
  spinner: {
    width: 48, height: 48,
    border: '3px solid rgba(255,255,255,0.08)',
    borderTopColor: '#818cf8', borderRadius: '50%',
    animation: 'spin 0.9s linear infinite',
  },
  loadText: { fontSize: 18, fontWeight: 600, color: 'rgba(255,255,255,0.8)' },
  loadSub: { fontSize: 13, color: 'rgba(255,255,255,0.28)', fontFamily: "'Inter',sans-serif" },
};

const ph = {
  wrapper: {
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    gap: 32, padding: 24,
  },
  leftPanel: {
    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
  },
  rightPanel: {
    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
  },
  device: {
    background: 'linear-gradient(160deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)',
    borderRadius: 48,
    border: '3px solid rgba(255,255,255,0.09)',
    boxShadow: `
      0 0 0 6px #0c0c1a,
      0 60px 120px rgba(0,0,0,0.7),
      inset 0 0 50px rgba(255,255,255,0.02),
      inset 0 1px 0 rgba(255,255,255,0.08)
    `,
    position: 'relative',
    overflow: 'hidden',
    flexShrink: 0,
  },
  sideBtn: {
    position: 'absolute',
    width: 4,
    background: 'linear-gradient(to bottom, #2a2a3e, #1a1a2e)',
    borderRadius: 4,
    boxShadow: '0 0 0 1px rgba(255,255,255,0.06)',
  },
  camera: {
    position: 'absolute',
    top: 18, left: '50%',
    transform: 'translateX(-50%)',
    width: 12, height: 12,
    background: '#0c0c1a',
    borderRadius: '50%',
    border: '2px solid rgba(255,255,255,0.06)',
    zIndex: 10,
    boxShadow: 'inset 0 0 4px rgba(100,149,237,0.3)',
  },
  screen: {
    position: 'absolute',
    inset: 0,
    background: '#000',
    overflow: 'hidden',
  },
  iframe: {
    position: 'absolute', inset: 0,
    width: '100%', height: '100%',
    border: 'none',
    transition: 'opacity 0.5s ease',
  },
  gestureBar: {
    position: 'absolute',
    bottom: 10, left: '50%',
    transform: 'translateX(-50%)',
    width: 100, height: 4,
    background: 'rgba(255,255,255,0.25)',
    borderRadius: 3, zIndex: 10,
  },
  bootScreen: {
    position: 'absolute', inset: 0, zIndex: 5,
    background: 'linear-gradient(160deg, #0a0a1e, #1a0a2e)',
    display: 'flex', flexDirection: 'column',
    alignItems: 'center', justifyContent: 'center',
    gap: 14, padding: 24,
  },
  androidLogo: { fontSize: 52, filter: 'drop-shadow(0 0 20px rgba(61,220,132,0.5))' },
  bootSpinner: {
    width: 36, height: 36,
    border: '3px solid rgba(61,220,132,0.2)',
    borderTopColor: '#3ddc84',
    borderRadius: '50%',
    animation: 'bootSpin 1s linear infinite',
  },
  bootText: {
    fontSize: 14, fontWeight: 600,
    color: 'rgba(255,255,255,0.8)',
    fontFamily: "'Space Grotesk', sans-serif",
  },
  bootSub: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.35)',
    textAlign: 'center',
    fontFamily: "'Inter', sans-serif",
  },
  bootBar: {
    width: '80%', height: 3,
    background: 'rgba(255,255,255,0.08)',
    borderRadius: 2, overflow: 'hidden',
  },
  bootBarFill: {
    height: '100%',
    background: 'linear-gradient(90deg, #3ddc84, #06b6d4)',
    borderRadius: 2,
    animation: 'bootFill 45s ease-out forwards',
  },
  navbar: {
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    gap: 8, marginTop: 0,
    background: 'rgba(255,255,255,0.03)',
    border: '1px solid rgba(255,255,255,0.07)',
    borderTop: 'none',
    borderRadius: '0 0 16px 16px',
    padding: '10px 16px',
    width: '100%',
  },
  navBtn: {
    display: 'flex', flexDirection: 'column',
    alignItems: 'center', justifyContent: 'center',
    gap: 4, flex: 1,
    padding: '10px 4px',
    borderRadius: 12,
    cursor: 'pointer', color: '#fff',
    transition: 'all 0.15s ease',
    fontFamily: "'Space Grotesk', sans-serif",
  },
  navLabel: {
    fontSize: 9, color: 'rgba(255,255,255,0.4)',
    fontFamily: "'Inter', sans-serif",
    letterSpacing: '0.5px',
  },
  ctrlBtn: {
    width: 44, height: 44,
    borderRadius: 12,
    border: '1px solid rgba(255,255,255,0.09)',
    color: '#fff', cursor: 'pointer',
    fontSize: 18, transition: 'all 0.15s ease',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontFamily: 'inherit',
  },
};

CPEOF008

RUN cat > /app/frontend/src/components/Toast.jsx << 'CPEOF009'
import { useEffect, useState } from 'react';

const COLORS = {
  success: { bg:'rgba(16,185,129,.15)', border:'rgba(16,185,129,.35)', icon:'✅' },
  error:   { bg:'rgba(239,68,68,.15)',  border:'rgba(239,68,68,.35)',  icon:'❌' },
  info:    { bg:'rgba(99,102,241,.15)', border:'rgba(99,102,241,.35)', icon:'ℹ️' },
};

function ToastItem({ toast }) {
  const [visible, setVisible] = useState(false);
  useEffect(() => { requestAnimationFrame(() => setVisible(true)); }, []);
  const c = COLORS[toast.type] || COLORS.info;
  return (
    <div style={{
      ...s.toast,
      background: c.bg,
      borderColor: c.border,
      opacity: visible ? 1 : 0,
      transform: visible ? 'none' : 'translateX(40px)',
    }}>
      <span>{c.icon}</span>
      <span style={s.msg}>{toast.msg}</span>
    </div>
  );
}

export default function Toast({ toasts }) {
  return (
    <div style={s.wrap}>
      {toasts.map(t => <ToastItem key={t.id} toast={t} />)}
      <style>{`@keyframes fadeOut{to{opacity:0}}`}</style>
    </div>
  );
}

const s = {
  wrap: { position:'fixed', top:20, right:20, zIndex:9999,
    display:'flex', flexDirection:'column', gap:10 },
  toast: { display:'flex', alignItems:'center', gap:10,
    padding:'12px 18px', borderRadius:12,
    border:'1px solid', backdropFilter:'blur(12px)',
    color:'#fff', fontSize:14, fontFamily:"'Space Grotesk',sans-serif",
    boxShadow:'0 8px 32px rgba(0,0,0,.3)', minWidth:240,
    transition:'all .3s ease' },
  msg: { flex:1 },
};

CPEOF009

RUN cat > /app/frontend/src/components/StatsBar.jsx << 'CPEOF010'
import { useState, useEffect } from 'react';

export default function StatsBar() {
  const [stats, setStats] = useState(null);

  useEffect(() => {
    const fetch_ = async () => {
      try {
        const r = await fetch('/api/stats', {
          headers: { 'Authorization': `Bearer ${localStorage.getItem('cp_token')}` }
        });
        setStats(await r.json());
      } catch {}
    };
    fetch_();
    const id = setInterval(fetch_, 4000);
    return () => clearInterval(id);
  }, []);

  const activeSessions = stats
    ? Object.values(stats.sessions || {}).filter(s => s.running).length
    : 0;
  const ramPct = stats?.memory
    ? Math.round((stats.memory.used / stats.memory.total) * 100)
    : null;

  return (
    <div style={s.bar}>
      <Chip icon="🖥️" label={`${activeSessions} активних`} glow={activeSessions > 0 ? '#10b981' : null} />
      {ramPct !== null && (
        <Chip
          icon="💾"
          label={`RAM ${ramPct}%`}
          glow={ramPct > 80 ? '#ef4444' : ramPct > 60 ? '#f59e0b' : null}
        />
      )}
      {stats?.uptime && <Chip icon="⏱️" label={fmtUptime(stats.uptime)} />}
    </div>
  );
}

function Chip({ icon, label, glow }) {
  return (
    <div style={{
      ...s.chip,
      borderColor: glow ? `${glow}50` : 'rgba(255,255,255,0.1)',
      background: glow ? `${glow}15` : 'rgba(255,255,255,0.05)',
    }}>
      <span>{icon}</span>
      <span style={s.chipLabel}>{label}</span>
      {glow && <span style={{ ...s.dot, background: glow, boxShadow: `0 0 6px ${glow}` }} />}
    </div>
  );
}

function fmtUptime(secs) {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  return h > 0 ? `${h}г ${m}хв` : `${m}хв`;
}

const s = {
  bar: { display:'flex', alignItems:'center', gap:8, flexWrap:'wrap' },
  chip: {
    display:'flex', alignItems:'center', gap:6,
    padding:'5px 12px', borderRadius:20,
    border:'1px solid', fontSize:12,
    fontFamily:"'Inter',sans-serif", color:'rgba(255,255,255,0.65)',
    transition:'all .3s',
  },
  chipLabel: { letterSpacing:'0.2px' },
  dot: { width:6, height:6, borderRadius:'50%', display:'inline-block' },
};

CPEOF010

RUN cat > /app/backend/package.json << 'CPEOF011'
{
  "name": "cloudplay-backend",
  "version": "1.0.0",
  "type": "commonjs",
  "scripts": {
    "start": "node server.js",
    "dev": "node --watch server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "uuid": "^9.0.0"
  }
}

CPEOF011

RUN cat > /app/backend/sessionManager.js << 'CPEOF012'
const { spawn, execSync } = require('child_process');
const { v4: uuidv4 } = require('uuid');

const ANDROID_SDK = process.env.ANDROID_SDK_ROOT || '/opt/android-sdk';

const CONFIGS = {
  browser: { display: ':1', vncPort: 5901, wsPort: 6901, res: '1920x1080x24' },
  desktop: { display: ':2', vncPort: 5902, wsPort: 6902, res: '1920x1080x24' },
  phone:   { display: ':3', vncPort: 5903, wsPort: 6903, res: '1080x2340x24' },
};

const sessions = { browser: null, desktop: null, phone: null };

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function spawnProc(cmd, args, env = {}) {
  const proc = spawn(cmd, args, {
    env: { ...process.env, ...env },
    stdio: 'ignore',
    detached: false,
  });
  proc.on('error', err => console.error(`[${cmd}] error:`, err.message));
  return proc;
}

async function startSession(type) {
  if (sessions[type]) await stopSession(type);
  const cfg = CONFIGS[type];
  if (!cfg) throw new Error('Unknown type');

  console.log(`\n▶ Starting [${type}] on ${cfg.display}...`);
  const procs = {};

  // ── 1. Xvfb ─────────────────────────────────────────────────
  procs.xvfb = spawnProc('Xvfb', [
    cfg.display,
    '-screen', '0', cfg.res,
    '-ac', '-nolisten', 'tcp', '-noreset',
  ]);
  await sleep(1200);

  // ── 2. WM + App ──────────────────────────────────────────────
  if (type === 'browser') {
    procs.wm = spawnProc('openbox', [], { DISPLAY: cfg.display });
    await sleep(600);
    procs.app = spawnProc('chromium-browser', [
      '--no-sandbox', '--disable-dev-shm-usage',
      '--disable-gpu', '--start-maximized',
      'https://www.google.com',
    ], { DISPLAY: cfg.display });

  } else if (type === 'desktop') {
    procs.wm = spawnProc('bash', ['-c', 'startxfce4'], {
      DISPLAY: cfg.display,
      DBUS_SESSION_BUS_ADDRESS: '/dev/null',
      HOME: '/root',
    });

  } else if (type === 'phone') {
    // Openbox як WM для emulator вікна
    procs.wm = spawnProc('openbox', ['--config-file', '/dev/null'], {
      DISPLAY: cfg.display,
    });
    await sleep(800);

    // Android emulator з swiftshader (БЕЗ KVM)
    procs.app = spawnProc(
      `${ANDROID_SDK}/emulator/emulator`,
      [
        '-avd', 'CloudPhone',
        '-no-audio',
        '-no-boot-anim',
        '-gpu', 'swiftshader_indirect',
        '-no-accel',             // не потребує KVM!
        '-screen', 'multi-touch',
        '-memory', '2048',
        '-cores', '2',
        '-camera-back', 'none',
        '-camera-front', 'none',
        '-dns-server', '8.8.8.8',
      ],
      {
        DISPLAY: cfg.display,
        ANDROID_SDK_ROOT: ANDROID_SDK,
        ANDROID_AVD_HOME: '/root/.android/avd',
        ANDROID_EMULATOR_HOME: '/root/.android',
        ANDROID_EMULATOR_USE_SYSTEM_LIBS: '1',
        LD_LIBRARY_PATH: `${ANDROID_SDK}/emulator/lib64/qt/lib:${ANDROID_SDK}/emulator/lib64`,
        HOME: '/root',
      }
    );

    console.log('[phone] Emulator starting (30-60s на завантаження Android)...');
  }

  await sleep(type === 'phone' ? 5000 : 2500);

  // ── 3. x11vnc ────────────────────────────────────────────────
  procs.vnc = spawnProc('x11vnc', [
    '-display', cfg.display,
    '-forever', '-nopw', '-quiet', '-shared',
    '-rfbport', String(cfg.vncPort),
  ]);
  await sleep(800);

  // ── 4. websockify ────────────────────────────────────────────
  procs.ws = spawnProc('websockify', [
    String(cfg.wsPort),
    `localhost:${cfg.vncPort}`,
  ]);
  await sleep(400);

  sessions[type] = { id: uuidv4(), type, procs, startTime: new Date() };
  console.log(`✅ [${type}] ready. VNC:${cfg.vncPort} WS:${cfg.wsPort}`);
  return sessions[type];
}

async function stopSession(type) {
  const s = sessions[type];
  if (!s) return;
  console.log(`⏹ Stopping [${type}]...`);
  for (const proc of Object.values(s.procs).reverse()) {
    try { if (proc && !proc.killed) proc.kill('SIGTERM'); } catch {}
  }
  sessions[type] = null;
}

function getAllStatus() {
  const out = {};
  for (const [type, s] of Object.entries(sessions)) {
    out[type] = s ? { running: true, id: s.id, startTime: s.startTime } : { running: false };
  }
  return out;
}

module.exports = { startSession, stopSession, getAllStatus };

CPEOF012

RUN cat > /app/backend/server.js << 'CPEOF013'
const express = require('express');
const { execSync } = require('child_process');
const fs = require('fs');
const crypto = require('crypto');
const sessionManager = require('./sessionManager');
const app = express();
app.use(express.json());
const TOKENS = new Set();
const PASSWORD = process.env.CLOUDPLAY_PASSWORD || 'cloudplay';
function auth(req,res,next){
  const h=req.headers.authorization;
  if(!h?.startsWith('Bearer ')||!TOKENS.has(h.split(' ')[1]))
    return res.status(401).json({error:'Unauthorized'});
  next();
}
app.post('/api/auth/login',(req,res)=>{
  if(req.body.password!==PASSWORD)
    return res.status(401).json({success:false,error:'Невiрний пароль'});
  const token=crypto.randomUUID();
  TOKENS.add(token);
  setTimeout(()=>TOKENS.delete(token),86400000);
  res.json({success:true,token});
});
app.post('/api/sessions/start/:type',auth,async(req,res)=>{
  const{type}=req.params;
  if(!['browser','desktop','phone'].includes(type))
    return res.status(400).json({success:false,error:'Bad type'});
  try{
    await sessionManager.startSession(type);
    res.json({success:true,
      vncUrl:`/novnc/vnc.html?path=websockify/${type}&autoconnect=true&reconnect=true`});
  }catch(err){res.status(500).json({success:false,error:err.message});}
});
app.post('/api/sessions/stop/:type',auth,async(req,res)=>{
  await sessionManager.stopSession(req.params.type);
  res.json({success:true});
});
app.get('/api/sessions/status',auth,(req,res)=>res.json(sessionManager.getAllStatus()));
app.get('/api/stats',auth,(req,res)=>{
  try{
    const mem=fs.readFileSync('/proc/meminfo','utf8');
    const total=parseInt(mem.match(/MemTotal:\s+(\d+)/)?.[1]||'0')/1024;
    const avail=parseInt(mem.match(/MemAvailable:\s+(\d+)/)?.[1]||'0')/1024;
    res.json({memory:{total:Math.round(total),used:Math.round(total-avail)},
      uptime:Math.floor(process.uptime()),sessions:sessionManager.getAllStatus()});
  }catch{res.json({memory:{total:0,used:0},uptime:0,sessions:{}});}
});
app.get('/api/health',(req,res)=>res.json({status:'ok',version:'1.2'}));
app.listen(3001,'127.0.0.1',()=>console.log('CloudPlay v1.2 :3001'));

CPEOF013

RUN cat > /app/nginx.conf << 'CPEOF014'
worker_processes 1;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;
events { worker_connections 512; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on; keepalive_timeout 65;
  gzip on; gzip_types text/plain text/css application/javascript application/json;
  server {
    listen 8080; server_name _;
    location /novnc/ { alias /opt/novnc/; try_files $uri $uri/ =404; }
    location /websockify/browser {
      proxy_pass http://127.0.0.1:6901;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_read_timeout 3600s;
    }
    location /websockify/desktop {
      proxy_pass http://127.0.0.1:6902;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_read_timeout 3600s;
    }
    location /websockify/phone {
      proxy_pass http://127.0.0.1:6903;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_read_timeout 3600s;
    }
    location /api/ {
      proxy_pass http://127.0.0.1:3001;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_read_timeout 120s;
    }
    location / {
      root /app/frontend/dist;
      try_files $uri $uri/ /index.html;
    }
  }
}

CPEOF014

RUN cat > /app/supervisord.conf << 'CPEOF015'
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
loglevel=info
user=root
[program:nginx]
command=/usr/sbin/nginx -g "daemon off;" -c /app/nginx.conf
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx.err.log
[program:backend]
command=node /app/backend/server.js
directory=/app/backend
autostart=true
autorestart=true
priority=20
environment=NODE_ENV="production",API_PORT="3001",CLOUDPLAY_PASSWORD="%(ENV_CLOUDPLAY_PASSWORD)s"
stdout_logfile=/var/log/supervisor/backend.log
stderr_logfile=/var/log/supervisor/backend.err.log

CPEOF015

# Залежності backend
RUN cd /app/backend && npm install --production

# Залежності + білд frontend
RUN cd /app/frontend && npm install && npm run build

EXPOSE 8080
CMD ["/usr/bin/supervisord", "-n", "-c", "/app/supervisord.conf"]
