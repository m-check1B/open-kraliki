#!/bin/bash
# fixer-orchestrator.sh — Runs all configured coding fixers SEQUENTIALLY
# Each fixer works on non-overlapping issues (slot modulo FIXER_COUNT).
# Sequential execution prevents git race conditions (all fixers share one worktree).
#
# NOTE: NEVER hardcode model names (e.g. "Opus", "Sonnet", "o4-mini", "GLM-4.7").
#       CLIs manage their own models internally. Reference CLIs only by name.
#
# LaunchAgent: com.automation.fixer-orchestrator
# Schedule: Every 15 minutes
# Slots: Claude (0), Codex (1), Opencode (2), Kimi (3)

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
FIXERS=("claude" "codex" "opencode" "kimi")
FIXER_EXITS=()

# Export fixer count so precheck.py can use dynamic modulo
export FIXER_COUNT="${#FIXERS[@]}"

# ── Run fixers sequentially (safe: all share one git worktree) ──
echo "Running ${#FIXERS[@]} fixers sequentially..." | tee -a "$LOGFILE"

for i in "${!FIXERS[@]}"; do
  fixer="${FIXERS[$i]}"
  fixer_script="${AUTOMATION_DIR}/fixers/${fixer}-fixer.sh"
  fixer_log="${LOGDIR}/${fixer}-$(date +%Y%m%d-%H%M).log"

  echo ">>> [$((i+1))/${#FIXERS[@]}] ${fixer^} Fixer (slot ${i}) <<<" | tee -a "$LOGFILE"

  exit_code=0
  if [ -f "$fixer_script" ]; then
    bash "$fixer_script" > "$fixer_log" 2>&1 || exit_code=$?
  else
    echo "  WARNING: ${fixer_script} not found, skipping." | tee -a "$LOGFILE"
  fi

  FIXER_EXITS+=("$exit_code")
  echo "${fixer^} Fixer finished (exit ${exit_code})" | tee -a "$LOGFILE"

  # Merge fixer log into orchestrator log
  echo "--- ${fixer^} Fixer output ---" >> "$LOGFILE"
  cat "$fixer_log" >> "$LOGFILE" 2>/dev/null || true
  echo "" >> "$LOGFILE"
  rm -f "$fixer_log"
done

echo "" | tee -a "$LOGFILE"
echo "=== Fixer Orchestrator complete: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
exit 0
