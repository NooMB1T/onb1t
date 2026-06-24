# ⚡ CloudPlay — Personal Cloud Desktop

Особистий хмарний сервер для 2-3 людей. Запускай браузер, Linux і Android прямо у браузері телефону.

## Що всередині

| Сервіс | Технологія | Статус |
|--------|-----------|--------|
| 🌐 Browser | Chromium + Openbox + noVNC | ✅ Готово |
| 🖥️ Desktop | Ubuntu + XFCE4 + noVNC | ✅ Готово |
| 📱 Phone | Android Emulator + noVNC | ⚠️ Потрібен KVM |

## Архітектура

```
[Browser] → HTTPS → [Nginx :8080]
                        ├── /         → React SPA
                        ├── /novnc/   → noVNC client (HTML/JS)
                        ├── /api/     → Node.js backend
                        └── /websockify/[type] → websockify → VNC
```

## Деплой на Railway

### 1. Підготовка репо
```bash
git init
git add .
git commit -m "initial"
```

### 2. Railway
1. Заходь на [railway.app](https://railway.app)
2. New Project → Deploy from GitHub
3. Вибери своє репо
4. Railway сам знайде `Dockerfile` і збере образ
5. В Settings → Networking: Generate Domain

### 3. Готово!
Відкривай `https://your-app.railway.app` і отримуй хмару.

## Локальний запуск (Docker)

```bash
docker compose up --build
# → відкривай http://localhost:8080
```

## Потрібні ресурси на Railway

| | Мінімум | Рекомендовано |
|--|---------|---------------|
| RAM | 1 GB | 2 GB |
| CPU | 1 vCPU | 2 vCPU |
| Диск | 5 GB | — |

## Android KVM (телефон)

Railway Hobby/Pro плани підтримують KVM. Щоб увімкнути:
1. В Railway: Settings → Environment → Add Variable: `ENABLE_KVM=true`
2. Потрібно ще встановити Android SDK всередині контейнера (буде в наступній версії)

## Структура проекту

```
cloudplay/
├── frontend/         # React + Vite (UI)
├── backend/          # Node.js API + session manager
├── nginx.conf        # Reverse proxy (єдиний порт)
├── supervisord.conf  # Process manager
└── Dockerfile        # Railway/Docker image
```
