const { spawn, execSync } = require('child_process');
const { v4: uuidv4 } = require('uuid');

// Per-session config: display number, VNC port, WebSocket port
const CONFIGS = {
  browser: { display: ':1', vncPort: 5901, wsPort: 6901 },
  desktop: { display: ':2', vncPort: 5902, wsPort: 6902 },
  phone:   { display: ':3', vncPort: 5903, wsPort: 6903 },
};

const sessions = { browser: null, desktop: null, phone: null };

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

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
  if (!cfg) throw new Error('Unknown session type');

  console.log(`\n▶ Starting [${type}] on ${cfg.display}...`);
  const procs = {};

  // ── 1. Xvfb ─────────────────────────────────────────────────
  procs.xvfb = spawnProc('Xvfb', [
    cfg.display,
    '-screen', '0', '1920x1080x24',
    '-ac', '-nolisten', 'tcp', '-noreset',
  ]);
  await sleep(1200);

  // ── 2. Window manager + app ──────────────────────────────────
  if (type === 'browser') {
    procs.wm = spawnProc('openbox', ['--startup', 'openbox --reconfigure'], {
      DISPLAY: cfg.display,
    });
    await sleep(600);

    procs.app = spawnProc('chromium-browser', [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--start-maximized',
      '--new-window',
      'https://www.google.com',
    ], { DISPLAY: cfg.display });

  } else if (type === 'desktop') {
    // XFCE4 full desktop
    procs.wm = spawnProc('bash', ['-c', 'startxfce4'], {
      DISPLAY: cfg.display,
      DBUS_SESSION_BUS_ADDRESS: '/dev/null',
      HOME: '/root',
    });

  } else if (type === 'phone') {
    // Check KVM
    try { execSync('test -e /dev/kvm'); }
    catch {
      throw new Error(
        'Android-емулятор потребує KVM. Увімкни апаратну віртуалізацію на Railway або запусти локально з KVM.'
      );
    }
    procs.wm = spawnProc('openbox', [], { DISPLAY: cfg.display });
    await sleep(500);
    procs.app = spawnProc('/opt/android-sdk/emulator/emulator', [
      '-avd', 'Pixel7',
      '-no-audio', '-no-boot-anim',
      '-gpu', 'swiftshader_indirect',
      '-no-accel',
    ], {
      DISPLAY: cfg.display,
      ANDROID_SDK_ROOT: '/opt/android-sdk',
      ANDROID_AVD_HOME: '/root/.android/avd',
    });
  }

  await sleep(2500);

  // ── 3. x11vnc ────────────────────────────────────────────────
  procs.vnc = spawnProc('x11vnc', [
    '-display', cfg.display,
    '-forever', '-nopw', '-quiet', '-shared',
    '-rfbport', String(cfg.vncPort),
  ]);
  await sleep(800);

  // ── 4. websockify (WebSocket ↔ VNC) ─────────────────────────
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
    out[type] = s
      ? { running: true, id: s.id, startTime: s.startTime }
      : { running: false };
  }
  return out;
}

module.exports = { startSession, stopSession, getAllStatus };
