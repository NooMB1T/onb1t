FROM ubuntu:22.04
LABEL maintainer="CloudPlay v1.3"
ENV DEBIAN_FRONTEND=noninteractive TZ=UTC LANG=C.UTF-8 CLOUDPLAY_PASSWORD=cloudplay

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc xauth dbus-x11 xsetroot \
    openbox tint2 feh \
    thunar mousepad xterm \
    arc-theme papirus-icon-theme gtk2-engines-murrine \
    imagemagick bzip2 \
    libdbus-glib-1-2 libgtk-3-0 libxt6 libx11-xcb1 \
    python3 python3-pip \
    wget curl unzip supervisor nginx \
    net-tools procps fonts-liberation fontconfig libfontconfig1 \
    && pip3 install --no-cache-dir websockify \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Firefox — напряму з Mozilla, без snap
RUN wget -q "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=en-US" \
    -O /tmp/ff.tar.bz2 \
    && tar xjf /tmp/ff.tar.bz2 -C /opt/ \
    && rm /tmp/ff.tar.bz2 \
    && ln -sf /opt/firefox/firefox /usr/local/bin/firefox

RUN mkdir -p /opt/novnc \
    && wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
       | tar xz --strip-components=1 -C /opt/novnc \
    && ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

RUN mkdir -p /app/frontend/src/components /app/backend \
    && mkdir -p /var/log/supervisor /var/log/nginx /run/nginx /tmp/xdg \
    && mkdir -p /root/.config/openbox \
    && rm -f /etc/nginx/sites-enabled/default

# Налаштовуємо Openbox щоб читав правильні конфіги
RUN mkdir -p /root/.config/openbox
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

const SERVICES = [
  { id:'browser', icon:'🌐', label:'Cloud Browser',
    desc:'Firefox у хмарі. Повний інтернет, нічого не грузить твій пристрій.',
    accent:'#4f46e5', g:'linear-gradient(135deg,#4f46e5,#7c3aed)', glow:'#4f46e5' },
  { id:'desktop', icon:'🖥️', label:'Cloud PC',
    desc:'Повноцінний Linux ПК. Firefox, файли, термінал — все через браузер.',
    accent:'#0ea5e9', g:'linear-gradient(135deg,#0ea5e9,#2563eb)', glow:'#0ea5e9' },
  { id:'phone', icon:'📱', label:'Cloud Phone',
    desc:'Android-інтерфейс у хмарі. Соцмережі, ютуб, месенджери.',
    accent:'#10b981', g:'linear-gradient(135deg,#10b981,#059669)', glow:'#10b981' },
];

export default function Dashboard({ onStart, onLogout, toast }) {
  const [loading, setLoading]   = useState(null);
  const [statuses, setStatuses] = useState({});
  const [time, setTime]         = useState(new Date());
  const [hovered, setHovered]   = useState(null);

  useEffect(()=>{
    const poll=async()=>{
      try{
        const r=await fetch('/api/sessions/status',{
          headers:{'Authorization':`Bearer ${localStorage.getItem('cp_token')}`}});
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
    await fetch(`/api/sessions/stop/${type}`,{method:'POST',
      headers:{'Authorization':`Bearer ${localStorage.getItem('cp_token')}`}});
    setStatuses(s=>({...s,[type]:{running:false}}));
    toast('Сесію зупинено','info');
  };

  const pad=n=>String(n).padStart(2,'0');
  const timeStr=`${pad(time.getHours())}:${pad(time.getMinutes())}:${pad(time.getSeconds())}`;
  const dateStr=time.toLocaleDateString('uk-UA',{weekday:'long',day:'numeric',month:'long'});
  const active=Object.values(statuses).filter(s=>s?.running).length;

  return (
    <div style={s.root}>
      <BG />

      {/* TOP BAR */}
      <header style={s.topbar}>
        <div style={s.brand}>
          <span style={s.brandIcon}>⚡</span>
          <span style={s.brandName}>CloudPlay</span>
          <span style={s.brandVer}>v1.3</span>
        </div>
        <div style={s.topCenter}>
          {active>0 && (
            <div style={s.activePill}>
              <span style={s.activeDot}/>
              {active} {active===1?'сесія активна':'сесії активні'}
            </div>
          )}
        </div>
        <div style={s.topRight}>
          <div style={s.clockBox}>
            <div style={s.clockTime}>{timeStr}</div>
            <div style={s.clockDate}>{dateStr}</div>
          </div>
          <button style={s.logoutBtn} onClick={onLogout} title="Вийти">
            <span>⏻</span>
          </button>
        </div>
      </header>

      {/* HERO */}
      <div style={s.hero}>
        <div style={s.heroInner}>
          <p style={s.heroTag}>☁ Особистий хмарний сервер</p>
          <h1 style={s.heroTitle}>
            Запускай будь-що<br/>
            <span style={s.heroGrad}>прямо в браузері</span>
          </h1>
          <p style={s.heroSub}>Firefox, Linux ПК або Android — без навантаження на твій девайс.</p>
        </div>
      </div>

      {/* CARDS */}
      <div style={s.cardsWrap}>
        <div style={s.cards}>
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
      </div>

      {/* FOOTER */}
      <div style={s.foot}>
        <span style={s.footItem}>CloudPlay v1.3</span>
        <span style={s.footDot}>·</span>
        <span style={s.footItem}>Приватний сервер</span>
        <span style={s.footDot}>·</span>
        <span style={s.footItem}>2-3 користувачі</span>
      </div>

      <style>{`
        @keyframes bg1{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(60px,-80px) scale(1.15)}}
        @keyframes bg2{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(-80px,60px) scale(1.1)}}
        @keyframes bg3{0%,100%{transform:translate(-50%,-50%) scale(1)}50%{transform:translate(-50%,-50%) scale(1.25)}}
        @keyframes bg4{0%,100%{transform:translate(0,0)}50%{transform:translate(50px,30px)}}
        @keyframes gradAnim{0%,100%{background-position:0% 50%}50%{background-position:100% 50%}}
        @keyframes fadeUp{from{opacity:0;transform:translateY(30px)}to{opacity:1;transform:none}}
        @keyframes dotPulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.6;transform:scale(.8)}}
        @keyframes tickAnim{from{opacity:0}to{opacity:1}}
      `}</style>
    </div>
  );
}

function BG(){
  return (
    <div style={{position:'fixed',inset:0,zIndex:0,overflow:'hidden',background:'#030308',pointerEvents:'none'}}>
      <div style={{position:'absolute',width:1000,height:1000,borderRadius:'50%',
        background:'radial-gradient(circle,rgba(79,70,229,.18) 0%,transparent 70%)',
        top:-400,right:-300,filter:'blur(40px)',animation:'bg1 14s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:900,height:900,borderRadius:'50%',
        background:'radial-gradient(circle,rgba(124,58,237,.14) 0%,transparent 70%)',
        bottom:-400,left:-300,filter:'blur(40px)',animation:'bg2 17s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:700,height:700,borderRadius:'50%',
        background:'radial-gradient(circle,rgba(14,165,233,.1) 0%,transparent 70%)',
        top:'50%',left:'50%',filter:'blur(40px)',animation:'bg3 11s ease-in-out infinite'}}/>
      <div style={{position:'absolute',width:500,height:500,borderRadius:'50%',
        background:'radial-gradient(circle,rgba(16,185,129,.08) 0%,transparent 70%)',
        bottom:50,right:50,filter:'blur(40px)',animation:'bg4 15s ease-in-out infinite'}}/>
      <div style={{position:'absolute',inset:0,
        backgroundImage:'linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px)',
        backgroundSize:'64px 64px'}}/>
    </div>
  );
}

const s={
  root:{minHeight:'100vh',background:'transparent',fontFamily:"'Space Grotesk',sans-serif",color:'#fff',
    display:'flex',flexDirection:'column',position:'relative'},
  topbar:{position:'relative',zIndex:10,display:'flex',alignItems:'center',
    padding:'12px 32px',gap:16,
    background:'rgba(3,3,8,.85)',backdropFilter:'blur(20px)',
    borderBottom:'1px solid rgba(255,255,255,.06)'},
  brand:{display:'flex',alignItems:'center',gap:8,flexShrink:0},
  brandIcon:{fontSize:22,filter:'drop-shadow(0 0 10px rgba(255,200,0,.8))'},
  brandName:{fontSize:18,fontWeight:700,letterSpacing:'-.5px'},
  brandVer:{fontSize:10,color:'rgba(255,255,255,.3)',border:'1px solid rgba(255,255,255,.1)',
    padding:'2px 7px',borderRadius:5,fontFamily:"'Inter',sans-serif"},
  topCenter:{flex:1,display:'flex',justifyContent:'center'},
  activePill:{display:'flex',alignItems:'center',gap:7,fontSize:12,
    color:'#10b981',background:'rgba(16,185,129,.1)',border:'1px solid rgba(16,185,129,.25)',
    padding:'5px 14px',borderRadius:20,fontFamily:"'Inter',sans-serif",fontWeight:500},
  activeDot:{width:7,height:7,borderRadius:'50%',background:'#10b981',
    boxShadow:'0 0 8px #10b981',animation:'dotPulse 2s ease-in-out infinite',display:'inline-block'},
  topRight:{display:'flex',alignItems:'center',gap:14,flexShrink:0},
  clockBox:{textAlign:'right'},
  clockTime:{fontSize:18,fontWeight:700,letterSpacing:'1px',lineHeight:1.2,
    fontVariantNumeric:'tabular-nums',animation:'tickAnim .1s ease'},
  clockDate:{fontSize:10,color:'rgba(255,255,255,.3)',fontFamily:"'Inter',sans-serif",
    textTransform:'capitalize'},
  logoutBtn:{background:'rgba(255,255,255,.06)',border:'1px solid rgba(255,255,255,.1)',
    color:'rgba(255,255,255,.5)',width:34,height:34,borderRadius:8,
    cursor:'pointer',fontSize:16,display:'flex',alignItems:'center',justifyContent:'center',
    transition:'all .2s'},
  hero:{position:'relative',zIndex:10,padding:'72px 32px 48px',textAlign:'center'},
  heroInner:{maxWidth:700,margin:'0 auto',animation:'fadeUp .6s ease'},
  heroTag:{fontSize:12,fontWeight:600,letterSpacing:'2px',textTransform:'uppercase',
    color:'rgba(255,255,255,.3)',marginBottom:20,fontFamily:"'Inter',sans-serif"},
  heroTitle:{fontSize:'clamp(38px,6vw,72px)',fontWeight:700,lineHeight:1.08,
    letterSpacing:'-2.5px',marginBottom:20},
  heroGrad:{background:'linear-gradient(135deg,#818cf8 0%,#a78bfa 35%,#38bdf8 65%,#34d399 100%)',
    backgroundSize:'300% 300%',WebkitBackgroundClip:'text',WebkitTextFillColor:'transparent',
    animation:'gradAnim 6s ease infinite'},
  heroSub:{fontSize:18,lineHeight:1.65,color:'rgba(255,255,255,.4)',
    fontFamily:"'Inter',sans-serif",fontWeight:400},
  cardsWrap:{position:'relative',zIndex:10,flex:1,padding:'0 24px 40px'},
  cards:{maxWidth:1100,margin:'0 auto',display:'grid',
    gridTemplateColumns:'repeat(auto-fit,minmax(300px,1fr))',gap:20},
  foot:{position:'relative',zIndex:10,display:'flex',alignItems:'center',justifyContent:'center',
    gap:10,padding:'16px',borderTop:'1px solid rgba(255,255,255,.04)'},
  footItem:{fontSize:11,color:'rgba(255,255,255,.15)',fontFamily:"'Inter',sans-serif"},
  footDot:{color:'rgba(255,255,255,.1)'},
};

CPEOF006

RUN cat > /app/frontend/src/components/ServiceCard.jsx << 'CPEOF007'
import { useState, useEffect } from 'react';

export default function ServiceCard({ service:sv, status, loading, onStart, onReconnect, onStop }){
  const [hov, setHov]     = useState(false);
  const [elapsed, setEl]  = useState(0);
  const running = status?.running;

  useEffect(()=>{
    if(!running||!status?.startTime) return;
    const tick=()=>setEl(Math.floor((Date.now()-new Date(status.startTime))/1000));
    tick(); const id=setInterval(tick,1000); return()=>clearInterval(id);
  },[running,status?.startTime]);

  const fmt=s=>{
    const h=Math.floor(s/3600),m=Math.floor((s%3600)/60),sec=s%60;
    return h>0?`${h}:${p(m)}:${p(sec)}`:`${p(m)}:${p(sec)}`;
  };
  const p=n=>String(n).padStart(2,'0');

  return (
    <div style={{
      ...card,
      borderColor: running?`${sv.accent}50`:hov?'rgba(255,255,255,.14)':'rgba(255,255,255,.07)',
      background:  running?`${sv.accent}0c`:hov?'rgba(255,255,255,.06)':'rgba(255,255,255,.03)',
      transform:   hov&&!loading?'translateY(-6px)':'none',
      boxShadow:   running
        ?`0 0 0 1px ${sv.accent}25 inset, 0 24px 64px ${sv.accent}18`
        :hov?'0 24px 48px rgba(0,0,0,.35)':'0 4px 20px rgba(0,0,0,.2)',
    }}
    onMouseEnter={()=>setHov(true)} onMouseLeave={()=>setHov(false)}>

      {/* Top accent line */}
      <div style={{...topLine, background:sv.g, opacity:running?1:hov?.7:.35}}/>

      {/* Glow blob */}
      <div style={{position:'absolute',inset:-80,borderRadius:'50%',
        background:sv.glow,filter:'blur(100px)',opacity:running?.3:hov?.15:.05,
        pointerEvents:'none',transition:'opacity .3s'}}/>

      {/* Status */}
      <div style={{...badge, background:running?`${sv.accent}18`:'rgba(255,255,255,.05)',
        borderColor:running?`${sv.accent}40`:'rgba(255,255,255,.09)',
        color:running?sv.accent:'rgba(255,255,255,.35)'}}>
        <span style={{width:6,height:6,borderRadius:'50%',background:running?sv.accent:'rgba(255,255,255,.25)',
          display:'inline-block',boxShadow:running?`0 0 8px ${sv.accent}`:'none',
          animation:running?'blink 2s ease infinite':'none'}}/>
        {running?'Активна':'Очікує'}
      </div>

      {/* Icon */}
      <div style={iconWrap}>{sv.icon}</div>

      {/* Text */}
      <h3 style={title}>{sv.label}</h3>
      <p style={desc}>{sv.desc}</p>

      {/* Timer */}
      {running && (
        <div style={timer}>
          <span>⏱</span>
          <span style={{fontVariantNumeric:'tabular-nums',letterSpacing:'.5px'}}>{fmt(elapsed)}</span>
        </div>
      )}

      {/* Buttons */}
      <div style={btnRow}>
        {running ? (
          <>
            <button style={{...btn,background:sv.g,border:'none',
              boxShadow:`0 4px 20px ${sv.accent}40`,flex:1}}
              onClick={onReconnect}>▶ Підключитись</button>
            <button style={{...btn,background:'rgba(239,68,68,.12)',
              borderColor:'rgba(239,68,68,.3)',color:'#f87171',width:42}}
              onClick={onStop} title="Зупинити">⏹</button>
          </>
        ):(
          <button style={{...btn, flex:1,
            background:hov?`${sv.accent}20`:'rgba(255,255,255,.06)',
            borderColor:hov?`${sv.accent}50`:'rgba(255,255,255,.1)',
            cursor:loading?'wait':'pointer', opacity:loading?.7:1}}
            onClick={onStart} disabled={loading}>
            {loading
              ?<><span style={spin}/>Запускаємо...</>
              <>🚀 Запустити</>}
          </button>
        )}
      </div>

      <style>{`
        @keyframes blink{0%,100%{opacity:1}50%{opacity:.4}}
        @keyframes sp{to{transform:rotate(360deg)}}
      `}</style>
    </div>
  );
}

const card={position:'relative',borderRadius:20,padding:'24px 22px 20px',
  border:'1px solid',overflow:'hidden',display:'flex',flexDirection:'column',gap:10,
  transition:'all .28s cubic-bezier(.4,0,.2,1)',backdropFilter:'blur(16px)',
  fontFamily:"'Space Grotesk',sans-serif"};
const topLine={position:'absolute',top:0,left:0,right:0,height:2,transition:'opacity .3s'};
const badge={position:'relative',zIndex:1,alignSelf:'flex-start',display:'flex',
  alignItems:'center',gap:6,fontSize:11,fontWeight:600,letterSpacing:'.8px',
  textTransform:'uppercase',border:'1px solid',padding:'3px 10px',borderRadius:6,
  fontFamily:"'Inter',sans-serif"};
const iconWrap={position:'relative',zIndex:1,fontSize:44,lineHeight:1,marginTop:4};
const title={position:'relative',zIndex:1,fontSize:21,fontWeight:700,
  letterSpacing:'-.5px',color:'#fff',margin:0};
const desc={position:'relative',zIndex:1,fontSize:13,color:'rgba(255,255,255,.45)',
  lineHeight:1.6,margin:0,fontFamily:"'Inter',sans-serif",flexGrow:1};
const timer={position:'relative',zIndex:1,display:'flex',alignItems:'center',gap:6,
  fontSize:13,color:'rgba(255,255,255,.5)',fontFamily:"'Inter',sans-serif"};
const btnRow={position:'relative',zIndex:1,display:'flex',gap:8,marginTop:4};
const btn={display:'flex',alignItems:'center',justifyContent:'center',gap:7,
  padding:'12px 16px',borderRadius:10,fontSize:13,fontWeight:600,
  fontFamily:"'Space Grotesk',sans-serif",border:'1px solid',
  color:'#fff',transition:'all .2s',cursor:'pointer'};
const spin={display:'inline-block',width:13,height:13,
  border:'2px solid rgba(255,255,255,.2)',borderTopColor:'#fff',
  borderRadius:'50%',animation:'sp .7s linear infinite'};

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
const { spawn, execSync } = require('child_process');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');

const CONFIGS = {
  browser: { display:':1', vncPort:5901, wsPort:6901, res:'1920x1080x24' },
  desktop: { display:':2', vncPort:5902, wsPort:6902, res:'1920x1080x24' },
  phone:   { display:':3', vncPort:5903, wsPort:6903, res:'412x915x24'   },
};
const sessions = {};
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

  // Xvfb
  procs.xvfb=sp('Xvfb',[cfg.display,'-screen','0',cfg.res,'-ac','-nolisten','tcp','-noreset','-dpi','96']);
  await sleep(1500);

  // Фон (без WM)
  sp('xsetroot',['-solid','#0d1117'],{DISPLAY:cfg.display});
  await sleep(200);

  if(type==='browser'){
    // Openbox + Firefox повноекранний
    procs.wm=sp('openbox',['--config-file','/app/ob-rc.xml'],
      {DISPLAY:cfg.display,HOME:'/root',GTK_THEME:'Arc-Dark'});
    await sleep(800);
    procs.browser=sp(FF,['--no-remote','--new-instance','--maximized',
      '-url','https://www.google.com'],
      {DISPLAY:cfg.display,HOME:'/root',MOZ_DISABLE_CONTENT_SANDBOX:'1',
       GTK_THEME:'Arc-Dark',MOZ_ENABLE_WAYLAND:'0'});

  } else if(type==='desktop'){
    // Openbox + tint2 taskbar + Firefox
    fs.mkdirSync('/tmp/xdg',{recursive:true});

    procs.wm=sp('openbox',['--config-file','/app/ob-rc.xml'],
      {DISPLAY:cfg.display,HOME:'/root',GTK_THEME:'Arc-Dark',
       XDG_RUNTIME_DIR:'/tmp/xdg'});
    await sleep(800);

    procs.taskbar=sp('tint2',['-c','/app/tint2rc'],
      {DISPLAY:cfg.display,HOME:'/root'});
    await sleep(400);

    // Wallpaper
    try{
      execSync('convert -size 1920x1080 gradient:"#0d1117-#1a2744" /tmp/wp.png',{timeout:5000});
      sp('feh',['--bg-scale','/tmp/wp.png'],{DISPLAY:cfg.display});
    }catch{}

    // Firefox автозапуск
    procs.browser=sp(FF,['--no-remote','--new-instance','https://www.google.com'],
      {DISPLAY:cfg.display,HOME:'/root',MOZ_DISABLE_CONTENT_SANDBOX:'1',
       GTK_THEME:'Arc-Dark',MOZ_ENABLE_WAYLAND:'0',XDG_RUNTIME_DIR:'/tmp/xdg'});

  } else if(type==='phone'){
    procs.wm=sp('openbox',['--config-file','/app/ob-rc.xml'],
      {DISPLAY:cfg.display,HOME:'/root'});
    await sleep(700);
    procs.browser=sp(FF,['--no-remote','--new-instance','--kiosk',
      'file:///app/backend/android.html'],
      {DISPLAY:cfg.display,HOME:'/root',MOZ_DISABLE_CONTENT_SANDBOX:'1',
       MOZ_ENABLE_WAYLAND:'0'});
  }

  await sleep(type==='desktop'?6000:5000);

  procs.vnc=sp('x11vnc',['-display',cfg.display,'-forever','-nopw',
    '-quiet','-shared','-rfbport',String(cfg.vncPort),
    '-wait','20','-defer','10','-no6']);
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
  delete sessions[type];
}

function getAllStatus(){
  const o={browser:{running:false},desktop:{running:false},phone:{running:false}};
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

RUN cat > /app/ob-rc.xml << 'CPEOF017'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme><name>Arc-Dark</name>
    <font place="ActiveWindow"><name>Sans</name><size>10</size><weight>Bold</weight></font>
  </theme>
  <desktops><number>1</number><names><name>CloudPlay</name></names></desktops>
  <focus><followMouse>no</followMouse><focusLast>yes</focusLast></focus>
  <placement><policy>Smart</policy></placement>
  <keyboard>
    <keybind key="A-F4"><action name="Close"/></keybind>
    <keybind key="super-d"><action name="ToggleShowDesktop"/></keybind>
  </keyboard>
  <mouse>
    <context name="Desktop">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
    <context name="Client">
      <mousebind button="A-Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="A-Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="A-Right" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="Left" action="DoubleClick"><action name="ToggleMaximize"/></mousebind>
    </context>
  </mouse>
</openbox_config>

CPEOF017

RUN cat > /app/ob-menu.xml << 'CPEOF018'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="CloudPlay PC">
    <item label="🌐  Firefox Browser">
      <action name="Execute"><execute>/opt/firefox/firefox --new-window https://www.google.com</execute></action>
    </item>
    <item label="📁  Files (Thunar)">
      <action name="Execute"><execute>thunar /root</execute></action>
    </item>
    <item label="🖥️  Terminal">
      <action name="Execute"><execute>xterm -bg '#0d1117' -fg '#e6edf3' -fa 'Monospace' -fs 13 -title Terminal</execute></action>
    </item>
    <separator/>
    <item label="📝  Text Editor">
      <action name="Execute"><execute>mousepad</execute></action>
    </item>
    <item label="🖥️  System Monitor">
      <action name="Execute"><execute>xterm -e 'htop'</execute></action>
    </item>
    <separator/>
    <item label="🔄  Restart Desktop">
      <action name="Restart"/>
    </item>
  </menu>
</openbox_menu>

CPEOF018

RUN cat > /app/tint2rc << 'CPEOF019'
# CloudPlay tint2 config
rounded = 0
border_width = 0
background_color = #0d1117 100
border_color = #30363d 100

panel_monitor = all
panel_position = bottom center horizontal
panel_size = 100% 44
panel_margin = 0 0
panel_padding = 4 0 4
panel_dock = 0
wm_menu = 0
panel_layer = top
panel_background_id = 1
panel_items = LTSC

# Taskbar
taskbar_mode = single_desktop
taskbar_padding = 2 2 2
taskbar_background_id = 0
taskbar_active_background_id = 2

task_icon = 1
task_text = 1
task_maximum_size = 220 36
task_centered = 1
task_padding = 4 4 4
task_font = Sans 10
task_font_color = #c9d1d9 100
task_active_font_color = #ffffff 100
task_background_id = 3
task_active_background_id = 4

# Launcher
launcher_padding = 6 4 6
launcher_background_id = 0
launcher_icon_theme =
launcher_item_app = /app/firefox.desktop

# Systray
systray_padding = 4 4 4
systray_sort = ascending
systray_icon_size = 22
systray_icon_asb = 100 0 0
systray_background_id = 0

# Clock
time1_format = %H:%M
time1_font = Sans Bold 13
time1_font_color = #ffffff 100
time2_format = %a %d %b
time2_font = Sans 9
time2_font_color = #8b949e 100
clock_font_color = #ffffff 100
clock_padding = 8 4
clock_background_id = 0

# Background 1 - panel
rounded = 0
border_width = 0
background_color = #0d1117 100
border_color = #21262d 100

# Background 2 - active taskbar item
rounded = 4
border_width = 0
background_color = #21262d 100
border_color = #30363d 100

# Background 3 - task
rounded = 4
border_width = 0
background_color = #0d1117 0
border_color = #30363d 0

# Background 4 - active task
rounded = 4
border_width = 0
background_color = #1f6feb 80
border_color = #1f6feb 100

CPEOF019

RUN cat > /app/firefox.desktop << 'CPEOF020'
[Desktop Entry]
Name=Firefox
Exec=/opt/firefox/firefox --new-window https://www.google.com
Icon=firefox
Type=Application

CPEOF020

RUN ln -sf /app/ob-rc.xml /root/.config/openbox/rc.xml     && ln -sf /app/ob-menu.xml /root/.config/openbox/menu.xml

RUN cd /app/backend && npm install --production
RUN cd /app/frontend && npm install && npm run build

EXPOSE 8080
CMD ["/usr/bin/supervisord", "-n", "-c", "/app/supervisord.conf"]
