FROM ubuntu:22.04
LABEL maintainer="CloudPlay v1.3"
ENV DEBIAN_FRONTEND=noninteractive TZ=UTC LANG=C.UTF-8 CLOUDPLAY_PASSWORD=cloudplay

# Пакети (БЕЗ chromium-browser — це snap-обгортка, не працює в Docker)
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc xauth dbus-x11 \
    mate-desktop-environment arc-theme papirus-icon-theme \
    openbox imagemagick bzip2 \
    python3 python3-pip \
    wget curl unzip supervisor nginx \
    net-tools procps fonts-liberation fontconfig libfontconfig1 \
    libdbus-glib-1-2 libgtk-3-0 libxt6 \
    && pip3 install --no-cache-dir websockify \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Firefox — пряме завантаження з Mozilla (не snap!)
RUN wget -q "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=en-US" \
    -O /tmp/ff.tar.bz2 \
    && tar xjf /tmp/ff.tar.bz2 -C /opt/ \
    && rm /tmp/ff.tar.bz2 \
    && /opt/firefox/firefox --version || true

RUN mkdir -p /opt/novnc \
    && wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
       | tar xz --strip-components=1 -C /opt/novnc \
    && ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

RUN mkdir -p /app/frontend/src/components /app/backend \
    && mkdir -p /var/log/supervisor /var/log/nginx /run/nginx /tmp/xdg \
    && mkdir -p /root/.config/openbox \
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
    desc:'Chromium у хмарі. Повний браузер без навантаження на девайс.',
    accent:'#4f46e5', gradient:'linear-gradient(135deg,#4f46e5,#7c3aed)', glow:'rgba(79,70,229,0.6)' },
  { id:'desktop', label:'Cloud PC', icon:'🖥️',
    desc:'Ubuntu GNOME. Сучасний робочий стіл у браузері.',
    accent:'#0ea5e9', gradient:'linear-gradient(135deg,#0ea5e9,#6366f1)', glow:'rgba(14,165,233,0.6)' },
  { id:'phone', label:'Cloud Phone', icon:'📱',
    desc:'Android-браузер з мобільним UA. Сайти як на телефоні.',
    accent:'#10b981', gradient:'linear-gradient(135deg,#10b981,#0891b2)', glow:'rgba(16,185,129,0.6)' },
];

export default function Dashboard({ onStart, onLogout, toast }) {
  const [loading, setLoading]   = useState(null);
  const [statuses, setStatuses] = useState({});
  const [time, setTime]         = useState(new Date());

  useEffect(()=>{
    const poll=async()=>{
      try{
        const r=await fetch('/api/sessions/status',{
          headers:{'Authorization':`Bearer ${localStorage.getItem('cp_token')}`}
        });
        setStatuses(await r.json());
      }catch{}
    };
    poll(); const id=setInterval(poll,5000); return()=>clearInterval(id);
  },[]);

  useEffect(()=>{ const id=setInterval(()=>setTime(new Date()),1000); return()=>clearInterval(id); },[]);

  const handleStart=async(sv)=>{
    setLoading(sv.id);
    try{ await onStart(sv.id); }
    catch(e){ toast(e.message,'error'); }
    finally{ setLoading(null); }
  };

  const handleStop=async(type)=>{
    await fetch(`/api/sessions/stop/${type}`,{
      method:'POST',headers:{'Authorization':`Bearer ${localStorage.getItem('cp_token')}`}
    });
    setStatuses(s=>({...s,[type]:{running:false}}));
    toast('Сесію зупинено','info');
  };

  const fmt=d=>d.toLocaleTimeString('uk-UA',{hour:'2-digit',minute:'2-digit'});
  const fmtDate=d=>d.toLocaleDateString('uk-UA',{weekday:'short',day:'numeric',month:'short'});
  const activeCount=Object.values(statuses).filter(s=>s?.running).length;

  return (
    <div style={s.root}>
      <Mesh />

      {/* Header */}
      <header style={s.header}>
        <div style={s.logoRow}>
          <span style={s.bolt}>⚡</span>
          <span style={s.brand}>CloudPlay</span>
          <span style={s.ver}>v1.3</span>
        </div>
        <div style={s.headerCenter}>
          <StatsBar statuses={statuses}/>
        </div>
        <div style={s.headerRight}>
          <div style={s.clock}>
            <div style={s.clockTime}>{fmt(time)}</div>
            <div style={s.clockDate}>{fmtDate(time)}</div>
          </div>
          <button style={s.logout} onClick={onLogout} title="Вийти">⏻</button>
        </div>
      </header>

      {/* Hero */}
      <main style={s.main}>
        <div style={s.hero}>
          <div style={s.heroBadge}>
            <span style={{...s.heroDot, background: activeCount>0?'#10b981':'#4f46e5',
              boxShadow:`0 0 8px ${activeCount>0?'#10b981':'#4f46e5'}`}}/>
            {activeCount>0 ? `${activeCount} активних сесій` : 'Готовий до роботи'}
          </div>
          <h1 style={s.title}>
            Твоя хмара,<br/>
            <span style={s.grad}>твої правила</span>
          </h1>
          <p style={s.sub}>Браузер, Linux та Android — все в одному місці.</p>
        </div>

        <div style={s.grid}>
          {SERVICES.map(sv=>(
            <ServiceCard key={sv.id} service={sv}
              status={statuses[sv.id]}
              loading={loading===sv.id}
              onStart={()=>handleStart(sv)}
              onReconnect={()=>onStart(sv.id).catch(()=>{})}
              onStop={()=>handleStop(sv.id)}
            />
          ))}
        </div>

        <div style={s.footer}>
          <span style={s.footTxt}>CloudPlay v1.3</span>
          <span style={s.footDivider}>·</span>
          <span style={s.footTxt}>Особистий сервер</span>
          <span style={s.footDivider}>·</span>
          <span style={s.footTxt}>2-3 користувачі</span>
        </div>
      </main>

      <style>{`
        @keyframes m1{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(80px,-60px)scale(1.15)}}
        @keyframes m2{0%,100%{transform:translate(0,0)scale(1)}50%{transform:translate(-60px,80px)scale(1.1)}}
        @keyframes m3{0%,100%{transform:translate(-50%,-50%)scale(1)}50%{transform:translate(-50%,-50%)scale(1.2)}}
        @keyframes m4{0%,100%{transform:translate(0,0)}50%{transform:translate(40px,50px)}}
        @keyframes gS{0%,100%{background-position:0% 50%}50%{background-position:100% 50%}}
        @keyframes fU{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:none}}
      `}</style>
    </div>
  );
}

function Mesh(){
  return(
    <div style={{position:'fixed',inset:0,pointerEvents:'none',overflow:'hidden',zIndex:0}}>
      <div style={{position:'absolute',width:900,height:900,borderRadius:'50%',
        background:'radial-gradient(circle,#4f46e5 0%,transparent 70%)',
        opacity:.12,top:-400,right:-200,filter:'blur(60px)',animation:'m1 12s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:800,height:800,borderRadius:'50%',
        background:'radial-gradient(circle,#7c3aed 0%,transparent 70%)',
        opacity:.1,bottom:-300,left:-200,filter:'blur(60px)',animation:'m2 15s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:600,height:600,borderRadius:'50%',
        background:'radial-gradient(circle,#0ea5e9 0%,transparent 70%)',
        opacity:.08,top:'50%',left:'50%',filter:'blur(80px)',animation:'m3 10s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:400,height:400,borderRadius:'50%',
        background:'radial-gradient(circle,#10b981 0%,transparent 70%)',
        opacity:.07,bottom:100,right:100,filter:'blur(60px)',animation:'m4 13s ease-in-out infinite'}}/>
      {/* Grid lines */}
      <div style={{position:'absolute',inset:0,
        backgroundImage:'linear-gradient(rgba(255,255,255,0.03) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,0.03) 1px,transparent 1px)',
        backgroundSize:'60px 60px'}}/>
    </div>
  );
}

const s={
  root:{minHeight:'100vh',background:'#030308',fontFamily:"'Space Grotesk',sans-serif",color:'#fff',position:'relative',overflow:'hidden'},
  header:{position:'relative',zIndex:10,display:'flex',alignItems:'center',gap:16,padding:'14px 32px',
    borderBottom:'1px solid rgba(255,255,255,0.06)',backdropFilter:'blur(20px)',
    background:'rgba(3,3,8,0.7)'},
  logoRow:{display:'flex',alignItems:'center',gap:8,flexShrink:0},
  bolt:{fontSize:24,filter:'drop-shadow(0 0 12px rgba(255,200,0,.8))'},
  brand:{fontSize:19,fontWeight:700,letterSpacing:'-.5px',color:'#fff'},
  ver:{fontSize:10,color:'rgba(255,255,255,.3)',border:'1px solid rgba(255,255,255,.1)',
    padding:'2px 7px',borderRadius:5,fontFamily:"'Inter',sans-serif",letterSpacing:'.5px'},
  headerCenter:{flex:1,display:'flex',justifyContent:'center'},
  headerRight:{display:'flex',alignItems:'center',gap:12,flexShrink:0},
  clock:{textAlign:'right'},
  clockTime:{fontSize:16,fontWeight:700,letterSpacing:'.5px',lineHeight:1.2,
    fontVariantNumeric:'tabular-nums'},
  clockDate:{fontSize:11,color:'rgba(255,255,255,.3)',fontFamily:"'Inter',sans-serif"},
  logout:{background:'rgba(255,255,255,.06)',border:'1px solid rgba(255,255,255,.1)',
    color:'rgba(255,255,255,.5)',width:34,height:34,borderRadius:8,cursor:'pointer',fontSize:15},
  main:{position:'relative',zIndex:10,maxWidth:1100,margin:'0 auto',padding:'56px 32px 48px'},
  hero:{marginBottom:48,animation:'fU .5s ease'},
  heroBadge:{display:'inline-flex',alignItems:'center',gap:8,fontSize:12,
    color:'rgba(255,255,255,.5)',fontFamily:"'Inter',sans-serif",
    background:'rgba(255,255,255,.06)',border:'1px solid rgba(255,255,255,.1)',
    padding:'6px 14px',borderRadius:20,marginBottom:20},
  heroDot:{width:7,height:7,borderRadius:'50%',display:'inline-block'},
  title:{fontSize:'clamp(32px,5.5vw,62px)',fontWeight:700,lineHeight:1.1,
    letterSpacing:'-2px',marginBottom:14,margin:'0 0 14px'},
  grad:{background:'linear-gradient(135deg,#818cf8 0%,#a78bfa 40%,#34d399 100%)',
    backgroundSize:'200% 200%',WebkitBackgroundClip:'text',WebkitTextFillColor:'transparent',
    animation:'gS 5s ease infinite'},
  sub:{fontSize:16,lineHeight:1.6,color:'rgba(255,255,255,.38)',
    fontFamily:"'Inter',sans-serif",marginTop:6},
  grid:{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(300px,1fr))',gap:16,marginBottom:36},
  footer:{display:'flex',alignItems:'center',gap:10},
  footTxt:{fontSize:11,color:'rgba(255,255,255,.15)',fontFamily:"'Inter',sans-serif"},
  footDivider:{color:'rgba(255,255,255,.1)',fontSize:11},
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
import { useState, useEffect, useCallback, useRef } from 'react';

const META = {
  browser: { icon:'🌐', name:'Cloud Browser', sub:'Chromium', boot:25 },
  desktop: { icon:'🖥️', name:'Cloud PC',      sub:'Ubuntu XFCE', boot:35 },
  phone:   { icon:'📱', name:'Cloud Phone',   sub:'Android 11', boot:20 },
};

async function adbKey(keycode){
  try{ await fetch('/api/adb/keyevent',{method:'POST',
    headers:{'Content-Type':'application/json'},body:JSON.stringify({keycode})}); }catch{}
}

export default function SessionViewer({ type, url, onBack }){
  const [loaded, setLoaded]     = useState(false);
  const [countdown, setCountdown] = useState(META[type]?.boot || 25);
  const [retries, setRetries]   = useState(0);
  const iframeRef               = useRef(null);
  const meta                    = META[type] || META.browser;

  // Countdown timer
  useEffect(()=>{
    if(loaded) return;
    const id = setInterval(()=>{
      setCountdown(c=> c > 0 ? c-1 : 0);
    },1000);
    return ()=>clearInterval(id);
  },[loaded]);

  const handleLoad = useCallback(()=> setLoaded(true),[]);

  const handleRetry = ()=>{
    setLoaded(false);
    setCountdown(META[type]?.boot || 25);
    setRetries(r=>r+1);
    if(iframeRef.current){
      const src = iframeRef.current.src;
      iframeRef.current.src = '';
      setTimeout(()=>{ if(iframeRef.current) iframeRef.current.src = src; },300);
    }
  };

  const openFullscreen = ()=>{
    if(iframeRef.current?.requestFullscreen) iframeRef.current.requestFullscreen();
    else if(url) window.open(url,'_blank');
  };

  // noVNC URL з кращими параметрами
  const vncUrl = url
    ? `${url}&resize=scale&quality=6&compression=2&reconnect_delay=3000&bell=0`
    : null;

  return (
    <div style={s.root}>
      {/* Toolbar */}
      <div style={s.bar}>
        <button style={s.backBtn} onClick={onBack}>← Назад</button>
        <div style={s.info}>
          <span style={{fontSize:20}}>{meta.icon}</span>
          <div>
            <div style={s.name}>{meta.name}</div>
            <div style={s.sub}>{meta.sub}</div>
          </div>
        </div>
        <div style={{...s.status, color: loaded?'#10b981':'#f59e0b'}}>
          <span style={{...s.dot, background:loaded?'#10b981':'#f59e0b',
            boxShadow:`0 0 6px ${loaded?'#10b981':'#f59e0b'}`}}/>
          {loaded ? 'Активна' : 'Запуск...'}
        </div>
        <button style={s.iconBtn} onClick={handleRetry} title="Перезапустити">↺</button>
        <button style={s.iconBtn} onClick={openFullscreen} title="Повний екран">⛶</button>
      </div>

      {/* Content */}
      <div style={s.content}>
        {/* Loading overlay */}
        {!loaded && (
          <div style={s.overlay}>
            <div style={s.card}>
              <div style={{fontSize:52}}>{meta.icon}</div>
              <div style={s.spinner}/>
              <p style={s.loadTitle}>Запускаємо {meta.name}...</p>
              {countdown > 0 ? (
                <div style={s.countWrap}>
                  <div style={s.countNum}>{countdown}</div>
                  <div style={s.countLabel}>секунд</div>
                </div>
              ) : (
                <p style={s.countLabel}>Майже готово...</p>
              )}
              <div style={s.progressBar}>
                <div style={{
                  ...s.progressFill,
                  width: `${Math.max(5, 100 - (countdown/(meta.boot||25))*100)}%`,
                }}/>
              </div>
              <p style={s.hint}>
                {retries === 0
                  ? 'Якщо екран чорний після завантаження — натисни ↺ вгорі'
                  : `Спроба ${retries+1}...`}
              </p>
              <button style={s.retryBtn} onClick={handleRetry}>
                ↺ Перезапустити з'єднання
              </button>
            </div>
          </div>
        )}

        {/* noVNC iframe */}
        {vncUrl && (
          <iframe
            ref={iframeRef}
            key={retries}
            src={vncUrl}
            style={{...s.frame, opacity: loaded ? 1 : 0}}
            onLoad={handleLoad}
            allow="clipboard-read; clipboard-write; fullscreen"
            title={meta.name}
          />
        )}
      </div>

      <style>{`
        @keyframes spin{to{transform:rotate(360deg)}}
        @keyframes pulse{0%,100%{opacity:1}50%{opacity:.5}}
        @keyframes fadeIn{from{opacity:0;transform:scale(.97)}to{opacity:1;transform:none}}
      `}</style>
    </div>
  );
}

const s = {
  root:{ display:'flex', flexDirection:'column', height:'100vh',
    background:'#030308', fontFamily:"'Space Grotesk',sans-serif", color:'#fff' },
  bar:{ display:'flex', alignItems:'center', gap:10, padding:'10px 16px',
    background:'rgba(255,255,255,.04)', borderBottom:'1px solid rgba(255,255,255,.07)',
    flexShrink:0 },
  backBtn:{ background:'rgba(255,255,255,.07)', border:'1px solid rgba(255,255,255,.1)',
    color:'#fff', padding:'7px 14px', borderRadius:8, cursor:'pointer',
    fontSize:13, fontFamily:"'Space Grotesk',sans-serif", flexShrink:0 },
  info:{ flex:1, display:'flex', alignItems:'center', gap:10 },
  name:{ fontSize:14, fontWeight:600 },
  sub:{ fontSize:11, color:'rgba(255,255,255,.35)', fontFamily:"'Inter',sans-serif" },
  status:{ display:'flex', alignItems:'center', gap:6, fontSize:12,
    fontFamily:"'Inter',sans-serif", flexShrink:0 },
  dot:{ display:'inline-block', width:8, height:8, borderRadius:'50%' },
  iconBtn:{ background:'rgba(255,255,255,.07)', border:'1px solid rgba(255,255,255,.1)',
    color:'#fff', width:34, height:34, borderRadius:8, cursor:'pointer', fontSize:15,
    display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0 },
  content:{ flex:1, position:'relative', overflow:'hidden' },
  overlay:{ position:'absolute', inset:0, zIndex:10, background:'#030308',
    display:'flex', alignItems:'center', justifyContent:'center' },
  card:{ display:'flex', flexDirection:'column', alignItems:'center', gap:16,
    padding:'40px 32px', background:'rgba(255,255,255,.04)',
    border:'1px solid rgba(255,255,255,.09)', borderRadius:24,
    animation:'fadeIn .4s ease', maxWidth:320, width:'90%', textAlign:'center' },
  spinner:{ width:44, height:44, border:'3px solid rgba(255,255,255,.08)',
    borderTopColor:'#818cf8', borderRadius:'50%', animation:'spin .9s linear infinite' },
  loadTitle:{ fontSize:17, fontWeight:600, color:'rgba(255,255,255,.85)' },
  countWrap:{ display:'flex', flexDirection:'column', alignItems:'center', gap:4 },
  countNum:{ fontSize:48, fontWeight:700, color:'#818cf8', lineHeight:1,
    fontVariantNumeric:'tabular-nums' },
  countLabel:{ fontSize:12, color:'rgba(255,255,255,.35)',
    fontFamily:"'Inter',sans-serif" },
  progressBar:{ width:'100%', height:4, background:'rgba(255,255,255,.08)',
    borderRadius:2, overflow:'hidden' },
  progressFill:{ height:'100%',
    background:'linear-gradient(90deg,#4f46e5,#818cf8)',
    borderRadius:2, transition:'width 1s linear' },
  hint:{ fontSize:12, color:'rgba(255,255,255,.3)',
    fontFamily:"'Inter',sans-serif", lineHeight:1.5 },
  retryBtn:{ background:'rgba(129,140,248,.15)', border:'1px solid rgba(129,140,248,.3)',
    color:'#818cf8', padding:'9px 20px', borderRadius:10, cursor:'pointer',
    fontSize:13, fontWeight:600, fontFamily:"'Space Grotesk',sans-serif" },
  frame:{ position:'absolute', inset:0, width:'100%', height:'100%',
    border:'none', transition:'opacity .5s ease' },
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
const { spawn } = require('child_process');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');

const CONFIGS = {
  browser: { display:':1', vncPort:5901, wsPort:6901, res:'1920x1080x24' },
  desktop: { display:':2', vncPort:5902, wsPort:6902, res:'1920x1080x24' },
  phone:   { display:':3', vncPort:5903, wsPort:6903, res:'412x915x24'   },
};
const sessions = { browser:null, desktop:null, phone:null };

const FF = '/opt/firefox/firefox';
function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }
function sp(cmd,args,env={}){
  const p=spawn(cmd,args,{env:{...process.env,...env},stdio:'ignore',detached:false});
  p.on('error',e=>console.error(`[${cmd}]:`,e.message));
  return p;
}

async function startSession(type){
  if(sessions[type]) await stopSession(type);
  const cfg=CONFIGS[type];
  const procs={};
  console.log(`▶ [${type}]...`);

  procs.xvfb=sp('Xvfb',[cfg.display,'-screen','0',cfg.res,
    '-ac','-nolisten','tcp','-noreset','-dpi','96']);
  await sleep(1500);

  if(type==='browser'){
    // Firefox — працює без snap, рендерить нормально
    procs.wm=sp('openbox',[],{DISPLAY:cfg.display,HOME:'/root'});
    await sleep(600);
    procs.app=sp(FF,[
      '--no-remote','--new-instance',
      '-url','https://www.google.com',
    ],{
      DISPLAY:cfg.display, HOME:'/root',
      MOZ_DISABLE_CONTENT_SANDBOX:'1',
      MOZ_ENABLE_WAYLAND:'0',
    });

  } else if(type==='desktop'){
    // MATE Desktop + Firefox
    fs.mkdirSync('/tmp/xdg',{recursive:true});
    fs.mkdirSync('/root/.config',{recursive:true});
    try{ require('child_process').execSync(
      'convert -size 1920x1080 gradient:"#0d1117-#1c2333" /tmp/wp.png',
      {timeout:5000}); }catch{}

    procs.dbus=sp('bash',['-c',
      'mkdir -p /run/dbus && dbus-daemon --system --fork 2>/dev/null; true'],{});
    await sleep(700);

    procs.wm=sp('bash',['-c',`
      export DISPLAY=${cfg.display}
      export HOME=/root
      export XDG_RUNTIME_DIR=/tmp/xdg
      export DBUS_SESSION_BUS_ADDRESS=autolaunch:
      (sleep 5
       gsettings set org.mate.interface gtk-theme 'Arc-Dark' 2>/dev/null
       gsettings set org.mate.interface icon-theme 'Papirus-Dark' 2>/dev/null
       gsettings set org.mate.Marco.general theme 'Arc-Dark' 2>/dev/null
       gsettings set org.mate.screensaver lock-enabled false 2>/dev/null
       [ -f /tmp/wp.png ] && gsettings set org.mate.background picture-filename '/tmp/wp.png' 2>/dev/null
       gsettings set org.mate.background picture-options 'stretched' 2>/dev/null
      )&
      dbus-run-session -- mate-session 2>/tmp/mate.log
    `],{DISPLAY:cfg.display,HOME:'/root',XDG_RUNTIME_DIR:'/tmp/xdg',
       MOZ_ENABLE_WAYLAND:'0'});

  } else if(type==='phone'){
    // Власний Android UI в Firefox (кіоск)
    procs.wm=sp('openbox',[],{DISPLAY:cfg.display,HOME:'/root'});
    await sleep(700);
    procs.app=sp(FF,[
      '--no-remote','--new-instance','--kiosk',
      'file:///app/backend/android.html',
    ],{
      DISPLAY:cfg.display, HOME:'/root',
      MOZ_DISABLE_CONTENT_SANDBOX:'1',
      MOZ_ENABLE_WAYLAND:'0',
    });
  }

  await sleep(type==='desktop'?5000:4000);

  procs.vnc=sp('x11vnc',[
    '-display',cfg.display,'-forever','-nopw','-quiet','-shared',
    '-rfbport',String(cfg.vncPort),'-wait','20','-defer','10',
  ]);
  await sleep(1200);

  procs.ws=sp('websockify',[String(cfg.wsPort),`localhost:${cfg.vncPort}`]);
  await sleep(500);

  sessions[type]={id:uuidv4(),type,procs,startTime:new Date()};
  console.log(`✅ [${type}] ready`);
  return sessions[type];
}

async function stopSession(type){
  const s=sessions[type]; if(!s)return;
  for(const p of Object.values(s.procs).reverse())
    try{if(p&&!p.killed)p.kill('SIGTERM');}catch{}
  sessions[type]=null;
}

function getAllStatus(){
  const o={};
  for(const[t,s]of Object.entries(sessions))
    o[t]=s?{running:true,id:s.id,startTime:s.startTime}:{running:false};
  return o;
}
module.exports={startSession,stopSession,getAllStatus};

CPEOF012

RUN cat > /app/backend/server.js << 'CPEOF013'
const express = require('express');
const { execSync } = require('child_process');
const sessionManager = require('./sessionManager');

const app = express();
app.use(express.json());

// ── Sessions ─────────────────────────────────────────────────────

app.post('/api/sessions/start/:type', async (req, res) => {
  const { type } = req.params;
  if (!['browser', 'desktop', 'phone'].includes(type)) {
    return res.status(400).json({ success: false, error: 'Невідомий тип' });
  }
  try {
    await sessionManager.startSession(type);
    res.json({
      success: true,
      vncUrl: `/novnc/vnc.html?path=websockify/${type}&autoconnect=true&reconnect=true`,
    });
  } catch (err) {
    console.error(`Start [${type}] failed:`, err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/sessions/stop/:type', async (req, res) => {
  await sessionManager.stopSession(req.params.type);
  res.json({ success: true });
});

app.get('/api/sessions/status', (req, res) => {
  res.json(sessionManager.getAllStatus());
});

// ── ADB Controls (для телефону) ───────────────────────────────────

// Допустимі keycodes: Back=4, Home=3, Recents=187, Vol+=24, Vol-=25, Power=26
const ALLOWED_KEYS = new Set([3, 4, 24, 25, 26, 187]);

app.post('/api/adb/keyevent', (req, res) => {
  const code = Number(req.body.keycode);
  if (!ALLOWED_KEYS.has(code)) {
    return res.status(400).json({ error: 'Invalid keycode' });
  }
  try {
    execSync(`${process.env.ANDROID_SDK_ROOT || '/opt/android-sdk'}/platform-tools/adb shell input keyevent ${code}`, { timeout: 3000 });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'ADB недоступний або емулятор ще завантажується' });
  }
});

app.post('/api/adb/rotate', (req, res) => {
  const orientation = Number(req.body.orientation); // 0=portrait, 1=landscape
  if (orientation !== 0 && orientation !== 1) {
    return res.status(400).json({ error: 'Invalid orientation' });
  }
  const adb = `${process.env.ANDROID_SDK_ROOT || '/opt/android-sdk'}/platform-tools/adb`;
  try {
    execSync(`${adb} shell settings put system accelerometer_rotation 0`, { timeout: 3000 });
    execSync(`${adb} shell settings put system user_rotation ${orientation}`, { timeout: 3000 });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'ADB rotate failed' });
  }
});

app.post('/api/adb/swipe', (req, res) => {
  const { x1, y1, x2, y2, duration = 300 } = req.body;
  const adb = `${process.env.ANDROID_SDK_ROOT || '/opt/android-sdk'}/platform-tools/adb`;
  try {
    execSync(`${adb} shell input swipe ${x1} ${y1} ${x2} ${y2} ${duration}`, { timeout: 3000 });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Swipe failed' });
  }
});

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// ── Start ────────────────────────────────────────────────────────
const PORT = process.env.API_PORT || 3001;
app.listen(PORT, '127.0.0.1', () => {
  console.log(`🚀 API на 127.0.0.1:${PORT}`);
});

CPEOF013

RUN cat > /app/backend/android.html << 'CPEOF014'
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=412,initial-scale=1">
<title>CloudPlay Phone</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{width:412px;height:915px;overflow:hidden;font-family:'Segoe UI',Roboto,sans-serif;background:#000;user-select:none}

/* WALLPAPER */
.wp{position:absolute;inset:0;background:linear-gradient(160deg,#0a0a1e 0%,#1a0533 40%,#0d1f3c 100%)}
.wp::after{content:'';position:absolute;inset:0;
  background:radial-gradient(ellipse at 30% 60%,rgba(99,102,241,.25) 0%,transparent 60%),
             radial-gradient(ellipse at 80% 20%,rgba(139,92,246,.2) 0%,transparent 50%)}

/* STATUS BAR */
.sb{position:absolute;top:0;left:0;right:0;height:28px;z-index:100;
  padding:0 16px;display:flex;align-items:center;justify-content:space-between}
.sb-time{font-size:13px;font-weight:700;color:#fff}
.sb-icons{display:flex;gap:5px;align-items:center;font-size:12px;color:#fff}

/* DATE WIDGET */
.date-widget{position:absolute;top:38px;left:0;right:0;text-align:center;z-index:10}
.date-time{font-size:52px;font-weight:200;color:#fff;letter-spacing:-2px;line-height:1}
.date-sub{font-size:14px;color:rgba(255,255,255,.6);margin-top:4px;font-weight:400}

/* NOTIFICATION PILL */
.notif{position:absolute;top:140px;left:20px;right:20px;z-index:10;
  background:rgba(255,255,255,.1);backdrop-filter:blur(20px);
  border:1px solid rgba(255,255,255,.15);border-radius:20px;padding:12px 16px;
  display:flex;align-items:center;gap:12px;cursor:pointer}
.notif-icon{font-size:20px}
.notif-text{flex:1}
.notif-app{font-size:11px;color:rgba(255,255,255,.5);font-weight:600;text-transform:uppercase;letter-spacing:.5px}
.notif-msg{font-size:13px;color:#fff;margin-top:2px}
.notif-time{font-size:11px;color:rgba(255,255,255,.4)}

/* APP GRID */
.apps{position:absolute;top:220px;left:0;right:0;padding:0 16px;
  display:grid;grid-template-columns:repeat(4,1fr);gap:16px 8px;z-index:10}
.app{display:flex;flex-direction:column;align-items:center;gap:5px;cursor:pointer;padding:6px 4px;border-radius:16px;transition:background .15s}
.app:active{background:rgba(255,255,255,.1)}
.app-i{width:58px;height:58px;border-radius:16px;display:flex;align-items:center;justify-content:center;
  font-size:28px;box-shadow:0 4px 20px rgba(0,0,0,.4);flex-shrink:0}
.app-l{font-size:11px;color:rgba(255,255,255,.9);text-shadow:0 1px 6px rgba(0,0,0,.8);font-weight:500;text-align:center}

/* DOCK */
.dock{position:absolute;bottom:28px;left:16px;right:16px;z-index:10;
  background:rgba(255,255,255,.12);backdrop-filter:blur(30px);
  border:1px solid rgba(255,255,255,.15);border-radius:28px;
  padding:10px 20px;display:flex;justify-content:space-around;align-items:center}

/* GESTURE BAR */
.gesture{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);
  width:100px;height:4px;background:rgba(255,255,255,.35);border-radius:2px;z-index:200}

/* BROWSER */
.browser{position:absolute;inset:0;z-index:300;display:none;flex-direction:column;background:#1a1a2e}
.browser.on{display:flex}
.brow-bar{background:#111827;padding:8px 10px;display:flex;align-items:center;gap:8px;flex-shrink:0;
  border-bottom:1px solid rgba(255,255,255,.08)}
.brow-btn{background:none;border:none;color:#9ca3af;font-size:18px;cursor:pointer;padding:4px 6px;
  border-radius:6px;display:flex;align-items:center;justify-content:center}
.brow-btn:active{background:rgba(255,255,255,.1)}
.brow-url{flex:1;padding:8px 14px;border-radius:20px;background:rgba(255,255,255,.08);
  color:#fff;border:1px solid rgba(255,255,255,.12);font-size:13px;outline:none;font-family:inherit}
.brow-tabs{display:flex;background:#111827;border-bottom:1px solid rgba(255,255,255,.06);overflow-x:auto;flex-shrink:0}
.tab{padding:8px 14px;font-size:12px;color:rgba(255,255,255,.5);white-space:nowrap;cursor:pointer;
  border-bottom:2px solid transparent;display:flex;align-items:center;gap:6px}
.tab.active{color:#818cf8;border-bottom-color:#818cf8;background:rgba(129,140,248,.1)}
.tab-close{font-size:14px;color:rgba(255,255,255,.3);margin-left:4px}
.brow-frame{flex:1;border:none;background:#fff}
.brow-navbar{background:#111827;padding:8px 20px;display:flex;justify-content:space-around;
  border-top:1px solid rgba(255,255,255,.06);flex-shrink:0}

@keyframes slideUp{from{transform:translateY(100%);opacity:0}to{transform:none;opacity:1}}
.browser.on{animation:slideUp .25s ease}
</style>
</head>
<body>
<div class="wp"></div>

<div class="sb">
  <span class="sb-time" id="st">00:00</span>
  <div class="sb-icons">
    <span>▲▲▲</span>
    <span>🔋</span>
  </div>
</div>

<div class="date-widget">
  <div class="date-time" id="dt">00:00</div>
  <div class="date-sub" id="ds">Субота, 14 червня</div>
</div>

<div class="notif" onclick="openApp('https://web.telegram.org')">
  <div class="notif-icon">✈️</div>
  <div class="notif-text">
    <div class="notif-app">Telegram</div>
    <div class="notif-msg">CloudPlay запущено! 🚀</div>
  </div>
  <div class="notif-time">зараз</div>
</div>

<div class="apps" id="apps">
  <div class="app" onclick="openApp('https://www.google.com')">
    <div class="app-i" style="background:#fff">🌐</div><div class="app-l">Chrome</div></div>
  <div class="app" onclick="openApp('https://m.youtube.com')">
    <div class="app-i" style="background:#ff0000">▶️</div><div class="app-l">YouTube</div></div>
  <div class="app" onclick="openApp('https://web.telegram.org')">
    <div class="app-i" style="background:#2196F3">✈️</div><div class="app-l">Telegram</div></div>
  <div class="app" onclick="openApp('https://discord.com/app')">
    <div class="app-i" style="background:#5865F2">💬</div><div class="app-l">Discord</div></div>
  <div class="app" onclick="openApp('https://m.instagram.com')">
    <div class="app-i" style="background:linear-gradient(135deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888)">📸</div><div class="app-l">Instagram</div></div>
  <div class="app" onclick="openApp('https://www.tiktok.com')">
    <div class="app-i" style="background:#010101">🎵</div><div class="app-l">TikTok</div></div>
  <div class="app" onclick="openApp('https://maps.google.com')">
    <div class="app-i" style="background:#4CAF50">🗺️</div><div class="app-l">Maps</div></div>
  <div class="app" onclick="openApp('https://gmail.com')">
    <div class="app-i" style="background:#EA4335">📧</div><div class="app-l">Gmail</div></div>
  <div class="app" onclick="openApp('https://open.spotify.com')">
    <div class="app-i" style="background:#1DB954">🎧</div><div class="app-l">Spotify</div></div>
  <div class="app" onclick="openApp('https://www.netflix.com')">
    <div class="app-i" style="background:#E50914">🎬</div><div class="app-l">Netflix</div></div>
  <div class="app" onclick="openApp('https://twitter.com')">
    <div class="app-i" style="background:#000">✕</div><div class="app-l">X</div></div>
  <div class="app" onclick="openApp('https://reddit.com')">
    <div class="app-i" style="background:#FF4500">🤖</div><div class="app-l">Reddit</div></div>
</div>

<div class="dock">
  <div class="app" onclick="openApp('https://www.google.com')" style="margin:0">
    <div class="app-i" style="background:#fff;width:52px;height:52px">🌐</div></div>
  <div class="app" onclick="openApp('https://m.youtube.com')" style="margin:0">
    <div class="app-i" style="background:#ff0000;width:52px;height:52px">▶️</div></div>
  <div class="app" onclick="openApp('https://web.telegram.org')" style="margin:0">
    <div class="app-i" style="background:#2196F3;width:52px;height:52px">✈️</div></div>
  <div class="app" onclick="openApp('https://gmail.com')" style="margin:0">
    <div class="app-i" style="background:#EA4335;width:52px;height:52px">📧</div></div>
</div>

<div class="gesture"></div>

<!-- BROWSER -->
<div class="browser" id="br">
  <div class="brow-bar">
    <button class="brow-btn" onclick="closeBr()">✕</button>
    <input class="brow-url" id="url" type="text" placeholder="Пошук або адреса..."
      onkeydown="if(event.key==='Enter')go(this.value)">
    <button class="brow-btn" onclick="go(document.getElementById('url').value)">→</button>
  </div>
  <div class="brow-tabs" id="tabs"></div>
  <iframe class="brow-frame" id="frm" allow="*" sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-top-navigation"></iframe>
  <div class="brow-navbar">
    <button class="brow-btn" onclick="document.getElementById('frm').contentWindow.history.back()">←</button>
    <button class="brow-btn" onclick="document.getElementById('frm').contentWindow.history.forward()">→</button>
    <button class="brow-btn" onclick="document.getElementById('frm').src=document.getElementById('frm').src">↺</button>
    <button class="brow-btn" onclick="closeBr()">⌂</button>
  </div>
</div>

<script>
function clock(){
  const n=new Date();
  const h=n.getHours().toString().padStart(2,'0');
  const m=n.getMinutes().toString().padStart(2,'0');
  document.getElementById('st').textContent=h+':'+m;
  document.getElementById('dt').textContent=h+':'+m;
  const days=['Неділя','Понеділок','Вівторок','Середа','Четвер',"П'ятниця",'Субота'];
  const months=['січня','лютого','березня','квітня','травня','червня','липня','серпня','вересня','жовтня','листопада','грудня'];
  document.getElementById('ds').textContent=days[n.getDay()]+', '+n.getDate()+' '+months[n.getMonth()];
}
clock(); setInterval(clock,1000);

function openApp(url){
  document.getElementById('url').value=url;
  document.getElementById('frm').src=url;
  document.getElementById('br').classList.add('on');
}
function closeBr(){
  document.getElementById('br').classList.remove('on');
  document.getElementById('frm').src='';
}
function go(v){
  if(!v)return;
  if(!v.startsWith('http'))v='https://'+v;
  document.getElementById('url').value=v;
  document.getElementById('frm').src=v;
}
</script>
</body>
</html>

CPEOF014

RUN cat > /app/nginx.conf << 'CPEOF015'
worker_processes 1;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 512;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/javascript application/json;

    server {
        listen 8080;
        server_name _;

        # ── noVNC static client ────────────────────────────────
        location /novnc/ {
            alias /opt/novnc/;
            try_files $uri $uri/ =404;
        }

        # ── WebSocket proxy → websockify (browser) ─────────────
        location /websockify/browser {
            proxy_pass http://127.0.0.1:6901;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        # ── WebSocket proxy → websockify (desktop) ─────────────
        location /websockify/desktop {
            proxy_pass http://127.0.0.1:6902;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        # ── WebSocket proxy → websockify (phone) ───────────────
        location /websockify/phone {
            proxy_pass http://127.0.0.1:6903;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        # ── API → Node.js backend ──────────────────────────────
        location /api/ {
            proxy_pass http://127.0.0.1:3001;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 60s;
        }

        # ── React SPA ──────────────────────────────────────────
        location / {
            root /app/frontend/dist;
            try_files $uri $uri/ /index.html;
            expires 1h;
            add_header Cache-Control "public, no-transform";
        }
    }
}

CPEOF015

RUN cat > /app/supervisord.conf << 'CPEOF016'
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
startretries=5
priority=10
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx.err.log

[program:backend]
command=node /app/backend/server.js
directory=/app/backend
autostart=true
autorestart=true
startretries=10
priority=20
environment=NODE_ENV="production",API_PORT="3001"
stdout_logfile=/var/log/supervisor/backend.log
stderr_logfile=/var/log/supervisor/backend.err.log

CPEOF016

RUN cd /app/backend && npm install --production
RUN cd /app/frontend && npm install && npm run build

EXPOSE 8080
CMD ["/usr/bin/supervisord", "-n", "-c", "/app/supervisord.conf"]
