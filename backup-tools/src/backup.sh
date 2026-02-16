#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${1:?usage: backup.sh <service-backup.config>}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "config not found: $CONFIG_PATH" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_PATH"

SERVICE_NAME="${SERVICE_NAME:-}"
BACKUP_DIR="${BACKUP_DIR:?BACKUP_DIR is required}"
BACKUP_LEVEL="${BACKUP_LEVEL:-3}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_PREFIX="${BACKUP_PREFIX:-${SERVICE_NAME%.service}}"
BACKUP_OWNER="${BACKUP_OWNER:-}"
STOP_WAIT_SECONDS="${STOP_WAIT_SECONDS:-300}"
RESTART_AFTER_BACKUP="${RESTART_AFTER_BACKUP:-true}"

declare -p BACKUP_DIRS >/dev/null 2>&1 || BACKUP_DIRS=()
declare -p EXCLUDE_PATTERNS >/dev/null 2>&1 || EXCLUDE_PATTERNS=()

if [[ "${#BACKUP_DIRS[@]}" -eq 0 ]]; then
  echo "BACKUP_DIRS must include at least one directory" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

sanitize_prefix() {
  local value="$1"
  printf '%s' "$value" | tr '/:@ ' '____' | tr -cd '[:alnum:]_.-'
}

BACKUP_PREFIX="$(sanitize_prefix "$BACKUP_PREFIX")"
STAMP="$(date +%F_%H-%M-%S)"
ARCHIVE="$BACKUP_DIR/${BACKUP_PREFIX}_$STAMP.7z"

if [[ -n "$SERVICE_NAME" ]]; then
  service_was_active=false
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    service_was_active=true
  fi

  systemctl stop "$SERVICE_NAME"

  restart_service() {
    if [[ "$RESTART_AFTER_BACKUP" != "true" ]]; then
      return
    fi

    if [[ "$service_was_active" == "true" ]]; then
      systemctl start "$SERVICE_NAME"
    fi
  }
  trap restart_service EXIT

  max_checks=$((STOP_WAIT_SECONDS / 2))
  if (( max_checks < 1 )); then
    max_checks=1
  fi

  for ((i=0; i<max_checks; i++)); do
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
      break
    fi
    sleep 2
  done

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "timed out waiting for $SERVICE_NAME to stop" >&2
    exit 1
  fi
fi

EXCLUDES=()
if [[ "${#EXCLUDE_PATTERNS[@]}" -gt 0 ]]; then
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ "$pattern" == -x* ]]; then
      echo "exclude patterns must be plain paths/globs, not 7z switches: $pattern" >&2
      exit 1
    fi
    EXCLUDES+=("-xr!$pattern")
  done
fi

7z a -t7z -mx="$BACKUP_LEVEL" "$ARCHIVE" "${BACKUP_DIRS[@]}" "${EXCLUDES[@]}"

if [[ -n "$BACKUP_OWNER" ]]; then
  chown "$BACKUP_OWNER" "$ARCHIVE"
fi

find "$BACKUP_DIR" -type f -name "${BACKUP_PREFIX}_*.7z" -mtime +"$BACKUP_RETENTION_DAYS" -delete
