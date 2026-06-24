const express = require('express');
const path = require('path');
const sessionManager = require('./sessionManager');

const app = express();
app.use(express.json());

// ── API ──────────────────────────────────────────────────────────

app.post('/api/sessions/start/:type', async (req, res) => {
  const { type } = req.params;
  if (!['browser', 'desktop', 'phone'].includes(type)) {
    return res.status(400).json({ success: false, error: 'Невідомий тип сесії' });
  }
  try {
    await sessionManager.startSession(type);
    res.json({
      success: true,
      vncUrl: `/novnc/vnc.html?path=websockify/${type}&autoconnect=true&reconnect=true&show_dot=true`,
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

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// ── Start ────────────────────────────────────────────────────────

const PORT = process.env.API_PORT || 3001;
app.listen(PORT, '127.0.0.1', () => {
  console.log(`🚀 CloudPlay API listening on 127.0.0.1:${PORT}`);
});
