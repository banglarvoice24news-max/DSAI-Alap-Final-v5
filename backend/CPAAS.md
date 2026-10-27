# CPaaS / telecom layer — operator runbook

Scope: the isolated `src/services/telecom/*` + `src/modules/cpaas/*` subsystem on the Nexus
`backend`. It adds a JSON-first voice interpreter, a FreeSWITCH ESL client, a jambonz BYOC
provider, a BD-aware SMS gateway (Jasmin + optional personal GSM relay), consent/CDR compliance
controls and a small `/api/cpaas` HTTP API.

The layer is **off by default** and opt-in via `ENABLE_CPAAS_LAYER=true`.

## 1. Enabling

1. Apply the additive migration (creates `api_keys`, `cdrs` + enums; touches nothing else):

   ```bash
   cd backend
   npx prisma migrate deploy
   ```

2. Set the CPaaS env block in `.env` (see `.env.example`). Minimum to boot the layer:

   ```bash
   ENABLE_CPAAS_LAYER=true
   CPAAS_REDIS_PREFIX=cpaas:
   CPAAS_CALL_EVENTS_CHANNEL=call:events:cpaas
   ```

   Add provider settings only for the paths you actually use:

   - FreeSWITCH outbound legs: `FS_ESL_HOST`, `FS_ESL_PORT`, `FS_ESL_PASSWORD` (required to
     start ESL), `FS_TRUNK_NAME`, `FS_GSM_GATEWAY`, `FS_DIALPLAN_CONTEXT`.
   - Licensed voice (jambonz BYOC): `JAMBONZ_API_BASE_URL`, `JAMBONZ_ACCOUNT_SID`,
     `JAMBONZ_API_TOKEN`, `JAMBONZ_CALLBACK_BASE_URL` (public HTTPS URL for webhooks), optional
     `JAMBONZ_CARRIER` and `JAMBONZ_WEBHOOK_*`.
   - Licensed SMS (Jasmin): `JASMIN_HTTP_URL`, `JASMIN_HTTP_USERNAME`, `JASMIN_HTTP_PASSWORD`.
   - Personal GSM relay (§5, owner-only): `ANDROID_GSM_BASE_URL`, `ANDROID_GSM_TOKEN`,
     `ANDROID_GSM_DEVICE_ID`.

3. Restart the API. On boot with the layer enabled, `index.ts` starts the call-event consumer
   (its own Redis connection, channel `call:events:cpaas`) and the FreeSWITCH ESL client
   (exponential reconnect). The ESL client is also started lazily by the first GSM call.

4. Issue a CPaaS API key (SHA-256 hashed in `api_keys`; the raw key is shown once) and use it as
   `x-dsaialap-key` on every business endpoint.

## 2. API surface

Business endpoints (require the API key):

- `POST /api/cpaas/calls` — create a call leg. Body: `{ to, from?, gateway?: GSM|JAMBONZ,
  lowBitrate?, meshHops?, consent?, clientRef? }`. The §5 policy service always re-decides the
  gateway; it never trusts the client request alone.
- `POST /api/cpaas/sms` — send an SMS through the BD failover router. Body:
  `{ to, body, from?, consent? }`.
- `GET /api/cpaas/logs?gatewayType=&status=&to=&from=&since=&until=&limit=&offset=` — low-detail
  CDR audit trail (no signalling content).
- `GET /api/cpaas/calls/:id/status` — live Redis status, then CDR fallback.

Provider webhooks (authenticated by their own basic-auth/signature, NOT the API key):

- `POST /api/cpaas/webhook/call` — jambonz application-leg entry point (returns an empty verb
  document while legs are pure bridges).
- `POST /api/cpaas/webhook/call-status` — feeds terminal state into the CDR trail.
- `POST /api/cpaas/webhook/jasmin/dlr` — DLR receipts (acked with `ACK/Jasmin`).
- `POST /api/cpaas/webhook/validate` — operator auth self-check.

## 3. Compose scaffold

`docker-compose.cpaas.yml` is a parameterized scaffold for the co-located media/gateway stack.
Image tags are deliberately left as `*_IMAGE` variables: pin them from each upstream project's
release notes before first use (FreeSWITCH 1.11.x, jambonz 0.x, Jasmin 0.10.x). It provisions a
separate Redis instance so the CPaaS channels/rate-limit keys never collide with the app Redis.

```bash
cd backend
FS_IMAGE=your/freeswitch:1.11 REDIS_IMAGE=redis:7-alpine \
  docker compose -f docker-compose.cpaas.yml up -d
```

The stack is intentionally independent of `docker-compose.yml`; the API container stays on the
main compose network and reaches media containers over the host or a shared network you extend.

## 4. Rollback (remove the layer)

1. Disable the layer: set `ENABLE_CPAAS_LAYER=false` (default) in `.env` and remove/blank the
   provider keys. Restart. The `/api/cpaas` routes are not mounted and no telecom process starts.
2. Leave the additive migration applied: `api_keys` and `cdrs` are inert when the layer is off and
   dropping them is destructive to the audit trail. If you must remove them, the migration
   `0002_cpaas_additive` has a documented inverse:

   ```sql
   DROP TABLE IF EXISTS "cdrs";
   DROP TABLE IF EXISTS "api_keys";
   DROP TYPE IF EXISTS "CdrStatus";
   DROP TYPE IF EXISTS "CdrDirection";
   DROP TYPE IF EXISTS "GatewayType";
   ```

   Run it only after exporting any CDR rows you are required to retain. There is no code path that
   reuses the `GatewayType`/`CdrStatus` enums, so removing them cannot affect the legacy modules.

## 5. Regulatory notes (Bangladesh, live BTRC risk)

- The zero-cost GSM path (Android relay + FreeSWITCH GSM leg) is restricted to **genuinely
  personal, on-net traffic originated by the SIM's own owner** with explicit consent
  (`consent.service.ts`, `gsm-policy.service.ts`). Commercial/B2B and international traffic is
  routed through licensed IGW/ICX (jambonz/Jasmin) or refused.
- Consent and per-device caps are compliance controls only. Nothing in this subsystem shapes call
  timing, volume or patterns to evade BTRC pattern detection — do not add such logic.
- CDR rows are append-only (unique `callSid`, `createMany skipDuplicates`, never updated). Consent
  audit entries are RPUSH-append-only in Redis. Detection systems must never read consent flags.
- The `lowBitrate` flag is a documented divergence: it forces `opus_bitrate=20000` + SILK on the
  FreeSWITCH leg only and is a no-op on jambonz legs.

## 6. Tests

```bash
cd backend
npm test          # voice interpreter unit tests + ESL mocked-integration tests
npm run typecheck
```
