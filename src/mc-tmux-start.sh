#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:?usage: mc-tmux-start.sh <instance>}"

if [[ -f /etc/default/mc/common.env ]]; then
  # shellcheck disable=SC1091
  source /etc/default/mc/common.env
fi
if [[ -f "/etc/default/mc/${INSTANCE}.env" ]]; then
  # shellcheck disable=SC1090
  source "/etc/default/mc/${INSTANCE}.env"
fi

: "${MC_SERVER_DIR:?MC_SERVER_DIR is required}"
: "${MC_JAR_NAME:?MC_JAR_NAME is required}"

MC_JAVA_BIN="${MC_JAVA_BIN:-/usr/bin/java}"
MC_XMX="${MC_XMX:-4G}"
MC_XMS="${MC_XMS:-4G}"
MC_TMUX_SESSION="${MC_TMUX_SESSION:-mc-${INSTANCE}}"

if tmux has-session -t "$MC_TMUX_SESSION" 2>/dev/null; then
  exit 0
fi

printf -v LAUNCH_CMD 'cd %q && exec %q -Xmx%s -Xms%s -jar %q nogui' \
  "$MC_SERVER_DIR" "$MC_JAVA_BIN" "$MC_XMX" "$MC_XMS" "$MC_JAR_NAME"

tmux new-session -d -s "$MC_TMUX_SESSION" "$LAUNCH_CMD"
