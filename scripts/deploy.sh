#!/usr/bin/env bash
set -Eeuo pipefail

BRANCH="${1:-}"
REQUESTED_SHA="${2:-}"

if [[ -z "$BRANCH" ]]; then
  echo "Usage: $0 <branch> [sha]" >&2
  exit 2
fi

APP_DIR="${APP_DIR:-/opt/catty/app}"
IMAGE="${IMAGE:-}"
CONTAINER_NAME="${CONTAINER_NAME:-catty-reminders-app}"
DB_CONTAINER_NAME="${DB_CONTAINER_NAME:-catty-reminders-db-1}"
DOCKER_BIN="${DOCKER_BIN:-}"
DOCKER_COMPOSE_BIN="${DOCKER_COMPOSE_BIN:-}"
COMPOSE_FILE_PATH="${COMPOSE_FILE_PATH:-$APP_DIR/docker-compose.yaml}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-catty-reminders}"
LOCK_FILE="${LOCK_FILE:-/tmp/catty-deploy.lock}"
LOCK_DIR="${LOCK_DIR:-/tmp/catty-deploy.lockdir}"

if [[ -z "$IMAGE" ]]; then
  echo "IMAGE is required for Docker deployment" >&2
  exit 2
fi

run_compose_deploy() {
  local compose_cmd=()

  if [[ -z "$DOCKER_BIN" ]]; then
    DOCKER_BIN="$(command -v docker || true)"
  fi
  if [[ -z "$DOCKER_BIN" && -x /opt/homebrew/bin/docker ]]; then
    DOCKER_BIN="/opt/homebrew/bin/docker"
  fi
  if [[ -z "$DOCKER_BIN" && -x /usr/local/bin/docker ]]; then
    DOCKER_BIN="/usr/local/bin/docker"
  fi
  if [[ -z "$DOCKER_BIN" ]]; then
    echo "docker command not found" >&2
    exit 1
  fi

  export PATH="$(dirname "$DOCKER_BIN"):$PATH"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-/tmp/catty-docker-config}"
  mkdir -p "$DOCKER_CONFIG"

  if [[ -n "$DOCKER_COMPOSE_BIN" ]]; then
    compose_cmd=("$DOCKER_COMPOSE_BIN")
  elif "$DOCKER_BIN" compose version >/dev/null 2>&1; then
    compose_cmd=("$DOCKER_BIN" "compose")
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=("$(command -v docker-compose)")
  elif [[ -x /opt/homebrew/bin/docker-compose ]]; then
    compose_cmd=("/opt/homebrew/bin/docker-compose")
  elif [[ -x /usr/local/bin/docker-compose ]]; then
    compose_cmd=("/usr/local/bin/docker-compose")
  else
    echo "docker compose command not found" >&2
    exit 1
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN" | "$DOCKER_BIN" login ghcr.io -u "${GITHUB_ACTOR:-github-actions}" --password-stdin
  fi

  if [[ ! -f "$COMPOSE_FILE_PATH" ]]; then
    echo "docker compose file not found at $COMPOSE_FILE_PATH" >&2
    exit 1
  fi

  "$DOCKER_BIN" stop "$CONTAINER_NAME" 2>/dev/null || true
  "$DOCKER_BIN" rm "$CONTAINER_NAME" 2>/dev/null || true
  "$DOCKER_BIN" stop "$DB_CONTAINER_NAME" 2>/dev/null || true
  "$DOCKER_BIN" rm "$DB_CONTAINER_NAME" 2>/dev/null || true

  export IMAGE
  export APP_PULL_POLICY="${APP_PULL_POLICY:-always}"

  echo "Using Docker Compose command: ${compose_cmd[*]}"
  "${compose_cmd[@]}" -f "$COMPOSE_FILE_PATH" --project-name "$COMPOSE_PROJECT_NAME" pull
  "${compose_cmd[@]}" -f "$COMPOSE_FILE_PATH" --project-name "$COMPOSE_PROJECT_NAME" up -d --remove-orphans
  "$DOCKER_BIN" image prune -af >/dev/null 2>&1 || true
}

mkdir -p "$(dirname "$LOCK_FILE")"
if command -v flock >/dev/null 2>&1; then
  exec 200>"$LOCK_FILE"
  flock -x 200
else
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    sleep 1
  done
  trap 'rmdir "$LOCK_DIR"' EXIT
fi

echo "Deploying image '$IMAGE' for branch '$BRANCH' using compose file '$COMPOSE_FILE_PATH'"

run_compose_deploy

echo "Docker Compose deployment completed for ${REQUESTED_SHA:-unknown} with $IMAGE"
