#!/usr/bin/env bash
set -u

PORT="${JARVIS_GATEWAY_PORT:-8765}"
TIMEOUT_SECONDS="${JARVIS_STOP_TIMEOUT:-5}"

log() {
  printf '[stop-jarvis] %s\n' "$*"
}

unique_pids() {
  awk 'NF && !seen[$1]++ { print $1 }'
}

is_running() {
  kill -0 "$1" 2>/dev/null
}

terminate_pids() {
  label="$1"
  pids="$2"

  if [ -z "$pids" ]; then
    log "No ${label} processes found."
    return 0
  fi

  log "Stopping ${label}: $(printf '%s' "$pids" | tr '\n' ' ')"
  printf '%s\n' "$pids" | while IFS= read -r pid; do
    [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
  done

  deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    remaining=""
    for pid in $pids; do
      if is_running "$pid"; then
        remaining="${remaining}${pid}
"
      fi
    done
    [ -z "$remaining" ] && return 0
    sleep 0.25
  done

  remaining=""
  for pid in $pids; do
    if is_running "$pid"; then
      remaining="${remaining}${pid}
"
    fi
  done

  if [ -n "$remaining" ]; then
    log "Force-stopping ${label}: $(printf '%s' "$remaining" | tr '\n' ' ')"
    printf '%s\n' "$remaining" | while IFS= read -r pid; do
      [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null || true
    done
  fi
}

main() {
  jarvis_pids="$(pgrep -x Jarvis 2>/dev/null | unique_pids || true)"
  gateway_pids="$(pgrep -f '[P]ython/gateway.py|[g]ateway.py' 2>/dev/null | unique_pids || true)"
  port_pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | unique_pids || true)"

  terminate_pids "Jarvis app" "$jarvis_pids"
  terminate_pids "Python gateway" "$gateway_pids"
  terminate_pids "listeners on TCP port ${PORT}" "$port_pids"

  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    log "Port ${PORT} is still in use."
    exit 1
  fi

  log "Stopped Jarvis processes."
}

main "$@"
