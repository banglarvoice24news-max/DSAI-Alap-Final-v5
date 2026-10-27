#!/usr/bin/env bash
#
# Zero-downtime-ish deploy + automatic rollback for the Nexus backend.
# This script runs ON THE VPS. It is invoked by
# .github/workflows/backend-deploy.yml over SSH.
#
# Required environment variables:
#   IMAGE_REPO            e.g. ghcr.io/owner/repo/backend
#   IMAGE_TAG             immutable tag, e.g. sha-<commit>
#
# Optional:
#   COMPOSE_FILE          default: docker-compose.prod.yml
#   ENV_FILE              default: .env
#   API_HEALTH_TIMEOUT    seconds to wait for health, default: 150
#
# Preconditions:
#   - `docker login ghcr.io` has already succeeded on this host.
#   - `.env` exists and contains POSTGRES_*/REDIS_PASSWORD plus app secrets.
#
# Rollback model:
#   - The previous BACKEND_IMAGE/BACKEND_MIGRATE_IMAGE values are restored on
#     failure. This only works if the new release did not apply an
#     irreversible, backwards-incompatible migration. Prisma migrations are
#     expected to be additive/backwards-compatible (see DEPLOY.md).
#   - A timestamped copy of the previous `.env` is kept on the host.

set -euo pipefail

: "${IMAGE_REPO:?IMAGE_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-.env}"
API_HEALTH_TIMEOUT="${API_HEALTH_TIMEOUT:-150}"

compose() { docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

get_env() {
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

set_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v} {print}' "$ENV_FILE" >"${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >>"$ENV_FILE"
  fi
}

resolve_digest() {
  local ref="$1"
  docker pull "$ref" >/dev/null
  docker inspect --format '{{index .RepoDigests 0}}' "$ref"
}

echo "[deploy] tag=${IMAGE_TAG}"
RUNTIME_DIGEST="$(resolve_digest "${IMAGE_REPO}:${IMAGE_TAG}")"
MIGRATE_DIGEST="$(resolve_digest "${IMAGE_REPO}:${IMAGE_TAG}-migrate")"
echo "[deploy] runtime=${RUNTIME_DIGEST}"
echo "[deploy] migrate=${MIGRATE_DIGEST}"

PREV_RUNTIME="$(get_env BACKEND_IMAGE)"
PREV_MIGRATE="$(get_env BACKEND_MIGRATE_IMAGE)"
ENV_BACKUP="${ENV_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$ENV_FILE" "$ENV_BACKUP"
echo "[deploy] env backup: ${ENV_BACKUP}"

set_env BACKEND_IMAGE "$RUNTIME_DIGEST"
set_env BACKEND_MIGRATE_IMAGE "$MIGRATE_DIGEST"

echo "[deploy] validating compose config"
compose config >/dev/null

echo "[deploy] pulling images"
compose pull

echo "[deploy] applying migrations"
compose run --rm migrate

echo "[deploy] starting services"
compose up -d --remove-orphans

rollback() {
  echo "[deploy] ROLLBACK: restoring previous image refs" >&2
  [ -n "$PREV_RUNTIME" ] && set_env BACKEND_IMAGE "$PREV_RUNTIME"
  [ -n "$PREV_MIGRATE" ] && set_env BACKEND_MIGRATE_IMAGE "$PREV_MIGRATE"
  compose up -d --remove-orphans || true
  echo "[deploy] rollback finished; previous env preserved at ${ENV_BACKUP}" >&2
}

echo "[deploy] waiting up to ${API_HEALTH_TIMEOUT}s for api to become healthy"
deadline=$(( $(date +%s) + API_HEALTH_TIMEOUT ))
while :; do
  cid="$(compose ps -q api || true)"
  status="unknown"
  if [ -n "$cid" ]; then
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
  fi
  if [ "$status" = "healthy" ]; then
    echo "[deploy] api healthy"
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "[deploy] ERROR: api did not become healthy (last status: ${status})" >&2
    compose logs --no-color --tail=50 api >&2 || true
    rollback
    exit 1
  fi
  sleep 5
done

echo "[deploy] success: ${RUNTIME_DIGEST}"
