#!/usr/bin/env bash
set -Eeuo pipefail

BRANCH="${1:-}"
REQUESTED_SHA="${2:-}"

if [[ -z "$BRANCH" ]]; then
  echo "Usage: $0 <branch> [sha]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_URL="$(git -C "$SCRIPT_DIR/.." remote get-url origin 2>/dev/null || true)"

REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
APP_DIR="${APP_DIR:-/opt/catty/app}"
IMAGE="${IMAGE:-}"
CONTAINER_NAME="${CONTAINER_NAME:-catty-reminders-app}"
CONTAINER_PORT="${CONTAINER_PORT:-8181}"
HOST_PORT="${HOST_PORT:-8181}"
DOCKER_BIN="${DOCKER_BIN:-}"
COMPOSE_BIN="${COMPOSE_BIN:-}"
COMPOSE_MODE=""
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
LOCK_FILE="${LOCK_FILE:-/tmp/catty-deploy.lock}"
LOCK_DIR="${LOCK_DIR:-/tmp/catty-deploy.lockdir}"

if [[ -z "$REPO_URL" ]]; then
  echo "REPO_URL is not set and could not be read from git remote origin" >&2
  exit 2
fi

if [[ -z "$IMAGE" ]]; then
  echo "IMAGE is required for Docker deployment" >&2
  exit 2
fi

run_compose_deploy() {
  local docker_candidates=()
  local compose_candidates=()
  local candidate
  local candidate_realpath

  export IMAGE
  export DEPLOY_REF="${REQUESTED_SHA:-NA}"
  export HOST_PORT
  export APP_PULL_POLICY="${APP_PULL_POLICY:-always}"

  if [[ -n "$DOCKER_BIN" ]]; then
    docker_candidates+=("$DOCKER_BIN")
  fi
  docker_candidates+=(
    "/Applications/Docker.app/Contents/Resources/bin/docker"
    "/opt/homebrew/bin/docker"
    "/usr/local/bin/docker"
  )
  if command -v docker >/dev/null 2>&1; then
    docker_candidates+=("$(command -v docker)")
  fi

  DOCKER_BIN=""
  for candidate in "${docker_candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      if [[ -z "$DOCKER_BIN" ]]; then
        DOCKER_BIN="$candidate"
      fi
      if "$candidate" compose -f "$APP_DIR/$COMPOSE_FILE" config >/dev/null 2>&1; then
        DOCKER_BIN="$candidate"
        COMPOSE_MODE="plugin"
        break
      fi
    fi
  done

  if [[ -z "$DOCKER_BIN" ]]; then
    echo "docker command not found" >&2
    exit 1
  fi

  export PATH="$(dirname "$DOCKER_BIN"):$PATH"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-/tmp/catty-docker-config}"
  mkdir -p "$DOCKER_CONFIG"

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN" | "$DOCKER_BIN" login ghcr.io -u "${GITHUB_ACTOR:-github-actions}" --password-stdin
  fi

  if [[ -z "$COMPOSE_MODE" ]]; then
    if [[ -n "$COMPOSE_BIN" ]]; then
      compose_candidates+=("$COMPOSE_BIN")
    fi
    compose_candidates+=(
      "/opt/homebrew/bin/docker-compose"
      "/usr/local/bin/docker-compose"
    )
    if command -v docker-compose >/dev/null 2>&1; then
      compose_candidates+=("$(command -v docker-compose)")
    fi

    COMPOSE_BIN=""
    for candidate in "${compose_candidates[@]}"; do
      if [[ -x "$candidate" ]]; then
        candidate_realpath="$(realpath "$candidate" 2>/dev/null || echo "$candidate")"
        if [[ "$(basename "$candidate_realpath")" == "docker" ]]; then
          continue
        fi
        if "$candidate" -f "$APP_DIR/$COMPOSE_FILE" config >/dev/null 2>&1; then
          COMPOSE_BIN="$candidate"
          COMPOSE_MODE="standalone"
          break
        fi
      fi
    done
  fi

  if [[ -z "$COMPOSE_MODE" && "$DOCKER_BIN" == "/usr/local/bin/docker" && -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
    DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
    if "$DOCKER_BIN" compose -f "$APP_DIR/$COMPOSE_FILE" config >/dev/null 2>&1; then
      COMPOSE_MODE="plugin"
    fi
  fi

  if [[ -z "$COMPOSE_MODE" ]]; then
    echo "docker compose command not found; install Docker Compose plugin or docker-compose" >&2
    exit 1
  fi

  if [[ "$COMPOSE_MODE" == "plugin" ]]; then
    echo "Using Docker Compose plugin: $DOCKER_BIN compose"
  else
    echo "Using standalone Docker Compose: $COMPOSE_BIN"
  fi

  "$DOCKER_BIN" stop "$CONTAINER_NAME" 2>/dev/null || true
  "$DOCKER_BIN" rm "$CONTAINER_NAME" 2>/dev/null || true

  if command -v lsof >/dev/null 2>&1; then
    for pid in $(lsof -tiTCP:"$HOST_PORT" -sTCP:LISTEN 2>/dev/null || true); do
      process_name="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
      case "$process_name" in
        *Docker*|*docker*|*OrbStack*)
          continue
          ;;
      esac
      echo "Stopping process $pid ($process_name) listening on port $HOST_PORT"
      kill "$pid" 2>/dev/null || true
    done
    sleep 1
  fi

  if [[ "$COMPOSE_MODE" == "plugin" ]]; then
    "$DOCKER_BIN" compose -f "$APP_DIR/$COMPOSE_FILE" pull
    "$DOCKER_BIN" compose -f "$APP_DIR/$COMPOSE_FILE" up -d --remove-orphans
  else
    "$COMPOSE_BIN" -f "$APP_DIR/$COMPOSE_FILE" pull
    "$COMPOSE_BIN" -f "$APP_DIR/$COMPOSE_FILE" up -d --remove-orphans
  fi
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

echo "Deploying branch '$BRANCH' from '$REPO_URL' into '$APP_DIR'"

if [[ ! -d "$APP_DIR/.git" ]]; then
  mkdir -p "$(dirname "$APP_DIR")"
  git clone "$REPO_URL" "$APP_DIR"
fi

git -C "$APP_DIR" fetch --prune origin '+refs/heads/*:refs/remotes/origin/*'
git -C "$APP_DIR" checkout -B "$BRANCH" "origin/$BRANCH"

if [[ -n "$REQUESTED_SHA" ]]; then
  git -C "$APP_DIR" reset --hard "$REQUESTED_SHA"
else
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
fi

DEPLOYED_SHA="$(git -C "$APP_DIR" rev-parse HEAD)"
if [[ -n "$REQUESTED_SHA" && "$DEPLOYED_SHA" != "$REQUESTED_SHA" ]]; then
  echo "Requested SHA $REQUESTED_SHA, deployed SHA $DEPLOYED_SHA" >&2
  exit 1
fi

run_compose_deploy

echo "Docker Compose deployment completed at $DEPLOYED_SHA with $IMAGE"
