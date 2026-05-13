#!/usr/bin/env bash
# Перезапуск user-unit приложения из deploy.sh (фон вебхука).
# Без XDG_RUNTIME_DIR / DBUS systemctl --user часто пишет "Failed to connect to bus" и ref не обновляется.
set -euo pipefail
uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
exec /usr/bin/systemctl --user restart catty-app.service
