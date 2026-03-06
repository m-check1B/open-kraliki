#!/bin/bash
# turbo-pre-wave.example.sh — Example turbo pre-wave hook
# Copy this, customize the audit/triage commands, and point TURBO_PRE_WAVE_CMD at it.

set -eo pipefail

AUTOMATION_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$AUTOMATION_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_DIR}/.env}"
LOGDIR="${HOME}/logs/turbo-wave"
LOGFILE="${LOGDIR}/turbo-wave-$(date +%Y%m%d-%H%M).log"

mkdir -p "$LOGDIR"

if [ -f "$ENV_FILE" ]; then
  set +e
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set -e
fi

if [ "${AUTOMATION_ENABLED:-true}" = "false" ]; then
  echo "Automation is paused (AUTOMATION_ENABLED=false). Skipping turbo wave." | tee -a "$LOGFILE"
  exit 0
fi

if [ "${TURBO_MODE:-false}" != "true" ]; then
  echo "Turbo mode is off. Skipping turbo wave." | tee -a "$LOGFILE"
  exit 0
fi

HOUR=$(date +%H)
TURBO_ACTIVE_START="${TURBO_ACTIVE_START:-0}"
TURBO_ACTIVE_END="${TURBO_ACTIVE_END:-24}"
if [ "$HOUR" -lt "$TURBO_ACTIVE_START" ] || [ "$HOUR" -ge "$TURBO_ACTIVE_END" ]; then
  echo "Outside turbo pre-wave hours (${TURBO_ACTIVE_START}-${TURBO_ACTIVE_END}), skipping." | tee -a "$LOGFILE"
  exit 0
fi

echo "=== Turbo pre-wave: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
echo "Replace this example with your own audit and triage commands." | tee -a "$LOGFILE"
echo "Examples: product audit, issue import, Linear triage, plan injection." | tee -a "$LOGFILE"
echo "=== Turbo pre-wave complete: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
