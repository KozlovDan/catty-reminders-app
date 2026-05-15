#!/usr/bin/env bash
set -Eeuo pipefail

BRANCH="${1:-}"
REQUESTED_SHA="${2:-}"

if [[ -z "$BRANCH" ]]; then
  echo "Usage: $0 <branch> [sha]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_REPO_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"

if [[ "$(uname -s)" == "Darwin" ]]; then
  DEFAULT_APP_DIR="$PROJECT_DIR"
  DEFAULT_APP_SERVICE="none"
  DEFAULT_APP_RESTART_COMMAND="$SCRIPT_DIR/restart-catty-app-macos.sh"
else
  DEFAULT_APP_DIR="/opt/catty/app"
  DEFAULT_APP_SERVICE="catty-app.service"
  DEFAULT_APP_RESTART_COMMAND=""
fi

REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"
APP_SERVICE="${APP_SERVICE:-$DEFAULT_APP_SERVICE}"
APP_RESTART_COMMAND="${APP_RESTART_COMMAND:-$DEFAULT_APP_RESTART_COMMAND}"
APP_ENV_FILE="${APP_ENV_FILE:-$APP_DIR/.env}"
LOCK_FILE="${LOCK_FILE:-/tmp/catty-deploy.lock}"
LOCK_DIR="${LOCK_DIR:-/tmp/catty-deploy.lockdir}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RUN_TESTS="${RUN_TESTS:-1}"
TEST_COMMAND="${TEST_COMMAND:-.venv/bin/python -m pytest tests/test_unit.py}"

if [[ -z "$REPO_URL" ]]; then
  echo "REPO_URL is not set and could not be read from git remote origin" >&2
  exit 2
fi

# Неинтерактивный git (вебхук без TTY): не ждать пароль SSH, не зависать на host key.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new}"

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
git -C "$APP_DIR" reset --hard "origin/$BRANCH"

# GitHub sends the exact post-receive commit in "after". CI compares deployref to that SHA.
# origin/$BRANCH can rarely lag "after" right after fetch; align when the object is available.
if [[ -n "$REQUESTED_SHA" ]]; then
  if ! git -C "$APP_DIR" cat-file -e "$REQUESTED_SHA^{commit}" 2>/dev/null; then
    git -C "$APP_DIR" fetch origin "refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null || true
  fi
  if git -C "$APP_DIR" cat-file -e "$REQUESTED_SHA^{commit}" 2>/dev/null; then
    git -C "$APP_DIR" reset --hard "$REQUESTED_SHA"
  else
    echo "WARNING: requested SHA $REQUESTED_SHA not in repo after fetch; using $(git -C "$APP_DIR" rev-parse HEAD)" >&2
  fi
fi

DEPLOYED_SHA="$(git -C "$APP_DIR" rev-parse HEAD)"
if [[ -n "$REQUESTED_SHA" && "$DEPLOYED_SHA" != "$REQUESTED_SHA" ]]; then
  echo "WARNING: deployed HEAD $DEPLOYED_SHA still differs from webhook after=$REQUESTED_SHA" >&2
fi

if [[ ! -x "$APP_DIR/.venv/bin/python" ]]; then
  "$PYTHON_BIN" -m venv "$APP_DIR/.venv"
fi

"$APP_DIR/.venv/bin/python" -m pip install --upgrade pip
"$APP_DIR/.venv/bin/python" -m pip install -r "$APP_DIR/requirements.txt"

if [[ "$RUN_TESTS" != "0" ]]; then
  (
    cd "$APP_DIR"
    bash -lc "$TEST_COMMAND"
  )
fi

touch "$APP_ENV_FILE"
if grep -q '^DEPLOY_REF=' "$APP_ENV_FILE"; then
  sed -i.bak "s/^DEPLOY_REF=.*/DEPLOY_REF=$DEPLOYED_SHA/" "$APP_ENV_FILE"
  rm -f "$APP_ENV_FILE.bak"
else
  printf 'DEPLOY_REF=%s\n' "$DEPLOYED_SHA" >> "$APP_ENV_FILE"
fi

if [[ -n "$APP_RESTART_COMMAND" ]]; then
  bash -lc "$APP_RESTART_COMMAND"
elif [[ -z "$APP_SERVICE" || "$APP_SERVICE" == "none" ]]; then
  echo "Skipping service restart"
elif [[ "$(id -u)" -eq 0 ]]; then
  systemctl restart "$APP_SERVICE"
else
  sudo systemctl restart "$APP_SERVICE"
fi

echo "Deployment completed at $DEPLOYED_SHA"
