# dsaialap deploy notes

Existing mobile APIs (`/api/auth`, `/api/users`, `/api/messages`) and Socket.io events are unchanged.
B2B lives only under `/api/b2b`. New backend logic stays in `src/services/` and `src/middlewares/`.

## Repository layout

```
backend/                      Node.js + TypeScript API (Prisma + Postgres + Redis)
  Dockerfile                  multi-stage build; `runtime` (app) + `migrate` (one-shot prisma)
  .dockerignore               excludes secrets, tests and tooling from the build context
  nginx/nginx.conf            main nginx config (includes conf.d/*.conf)
  nginx/conf.d/dsaialap.conf  dsaialap vhost: SSL, WSS, Cloudflare real-IP, rate limits
  docker-compose.prod.yml     PRODUCTION compose (pinned digests, healthchecks, limits, backups)
  scripts/issue-certs.sh      initial Let's Encrypt issuance
  scripts/deploy-vps.sh       pull by digest + migrate + health-gate + auto-rollback (runs on VPS)
  scripts/dsaialap_monitor.sh per-minute health/memory/socket watchdog
mobile/                       Flutter client (BLoC, i18n en/bn, 4-tab IndexedStack shell)
frontend/                     Static site for Vercel (index.html landing + b2b.html portal)
  vercel.json                 rewrites + security headers (CSP is report-only)
  .env.example                documents that no build-time env vars are required
.github/workflows/
  build-apk.yml               CI build of signed release APKs -> GitHub Release
  backend-ci.yml              typecheck/test/secret-scan/hadolint -> build+scan+push GHCR
  backend-deploy.yml          deploy the pushed digest to the VPS over SSH
  frontend-vercel.yml         preview deploys on PRs, production on main
.gitleaks.toml                secret-scanning config (allowlists placeholders/docs)
.trivyignore                  image vulnerability waivers (empty; every entry needs a reason)
.pre-commit-config.yaml        local gitleaks + hadolint hooks
deploy_and_export.sh          commit + push + trigger CI + print APK links
```

The production compose file for the VPS is `backend/docker-compose.prod.yml`
(it is the file the monitor, cron, deploy workflow, and this doc reference). The base
`docker-compose.yml` is the local-dev stack; `docker-compose.cpaas.yml` is the
optional telecom layer.

## Google VPS (Docker + Nginx)

Target host `dsaialap.banglarvoice24news.com` -> Google VPS `34.61.176.149` (1GB RAM).
Place the project under `/opt/dsaialap`.

```bash
cd /opt/dsaialap/backend
cp .env.example .env
```

Edit `.env` and set real secrets plus B2B keys.

B2B key format (comma-separated `key|name|tier|webhookUrl`):

```bash
DSAIALAP_B2B_KEYS=sk_live_abc123|acme-corp|enterprise|https://client.example.com/hooks/dsaialap,sk_live_xyz|acme-ltd|pro|
```

Populate `.env` (never commit it). At minimum set `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`, `REDIS_PASSWORD`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
`BACKUP_KEY_PEPPER`, `CORS_ORIGINS`, `PUBLIC_HOST`, and the two image refs
(`BACKEND_IMAGE`, `BACKEND_MIGRATE_IMAGE`) written by the deploy workflow. See
`backend/.env.example` for the full list with dummy values.

Production requires an SMS gateway: the API refuses to boot in `NODE_ENV=production`
unless either Twilio (`TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN`/`TWILIO_FROM_NUMBER`) or a
custom REST gateway (`SMS_API_URL`/`SMS_API_KEY`) is configured. OTP fallback to the
log gateway is development/test only.

Build once locally, or let CI build and push to GHCR (recommended). Only the first-ever
deploy needs the images built before they exist:

```bash
cd /opt/dsaialap/backend
DOCKER_BUILDKIT=1 docker build -t nexus-backend:local --target runtime .
DOCKER_BUILDKIT=1 docker build -t nexus-backend-migrate:local --target migrate .
```

Bootstrap the stack (run the `migrate` service, then start everything):

```bash
cd /opt/dsaialap/backend
docker compose --env-file .env -f docker-compose.prod.yml pull
docker compose --env-file .env -f docker-compose.prod.yml run --rm migrate
docker compose --env-file .env -f docker-compose.prod.yml up -d --remove-orphans
bash scripts/issue-certs.sh
chmod +x scripts/dsaialap_monitor.sh
```

Runtime hardening: images are pinned by digest; the API runs as non-root uid 10001 with a
read-only root filesystem (`/tmp` is a small tmpfs), `no-new-privileges` and all Linux
capabilities dropped. The app container does **not** run migrations — that is the
separate `migrate` service, which exits before the API starts.

Memory is enforced with `deploy.resources.limits` (Compose v2): API `256M` (soft reserve
`96M`), Postgres `384M`, Redis `64M`, nginx `64M`, certbot/migrate `256M`/`64M`. This keeps
the whole stack well inside a 1GB VPS. Services use `restart: unless-stopped`; nginx
auto-reloads every 6h so renewed Certbot certificates are served without a manual restart.

### Backups and restore

Postgres is dumped to the `backups` named volume (newest 14 gzipped dumps retained). The
service is one-shot, so schedule it from host cron:

```bash
# /etc/cron.d/nexus-backup  (daily 02:30 UTC)
30 2 * * * root cd /opt/dsaialap/backend && docker compose --env-file .env -f docker-compose.prod.yml --profile backup run --rm backup >> /var/log/nexus-backup.log 2>&1
```

Restore a dump (replace the filename and target db):

```bash
gunzip -c /var/lib/docker/volumes/nexus-backend_backups/_data/nexus_<ts>.sql.gz \
  | docker compose --env-file .env -f docker-compose.prod.yml exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Test a restore against a throwaway database before relying on it.


Monitor (cron, every minute) restarts the API when RSS >= 450MB, `/health` fails, or a live
Socket.io Engine.IO handshake fails:

```bash
* * * * * /opt/dsaialap/backend/scripts/dsaialap_monitor.sh
```

Overridable env vars: `COMPOSE_FILE`, `API_CONTAINER`, `MEM_LIMIT_MB`, `HEALTH_URL`, `SOCKET_URL`, `LOG`.
Log: `/var/log/dsaialap_monitor.log`.

Security note: nginx only rewrites the client IP from `CF-Connecting-IP` when the peer is inside
Cloudflare ranges. Lock port 443 to Cloudflare edge IPs at the GCP firewall so masked/Worker traffic
is the only path to the origin.

## Release APKs via GitHub Actions

No local SDK is required. The workflow `.github/workflows/build-apk.yml` builds on `ubuntu-latest`
with `subosito/flutter-action@v2`, runs `flutter build apk --release --split-per-abi` and uploads the
three APKs to a GitHub Release, then prints direct download links.

```bash
# One-shot automation (commit + push + trigger + links)
cd /opt/dsaialap
./deploy_and_export.sh

# Or trigger manually from GitHub UI -> Actions -> "Build APK & Release" -> Run workflow
```

Direct download URLs follow the pattern:

```text
https://github.com/<owner>/<repo>/releases/download/v1.0.0/app-arm64-v8a-release.apk
https://github.com/<owner>/<repo>/releases/download/v1.0.0/app-armeabi-v7a-release.apk
https://github.com/<owner>/<repo>/releases/download/v1.0.0/app-x86_64-release.apk
```

Local (non-destructive) alternative:

```bash
cd mobile
flutter pub get
flutter gen-l10n
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://dsaialap.banglarvoice24news.com
```

Outputs: `mobile/build/app/outputs/flutter-apk/app-{arm64-v8a,armeabi-v7a,x86_64}-release.apk`.

### Required GitHub repository secrets

`build-apk.yml`'s "Configure Release Signing" step reads the release signing material from
repository secrets (GitHub repo -> Settings -> Secrets and variables -> Actions). They are not
set automatically — add them once, then replace the placeholder values below with real ones.
If `KEYSTORE_BASE64` is left unset, that step is skipped and the release build step fails loudly
instead of silently falling back to debug signing (see `mobile/android/app/build.gradle.kts`).

| Secret            | Purpose                                      | Placeholder (replace with a real value) |
|-------------------|-----------------------------------------------|------------------------------------------|
| `KEYSTORE_BASE64` | base64 of the release `.jks` keystore file    | `CHANGE_ME_base64_keystore`              |
| `KEY_ALIAS`       | alias of the signing key inside the keystore  | `upload`                                 |
| `KEY_PASSWORD`    | password for that key alias                   | `CHANGE_ME`                              |
| `STORE_PASSWORD`  | password for the keystore file itself         | `CHANGE_ME`                              |

Generate a fresh upload keystore (do not reuse any pre-existing `.jks` file found elsewhere in
the repo history — its provenance can't be verified as a real production key, so treat it as
compromised rather than reusing it):

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 upload-keystore.jks > keystore_base64.txt
```

Paste the contents of `keystore_base64.txt` as the `KEYSTORE_BASE64` secret value, then delete
both local files — neither should ever be committed (`mobile/android/**/*.jks` and
`mobile/android/key.properties` are already git-ignored; see `mobile/android/key.properties.example`
for the equivalent local-dev file layout).

## Vercel / Netlify SPA frontend

The deployable frontend is `frontend/` (static single-page app; `index.html` = landing,
`b2b.html` = B2B portal). It calls the API host `https://dsaialap.banglarvoice24news.com`
(CORS allows `MASKED_ORIGINS`).

### Netlify

Connect the repo in the Netlify UI: build command (none), publish directory `frontend`
(`netlify.toml` at repo root already sets this and SPA redirects).

### Vercel (frontend only — not containerized)

The frontend is plain static HTML and does not need Docker. Import the repo in the
Vercel UI (or let `frontend-vercel.yml` manage it):

- Framework Preset: Other
- Root Directory: `frontend`
- Install Command: none / disabled (there is no `package.json`)
- Build Command: none
- Output Directory: `.` (the files sit at the root of `frontend/`)
- Environment Variables: none required today. Add any future build-time values in the
  dashboard only (Project -> Settings -> Environment Variables); never commit them.
  `frontend/.env.example` documents this.

`frontend/vercel.json` rewrites `/b2b` to `/b2b.html`, keeps unknown paths on
`/index.html` so a refresh never 404s, and applies security headers. Alternative: deploy
the repo root — the root `vercel.json` serves `/frontend/index.html`.

CSP note: `Content-Security-Policy-Report-Only` is shipped, not an enforcing
`Content-Security-Policy`. `b2b.html` contains an inline `<script>` and inline `<style>`,
and it fetches a user-entered API base, so an enforcing CSP would need `'unsafe-inline'`
and a broad `connect-src`. The report-only policy records violations without breaking the
page; enforcing it is a follow-up that requires moving the inline code to external files.

CI/CD: `.github/workflows/frontend-vercel.yml` deploys a preview on pull requests and
production on `main` using the `VERCEL_TOKEN`, `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID`
secrets. A preview deployment can be promoted to production from the Vercel dashboard.

Verify after deploy: hard-refresh `https://<app>.vercel.app/b2b` — it must render instead of 404.


## Backend release pipeline (CI/CD)

`.github/workflows/backend-ci.yml` runs on every backend change:

1. `npm ci`, `npm run typecheck`, `npm test`, `npm audit --omit=dev --audit-level=critical`.
2. Secret scan: gitleaks (whole history) and trufflehog (`--only-verified`).
3. `hadolint` on `backend/Dockerfile`.
4. On `main` only: build the `runtime` and `migrate` targets with buildx, push both to
   `ghcr.io/<owner>/<repo>/backend` tagged `sha-<commit>` with SLSA provenance and an SBOM,
   then scan the pushed digest with Trivy and fail on CRITICAL (waivers live in `.trivyignore`).
   The digests are printed to the job summary.

`.github/workflows/backend-deploy.yml` runs after Backend CI succeeds on `main` (or manually
via `workflow_dispatch` with an `image_tag`). It SSHes to the VPS and runs
`backend/scripts/deploy-vps.sh`, which:

1. Resolves the immutable digest for the pushed tag and rewrites `BACKEND_IMAGE` /
   `BACKEND_MIGRATE_IMAGE` in `.env` (keeping a timestamped `.env.bak.<ts>`).
2. Validates compose config, pulls by digest, runs the `migrate` service, then `up -d`.
3. Polls the API healthcheck; on timeout it restores the previous image refs, brings the
   stack back up, and exits non-zero.

Required GitHub secrets: `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS`,
`VPS_DEPLOY_PATH`, `GHCR_USER`, `GHCR_PULL_TOKEN`. Use a read-only deploy key for the VPS
and a GHCR token scoped to `read:packages`. The workflow and this doc never print secret
values; SSH host keys are pinned via `VPS_KNOWN_HOSTS` (no trust-on-first-use).

`deploy-vps.sh` runs on the VPS and expects `docker login ghcr.io` to already be done (the
workflow performs it immediately before). Its rollback restores the previous image digests;
it does **not** reverse database migrations.

## Secret scanning

- Config: `.gitleaks.toml` (allowlists documentation and placeholder values only).
- Local hooks: `.pre-commit-config.yaml` (gitleaks + hadolint). Enable with
  `pip install pre-commit && pre-commit install`.
- CI runs both gitleaks and trufflehog on every backend change.

Never commit `.env`, keystores, `google-services.json`, DB/Redis credentials, or VPS SSH
keys. If a secret is committed, treat it as compromised: rotate it first, then clean history.

## Rollback plan

Prerequisite: Prisma migrations are additive/backwards-compatible. A new release must not
drop or rename columns that the previous release still reads, otherwise the old image cannot
serve traffic against the migrated schema.

Fast rollback (previous image, same schema):

```bash
cd /opt/dsaialap/backend
cp .env.bak.<timestamp> .env          # restores the previous image digests
docker compose --env-file .env -f docker-compose.prod.yml pull
docker compose --env-file .env -f docker-compose.prod.yml up -d --remove-orphans
docker compose --env-file .env -f docker-compose.prod.yml ps
```

`deploy-vps.sh` performs exactly this automatically when the new container fails its
healthcheck. Manual rollback is for the case where the container is "healthy" but the release
is functionally bad.

If a migration is not backwards-compatible, roll back the database too:

1. Stop the API: `docker compose ... stop api`.
2. Restore the pre-release dump (see Backups and restore above).
3. Point `.env` at the previous image digests and `up -d`.

Verify rollback by comparing `docker inspect <api> --format '{{.Config.Image}}'` against the
digest you intended, and by re-running the smoke tests below.

## Smoke tests after deploy

```bash
curl -fsS https://dsaialap.banglarvoice24news.com/health
curl -fsS -H "x-dsaialap-key: sk_live_abc123" https://dsaialap.banglarvoice24news.com/api/b2b/v1/me
curl -fsS -X POST -H "x-dsaialap-key: sk_live_abc123" -H "Content-Type: application/json" -d '{"type":"ping","payload":{"hello":"world"}}' https://dsaialap.banglarvoice24news.com/api/b2b/v1/events
```

`socket.io/?EIO=4&transport=polling` must answer `0{"sid":"..."...}`.
