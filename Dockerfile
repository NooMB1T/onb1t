FROM ubuntu:22.04

LABEL maintainer="CloudPlay"
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=$PATH:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/emulator:/opt/android-sdk/platform-tools

# ── 1. Системні пакети ───────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc xauth dbus-x11 \
    openbox xfce4 xfce4-terminal \
    chromium-browser \
    python3 python3-pip \
    wget curl unzip supervisor nginx \
    net-tools procps \
    fonts-liberation fontconfig libfontconfig1 \
    openjdk-17-jdk-headless \
    libgl1-mesa-glx libglu1-mesa \
    && pip3 install --no-cache-dir websockify \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── 2. Node.js 20 ────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── 3. noVNC ─────────────────────────────────────────────────────
RUN mkdir -p /opt/novnc \
    && wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
       | tar xz --strip-components=1 -C /opt/novnc \
    && ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# ── 4. Android SDK + Emulator (inline, без зовнішніх скриптів) ──
RUN mkdir -p /opt/android-sdk/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
       -O /tmp/cmdtools.zip \
    && unzip -q /tmp/cmdtools.zip -d /tmp/ \
    && mv /tmp/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
    && rm -f /tmp/cmdtools.zip

RUN yes | sdkmanager --sdk_root=/opt/android-sdk --licenses > /dev/null 2>&1 \
    && sdkmanager --sdk_root=/opt/android-sdk \
       "emulator" \
       "platform-tools" \
       "platforms;android-30" \
       "system-images;android-30;google_apis;x86_64"

RUN mkdir -p /root/.android/avd \
    && echo no | avdmanager --sdk_root=/opt/android-sdk create avd \
       -n CloudPhone \
       -k "system-images;android-30;google_apis;x86_64" \
       -d "pixel_4a" --force \
    && echo "hw.cpu.ncore=2"          >> /root/.android/avd/CloudPhone.avd/config.ini \
    && echo "hw.ramSize=2048"         >> /root/.android/avd/CloudPhone.avd/config.ini \
    && echo "hw.gpu.enabled=yes"      >> /root/.android/avd/CloudPhone.avd/config.ini \
    && echo "hw.gpu.mode=swiftshader_indirect" >> /root/.android/avd/CloudPhone.avd/config.ini \
    && echo "hw.keyboard=yes"         >> /root/.android/avd/CloudPhone.avd/config.ini \
    && echo "showDeviceFrame=no"      >> /root/.android/avd/CloudPhone.avd/config.ini

# ── 5. Backend ───────────────────────────────────────────────────
WORKDIR /app
COPY backend/package.json ./backend/
RUN cd backend && npm install --production

# ── 6. Frontend (build) ──────────────────────────────────────────
COPY frontend/package.json ./frontend/
RUN cd frontend && npm install

COPY frontend/ ./frontend/
RUN cd frontend && npm run build

# ── 7. Решта файлів ──────────────────────────────────────────────
COPY backend/ ./backend/
COPY nginx.conf      ./nginx.conf
COPY supervisord.conf ./supervisord.conf

# ── 8. Runtime dirs ──────────────────────────────────────────────
RUN mkdir -p /var/log/supervisor /var/log/nginx /run/nginx \
    && mkdir -p /root/.config/openbox /root/.config/xfce4 \
    && rm -f /etc/nginx/sites-enabled/default

EXPOSE 8080

CMD ["/usr/bin/supervisord", "-n", "-c", "/app/supervisord.conf"]
