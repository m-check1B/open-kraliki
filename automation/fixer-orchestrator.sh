#!/bin/bash
# fixer-orchestrator.sh — Runs all 4 coding fixers IN PARALLEL
# Each fixer works on non-overlapping issues (slot modulo 4).
# Git push conflicts are handled by retry logic inside each fixer.
#
# NOTE: NEVER hardcode model names (e.g. "Opus", "Sonnet", "o4-mini", "GLM-4.7").
#       CLIs manage their own models internally. Reference CLIs only by name.
#
# LaunchAgent: com.automation.fixer-orchestrator
# Schedule: Every 15 minutes
# Parallel: Claude Fixer (slot 0) | Codex Fixer (slot 1) | Opencode Fixer (slot 2)

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────
AUTOMATION_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$(cd "$AUTOMATION_DIR/.." && pwd)/.env}"
LOGDIR="${HOME}/logs/fixer-orchestrator"
LOCKFILE="${LOGDIR}/orchestrator.lock"
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%SZ)"
LOGFILE="${LOGDIR}/orchestrator-$(date +%Y%m%d-%H%M).log"

# Source env vars (launchd doesn't inherit shell env)
if [ -f "$ENV_FILE" ]; then
  set +e
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set -e
fi
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"

mkdir -p "$LOGDIR"

# Rotate logs older than retention period
find "$LOGDIR" -name 'orchestrator-*.log' -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true

echo "=== Fixer Orchestrator: ${TIMESTAMP} ===" | tee "$LOGFILE"

# ── Lock file ────────────────────────────────────────────────────
if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Another orchestrator is running (PID ${LOCK_PID}), skipping." | tee -a "$LOGFILE"
    exit 0
  else
    echo "Stale lock file found, removing." | tee -a "$LOGFILE"
    rm -f "$LOCKFILE"
  fi
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# ── Fixer definitions ───────────────────────────────────────────
FIXERS=("claude" "codex" "opencode")
FIXER_PIDS=()
FIXER_LOGS=()
FIXER_EXITS=()

# ── Per-fixer log files ─────────────────────────────────────────
for fixer in "${FIXERS[@]}"; do
  FIXER_LOGS+=("${LOGDIR}/${fixer}-$(date +%Y%m%d-%H%M).log")
done

# ── Run all fixers in parallel ──────────────────────────────────
echo "Starting all ${#FIXERS[@]} fixers in parallel..." | tee -a "$LOGFILE"

for i in "${!FIXERS[@]}"; do
  fixer="${FIXERS[$i]}"
  fixer_log="${FIXER_LOGS[$i]}"
  fixer_script="${AUTOMATION_DIR}/fixers/${fixer}-fixer.sh"
  slot=$i

  echo ">>> [$((i+1))/${#FIXERS[@]}] ${fixer^} Fixer (slot ${slot}) <<<" | tee -a "$LOGFILE"

  if [ -f "$fixer_script" ]; then
    bash "$fixer_script" > "$fixer_log" 2>&1 &
    FIXER_PIDS+=($!)
  else
    echo "  WARNING: ${fixer_script} not found, skipping." | tee -a "$LOGFILE"
    FIXER_PIDS+=(0)
  fi
done

# Log all PIDs
PID_LINE="PIDs:"
for i in "${!FIXERS[@]}"; do
  PID_LINE="${PID_LINE} ${FIXERS[$i]}=${FIXER_PIDS[$i]}"
done
echo "$PID_LINE" | tee -a "$LOGFILE"

# ── Wait for all fixers to complete ─────────────────────────────
for i in "${!FIXERS[@]}"; do
  fixer="${FIXERS[$i]}"
  pid="${FIXER_PIDS[$i]}"
  exit_code=0

  if [ "$pid" -ne 0 ]; then
    wait "$pid" 2>/dev/null || exit_code=$?
  fi

  FIXER_EXITS+=("$exit_code")
  echo "${fixer^} Fixer finished (exit ${exit_code})" | tee -a "$LOGFILE"
done

# ── Merge per-fixer logs into orchestrator log ──────────────────
echo "" | tee -a "$LOGFILE"

for i in "${!FIXERS[@]}"; do
  fixer="${FIXERS[$i]}"
  fixer_log="${FIXER_LOGS[$i]}"

  echo "--- ${fixer^} Fixer output ---" >> "$LOGFILE"
  cat "$fixer_log" >> "$LOGFILE" 2>/dev/null || true
  echo "" >> "$LOGFILE"
done

# Clean up per-fixer logs (already merged)
for fixer_log in "${FIXER_LOGS[@]}"; do
  rm -f "$fixer_log"
done

echo "" | tee -a "$LOGFILE"
echo "=== Fixer Orchestrator complete: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
exit 0
