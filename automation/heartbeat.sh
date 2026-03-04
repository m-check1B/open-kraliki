#!/bin/bash
# heartbeat.sh — Heartbeat orchestrator
# Runs precheck, skips LLM if no findings, sends Telegram if findings exist.
#
# NOTE: NEVER hardcode model names (e.g. "Opus", "Sonnet", "o4-mini", "GLM-4.7").
#       CLIs manage their own models internally. Reference CLIs only by name.
#
# LaunchAgent: com.automation.heartbeat
# Schedule: Every 30 minutes

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────
AUTOMATION_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="${HOME}/logs/heartbeat"
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%SZ)"
LOGFILE="${LOGDIR}/heartbeat-$(date +%Y%m%d-%H%M).log"
LOG_RETENTION_DAYS=7
ENV_FILE="${ENV_FILE:-$(cd "$AUTOMATION_DIR/.." && pwd)/.env}"
HEARTBEAT_CLI="${HEARTBEAT_CLI:-claude}"
PRECHECK_SCRIPT="${AUTOMATION_DIR}/heartbeat-precheck.py"
PROMPT_FILE="${AUTOMATION_DIR}/../prompts/heartbeat.md"
PERSONALITY_DIR="${AUTOMATION_DIR}/../personality"
SEND_TELEGRAM="${AUTOMATION_DIR}/send-telegram.py"

mkdir -p "$LOGDIR"

# ── Source env vars (launchd doesn't inherit shell env) ──────────
if [ -f "$ENV_FILE" ]; then
  set +e
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set -e
fi

# Rotate logs older than retention period
find "$LOGDIR" -name 'heartbeat-*.log' -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true

echo "=== Heartbeat: ${TIMESTAMP} ===" | tee "$LOGFILE"

# ── Active hours gate ────────────────────────────────────────────
HOUR=$(date +%H)
ACTIVE_START="${ACTIVE_START:-8}"
ACTIVE_END="${ACTIVE_END:-23}"

if [ "$HOUR" -lt "$ACTIVE_START" ] || [ "$HOUR" -ge "$ACTIVE_END" ]; then
  echo "Outside active hours (${ACTIVE_START}-${ACTIVE_END}), skipping." | tee -a "$LOGFILE"
  exit 0
fi

# ── Ensure tools are available ───────────────────────────────────
export PATH="/opt/homebrew/bin:${PATH}"
unset CLAUDECODE 2>/dev/null || true

if ! command -v "$HEARTBEAT_CLI" &>/dev/null; then
  echo "ERROR: ${HEARTBEAT_CLI} CLI not found" | tee -a "$LOGFILE"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found" | tee -a "$LOGFILE"
  exit 1
fi

# ── Run pre-check (no LLM, cheap) ───────────────────────────────
echo "Running precheck..." | tee -a "$LOGFILE"
PRECHECK_EXIT=0

if [ -f "$PRECHECK_SCRIPT" ]; then
  FINDINGS_JSON=$(python3 "$PRECHECK_SCRIPT" 2>&1) || PRECHECK_EXIT=$?
else
  echo "WARNING: precheck script not found at ${PRECHECK_SCRIPT}" | tee -a "$LOGFILE"
  PRECHECK_EXIT=1
  FINDINGS_JSON="{}"
fi

echo "Precheck result (exit ${PRECHECK_EXIT}):" | tee -a "$LOGFILE"
echo "$FINDINGS_JSON" | tee -a "$LOGFILE"

# Exit 1 from precheck = no findings, skip LLM
if [ "$PRECHECK_EXIT" -ne 0 ]; then
  echo "No findings, skipping LLM call." | tee -a "$LOGFILE"
  echo "=== Heartbeat complete (no findings): $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
  exit 0
fi

# ── Build prompt with findings ───────────────────────────────────
if [ -f "$PROMPT_FILE" ]; then
  PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")
else
  PROMPT_TEMPLATE="Analyze these findings and provide a brief status summary:\n{FINDINGS_JSON}\nCurrent time: {CURRENT_TIME}\nIf nothing actionable, respond with just: SKIP"
fi

CURRENT_TIME=$(date "+%Y-%m-%d %H:%M %Z")

# Replace placeholders in prompt
PROMPT="${PROMPT_TEMPLATE//\{FINDINGS_JSON\}/$FINDINGS_JSON}"
PROMPT="${PROMPT//\{CURRENT_TIME\}/$CURRENT_TIME}"

# ── Call CLI to analyze findings ─────────────────────────────────
echo "Calling ${HEARTBEAT_CLI} for analysis..." | tee -a "$LOGFILE"

# Load personality context if available
SYSTEM_CONTEXT=""
if [ -d "$PERSONALITY_DIR" ]; then
  for ctx_file in "${PERSONALITY_DIR}/"*.md; do
    if [ -f "$ctx_file" ]; then
      SYSTEM_CONTEXT="${SYSTEM_CONTEXT}$(cat "$ctx_file" 2>/dev/null || true)"$'\n'
    fi
  done
fi

RESPONSE=$(echo "$PROMPT" | "$HEARTBEAT_CLI" --print \
  --dangerously-skip-permissions \
  --no-session-persistence \
  --append-system-prompt "$SYSTEM_CONTEXT" \
  --allowedTools "Read,Grep,Glob" \
  2>&1) || true

echo "CLI response:" | tee -a "$LOGFILE"
echo "$RESPONSE" | tee -a "$LOGFILE"

# ── Send to Telegram (unless SKIP) ──────────────────────────────
if [ "$RESPONSE" = "SKIP" ] || [ -z "$RESPONSE" ]; then
  echo "CLI said SKIP or empty response, no Telegram message." | tee -a "$LOGFILE"
elif [ -f "$SEND_TELEGRAM" ]; then
  echo "Sending to Telegram..." | tee -a "$LOGFILE"
  echo "$RESPONSE" | python3 "$SEND_TELEGRAM" 2>&1 | tee -a "$LOGFILE"
else
  echo "No send-telegram.py found at ${SEND_TELEGRAM}, skipping Telegram." | tee -a "$LOGFILE"
fi

echo "=== Heartbeat complete: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
exit 0
