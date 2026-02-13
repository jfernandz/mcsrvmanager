#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:?usage: mc-tmux-stop.sh <instance>}"

if [[ -f /etc/default/mc/common.env ]]; then
  # shellcheck disable=SC1091
  source /etc/default/mc/common.env
fi
if [[ -f "/etc/default/mc/${INSTANCE}.env" ]]; then
  # shellcheck disable=SC1090
  source "/etc/default/mc/${INSTANCE}.env"
fi

MC_TMUX_SESSION="${MC_TMUX_SESSION:-mc-${INSTANCE}}"
MC_STOP_TIMEOUT="${MC_STOP_TIMEOUT:-120}"
MC_STOP_COMMAND="${MC_STOP_COMMAND:-stop}"

if ! tmux has-session -t "$MC_TMUX_SESSION" 2>/dev/null; then
  exit 0
fi

tmux send-keys -t "$MC_TMUX_SESSION" "$MC_STOP_COMMAND" C-m

for ((i=0; i<MC_STOP_TIMEOUT; i++)); do
  if ! tmux has-session -t "$MC_TMUX_SESSION" 2>/dev/null; then
    exit 0
  fi
  sleep 1
done

# Last resort to avoid hanging stop forever.
tmux kill-session -t "$MC_TMUX_SESSION"
