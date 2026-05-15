#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
APP_ENV_FILE="${APP_ENV_FILE:-$APP_DIR/.env}"
APP_HOST="${APP_HOST:-0.0.0.0}"
APP_PORT="${APP_PORT:-8181}"
APP_PID_FILE="${APP_PID_FILE:-/tmp/catty-app.pid}"
APP_LOG_FILE="${APP_LOG_FILE:-/tmp/catty-app.log}"
UVICORN_BIN="${UVICORN_BIN:-$APP_DIR/.venv/bin/uvicorn}"

if [[ ! -x "$UVICORN_BIN" ]]; then
  echo "uvicorn not found at $UVICORN_BIN" >&2
  exit 1
fi

deploy_ref="${DEPLOY_REF:-NA}"
if [[ -f "$APP_ENV_FILE" ]]; then
  file_ref="$(grep -E '^DEPLOY_REF=' "$APP_ENV_FILE" | tail -n 1 | cut -d= -f2- || true)"
  if [[ -n "$file_ref" ]]; then
    deploy_ref="$file_ref"
  fi
fi

if [[ -f "$APP_PID_FILE" ]]; then
  old_pid="$(cat "$APP_PID_FILE")"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid"
    for _ in {1..50}; do
      if ! kill -0 "$old_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$old_pid" 2>/dev/null; then
      kill -9 "$old_pid"
    fi
  fi
fi

cd "$APP_DIR"
nohup env DEPLOY_REF="$deploy_ref" "$UVICORN_BIN" app.main:app --host "$APP_HOST" --port "$APP_PORT" > "$APP_LOG_FILE" 2>&1 &
new_pid="$!"
printf '%s\n' "$new_pid" > "$APP_PID_FILE"
sleep 1

if ! kill -0 "$new_pid" 2>/dev/null; then
  echo "Catty app failed to start; last log lines:" >&2
  tail -n 40 "$APP_LOG_FILE" >&2 || true
  exit 1
fi

echo "Catty app restarted on $APP_HOST:$APP_PORT with DEPLOY_REF=$deploy_ref (pid=$new_pid)"
