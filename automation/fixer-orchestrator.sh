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

set -eo pipefail

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
TURBO_MODE="${TURBO_MODE:-false}"
TURBO_PRE_WAVE_CMD="${TURBO_PRE_WAVE_CMD:-}"
TURBO_PRE_WAVE_MIN_INTERVAL="${TURBO_PRE_WAVE_MIN_INTERVAL:-3600}"
TURBO_STATE_FILE="${TURBO_STATE_FILE:-${LOGDIR}/turbo-wave.state}"

# ── On/Off switch (exit early if automation is paused) ─────────
if [ "${AUTOMATION_ENABLED:-true}" = "false" ]; then
  echo "Automation is paused (AUTOMATION_ENABLED=false). Skipping."
  exit 0
fi

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

run_turbo_pre_wave() {
  if [ "$TURBO_MODE" != "true" ] || [ -z "$TURBO_PRE_WAVE_CMD" ]; then
    return 0
  fi

  local now last_run elapsed
  now=$(date +%s)
  last_run=0
  if [ -f "$TURBO_STATE_FILE" ]; then
    last_run=$(cat "$TURBO_STATE_FILE" 2>/dev/null || echo "0")
  fi
  elapsed=$((now - last_run))

  if [ "$elapsed" -lt "$TURBO_PRE_WAVE_MIN_INTERVAL" ]; then
    echo "Turbo pre-wave cooldown active (${elapsed}s < ${TURBO_PRE_WAVE_MIN_INTERVAL}s), skipping." | tee -a "$LOGFILE"
    return 0
  fi

  echo "Running turbo pre-wave command: ${TURBO_PRE_WAVE_CMD}" | tee -a "$LOGFILE"
  if bash -lc "$TURBO_PRE_WAVE_CMD" 2>&1 | tee -a "$LOGFILE"; then
    printf "%s" "$now" > "$TURBO_STATE_FILE"
    echo "Turbo pre-wave complete." | tee -a "$LOGFILE"
  else
    echo "WARNING: Turbo pre-wave failed. Continuing to fixers." | tee -a "$LOGFILE"
  fi
}

# ── Preflight: git identity (commits fail without this) ────────
if ! git config user.name &>/dev/null || ! git config user.email &>/dev/null; then
  echo "ERROR: git user.name or user.email not configured." | tee -a "$LOGFILE"
  echo "  Run: git config --global user.name 'Your Name'" | tee -a "$LOGFILE"
  echo "  Run: git config --global user.email 'you@example.com'" | tee -a "$LOGFILE"
  exit 1
fi

# ── Fixer definitions ───────────────────────────────────────────
ALL_FIXERS=("claude" "codex" "opencode" "kimi")
FIXERS=()
FIXER_EXITS=()

# Auto-detect which CLIs are installed; skip missing ones
for cli in "${ALL_FIXERS[@]}"; do
  if command -v "$cli" &>/dev/null; then
    FIXERS+=("$cli")
  else
    echo "Skipping ${cli} fixer (CLI not installed)" | tee -a "$LOGFILE"
  fi
done

if [ "${#FIXERS[@]}" -eq 0 ]; then
  echo "ERROR: No AI coding CLIs found. Install at least one (claude, codex, opencode, kimi)." | tee -a "$LOGFILE"
  exit 1
fi

# Export fixer count so precheck.py can use dynamic modulo
export FIXER_COUNT="${#FIXERS[@]}"

run_turbo_pre_wave

# ── Run fixers sequentially (safe: all share one git worktree) ──
echo "Running ${#FIXERS[@]} fixers sequentially..." | tee -a "$LOGFILE"

for i in "${!FIXERS[@]}"; do
  fixer="${FIXERS[$i]}"
  fixer_script="${AUTOMATION_DIR}/fixers/${fixer}-fixer.sh"
  fixer_log="${LOGDIR}/${fixer}-$(date +%Y%m%d-%H%M).log"

  fixer_label="$(echo "$fixer" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  echo ">>> [$((i+1))/${#FIXERS[@]}] ${fixer_label} Fixer (slot ${i}) <<<" | tee -a "$LOGFILE"

  # Override fixer slot to match dynamic index (not hardcoded slot in script)
  export FIXER_SLOT="$i"

  exit_code=0
  if [ -f "$fixer_script" ]; then
    bash "$fixer_script" > "$fixer_log" 2>&1 || exit_code=$?
  else
    echo "  WARNING: ${fixer_script} not found, skipping." | tee -a "$LOGFILE"
  fi

  FIXER_EXITS+=("$exit_code")
  echo "${fixer_label} Fixer finished (exit ${exit_code})" | tee -a "$LOGFILE"

  # Merge fixer log into orchestrator log
  echo "--- ${fixer_label} Fixer output ---" >> "$LOGFILE"
  cat "$fixer_log" >> "$LOGFILE" 2>/dev/null || true
  echo "" >> "$LOGFILE"
  rm -f "$fixer_log"
done

echo "" | tee -a "$LOGFILE"
echo "=== Fixer Orchestrator complete: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
exit 0
