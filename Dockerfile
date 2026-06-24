FROM ubuntu:22.04

LABEL maintainer="CloudPlay Personal"
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8

# ── System packages ──────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # X11 virtual display
    xvfb x11vnc xauth dbus-x11 \
    # Window managers
    openbox xfce4 xfce4-terminal \
    # Browser
    chromium-browser \
    # Python + websockify
    python3 python3-pip \
    # Tools
    wget curl supervisor nginx \
    net-tools procps \
    fonts-liberation fontconfig \
    && pip3 install websockify \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 ───────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── noVNC ────────────────────────────────────────────────────────
RUN mkdir -p /opt/novnc \
    && wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
       | tar xz --strip-components=1 -C /opt/novnc \
    && ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# ── App files ────────────────────────────────────────────────────
WORKDIR /app

# Backend deps (cached layer)
COPY backend/package.json ./backend/
RUN cd backend && npm install --production

# Frontend deps (cached layer)
COPY frontend/package.json ./frontend/
RUN cd frontend && npm install

# Build frontend
COPY frontend/ ./frontend/
RUN cd frontend && npm run build

# Copy rest of backend
COPY backend/ ./backend/

# Configs
COPY nginx.conf ./nginx.conf
COPY supervisord.conf ./supervisord.conf

# ── Runtime setup ────────────────────────────────────────────────
RUN mkdir -p /var/log/supervisor /var/log/nginx /run/nginx \
    && mkdir -p /root/.config/openbox /root/.config/xfce4

# Remove default nginx site
RUN rm -f /etc/nginx/sites-enabled/default

EXPOSE 8080

CMD ["/usr/bin/supervisord", "-n", "-c", "/app/supervisord.conf"]
