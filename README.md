# Nexus Comm / dsaialap

Hybrid E2EE communication platform: internet signaling, offline mesh voice, and SIM fallback.

## Architecture and deploy

- `docs/architecture.md` — system design, Slice 1 offline flow, crypto, and online path
- `docs/deployment-process.md` — GitHub Actions, APK, VPS, and Vercel release rules
- `DEPLOY.md` — VPS operator runbook

## Layout

```
backend/     Node.js + TypeScript API, Socket.io signaling, Prisma (Postgres), Redis OTP
mobile/      Flutter client (BLoC, i18n en/bn, 4-tab IndexedStack shell)
frontend/    Vercel/Netlify SPA: landing + B2B dashboard
dashboard/   (legacy single-file B2B portal, superseded by frontend/)
```

## Backend

Required env: copy `backend/.env.example` to `backend/.env`.

```bash
cd backend
npm ci
npx prisma generate
npm run dev
```

Local Docker dev stack:

```bash
cd backend
cp .env.example .env
docker compose up --build
```

Production (Google VPS, Docker + Nginx reverse proxy + Let's Encrypt):

```bash
cd backend
cp .env.example .env
docker compose -f docker-compose.prod.yml up -d --build
bash scripts/issue-certs.sh
```

See `DEPLOY.md` for the full production runbook.

### Auth

- `POST /api/auth/otp/request` — SMS OTP, Redis TTL 180s, max 3 / 15 min
- `POST /api/auth/otp/verify` — JWT access 15m + HTTP-only refresh cookie
- `POST /api/auth/refresh` / `POST /api/auth/logout`
- `POST /api/auth/backup/register` and restore endpoints for offline backup keys

### Signaling (Socket.io)

Authenticated with Bearer access token. Events: `call:offer|answer|ice|hangup`, `message:send|delivered|read`, `e2ee:prekey`.
Server pings every 25s (`pingInterval`) and drops dead sockets; failed webhook deliveries are queued in Redis and retried.

### B2B SaaS

All B2B endpoints live under `/api/b2b` behind the `x-dsaialap-key` header (tier-based Redis rate
limiting + webhook dispatcher with retry queue). Configure `DSAIALAP_B2B_KEYS` in `.env`.

### CPaaS / telecom layer (optional, off by default)

Voice interpreter (JSON-first verbs), FreeSWITCH ESL client, jambonz BYOC provider and a BD-aware
SMS gateway with licensed fallback. Mounted at `/api/cpaas` **only** when `ENABLE_CPAAS_LAYER=true`;
runs behind hashed Prisma `ApiKey` auth (`x-dsaialap-key`). See `backend/CPAAS.md` for the operator
runbook, migration/rollback steps and regulatory notes.

## Mobile

Release APKs are built in CI (`.github/workflows/build-apk.yml`) and published to GitHub Releases —
no local SDK needed. Run it once:

```bash
./deploy_and_export.sh
```

Local (non-destructive) build:

```bash
cd mobile
flutter pub get
flutter gen-l10n
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://dsaialap.banglarvoice24news.com
```

Language switches at runtime via `LocaleCubit` without restart.
