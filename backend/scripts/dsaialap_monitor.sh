#!/usr/bin/env bash
set -u

COMPOSE_FILE="${COMPOSE_FILE:-/opt/dsaialap/backend/docker-compose.prod.yml}"
API_CONTAINER="${API_CONTAINER:-backend-api-1}"
MEM_LIMIT_MB="${MEM_LIMIT_MB:-450}"
HEALTH_URL="${HEALTH_URL:-https://dsaialap.banglarvoice24news.com/health}"
SOCKET_URL="${SOCKET_URL:-https://dsaialap.banglarvoice24news.com/socket.io/?EIO=4&transport=polling}"
LOG="${LOG:-/var/log/dsaialap_monitor.log}"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() {
  if ! printf '[%s] %s\n' "$(ts)" "$*" >> "$LOG" 2>/dev/null; then
    printf '[%s] %s\n' "$(ts)" "$*" >&2
  fi
}

restart_api() {
  log "restarting $API_CONTAINER"
  if docker compose -f "$COMPOSE_FILE" restart api >/dev/null 2>&1 || docker restart "$API_CONTAINER" >/dev/null 2>&1; then
    log "restart accepted for $API_CONTAINER"
    return 0
  fi
  log "ERROR: restart failed for $API_CONTAINER (bad compose path or container name)"
  return 1
}

rss_mb() {
  local raw mem unit
  raw=$(docker stats --no-stream --format "{{.MemUsage}}" "$API_CONTAINER" 2>/dev/null | awk '{print $1}')
  if [ -z "$raw" ]; then
    echo 0
    return 0
  fi
  mem="${raw%[A-Za-z]*}"
  unit="${raw##*[0-9.]}"
  case "$unit" in
    GiB | GB) awk -v v="$mem" 'BEGIN{printf "%d", v * 1024}' ;;
    KiB | KB) awk -v v="$mem" 'BEGIN{printf "%d", v / 1024}' ;;
    *) awk -v v="$mem" 'BEGIN{printf "%d", v}' ;;
  esac
}

health_ok() {
  curl -fsS --max-time 5 "$HEALTH_URL" 2>/dev/null | grep -q '"ok":true'
}

socket_ok() {
  local body
  body=$(curl -fsS --max-time 5 "$SOCKET_URL" 2>/dev/null) || return 1
  printf '%s' "$body" | grep -q '"sid"'
}

mem=$(rss_mb)
log "check mem=${mem}MB"

if [ "${mem:-0}" -ge "$MEM_LIMIT_MB" ]; then
  log "memory ${mem}MB >= ${MEM_LIMIT_MB}MB, restarting"
  restart_api || exit 1
  exit 0
fi

if ! health_ok; then
  log "health check failed, restarting"
  restart_api || exit 1
  exit 0
fi

if ! socket_ok; then
  log "socket.io handshake failed, restarting"
  restart_api || exit 1
  exit 0
fi

log "ok"
exit 0
