#!/bin/bash
# codex-fixer.sh — AI Fixer using Codex CLI
# Picks up issues from Linear, uses Codex CLI to fix code, commits + pushes.
#
# NOTE: NEVER hardcode model names. CLIs manage their own models internally.
#
# Slot: 1

set -euo pipefail

# === CONFIGURATION ===
AUTOMATION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$(cd "$AUTOMATION_DIR/.." && pwd)/.env}"

# ── Source env vars first (launchd/cron doesn't inherit shell env) ─────
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PROJECT_DIR="${PROJECT_DIR:?ERROR: PROJECT_DIR must be set. Check your .env file.}"
PROJECT_BRANCH="${PROJECT_BRANCH:-main}"
LOGDIR="$HOME/logs/codex-fixer"
FIXER_NAME="Codex Fixer"
FIXER_SLOT="1"
CLI_COMMAND="codex"
FIX_TIMEOUT="${FIX_TIMEOUT:-600}"
ACTIVE_START="${ACTIVE_START:-0}"
ACTIVE_END="${ACTIVE_END:-24}"
ISSUE_PREFIX="${ISSUE_PREFIX:-[AI-QA]}"
COMMIT_PREFIX="${COMMIT_PREFIX:-[AI-FIX]}"
# === END CONFIGURATION ===

LOCKFILE="${LOGDIR}/codex-fixer.lock"
STATE_FILE="${LOGDIR}/state.json"
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%SZ)"
LOGFILE="${LOGDIR}/fixer-$(date +%Y%m%d-%H%M).log"

# Ensure log dir exists
mkdir -p "$LOGDIR"

# Rotate logs older than 7 days
find "$LOGDIR" -name 'fixer-*.log' -mtime +7 -delete 2>/dev/null || true

echo "=== ${FIXER_NAME}: ${TIMESTAMP} ===" | tee "$LOGFILE"

# ── Active hours gate ────────────────────────────────────────────
HOUR=$(date +%H)

if [ "$HOUR" -lt "$ACTIVE_START" ] || [ "$HOUR" -ge "$ACTIVE_END" ]; then
  echo "Outside active hours (${ACTIVE_START}-${ACTIVE_END}), skipping." | tee -a "$LOGFILE"
  exit 0
fi

# ── Lock file (prevent overlapping runs) ─────────────────────────
if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Another codex-fixer is running (PID ${LOCK_PID}), skipping." | tee -a "$LOGFILE"
    exit 0
  else
    echo "Stale lock file found, removing." | tee -a "$LOGFILE"
    rm -f "$LOCKFILE"
  fi
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# ── Ensure tools are available ───────────────────────────────────
export PATH="/opt/homebrew/bin:$PATH"
unset CLAUDECODE 2>/dev/null || true

for cmd in "$CLI_COMMAND" python3 git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: ${cmd} not found" | tee -a "$LOGFILE"
    exit 1
  fi
done

# ── Export state file path for precheck ──────────────────────────
export QA_FIXER_STATE_FILE="$STATE_FILE"
export FIXER_SLOT

# ── Run pre-check (no LLM, cheap) ───────────────────────────────
echo "Running precheck..." | tee -a "$LOGFILE"
PRECHECK_EXIT=0
ISSUES_JSON=$(python3 "${AUTOMATION_DIR}/precheck.py" 2>&1) || PRECHECK_EXIT=$?

echo "Precheck result (exit ${PRECHECK_EXIT}):" | tee -a "$LOGFILE"
echo "$ISSUES_JSON" | tee -a "$LOGFILE"

if [ "$PRECHECK_EXIT" -eq 2 ]; then
  echo "Precheck error, aborting." | tee -a "$LOGFILE"
  exit 1
fi

if [ "$PRECHECK_EXIT" -ne 0 ]; then
  echo "No ${ISSUE_PREFIX} issues found, nothing to fix." | tee -a "$LOGFILE"
  echo "=== ${FIXER_NAME} complete (no issues): $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
  exit 0
fi

# ── Parse issues from JSON ───────────────────────────────────────
ISSUE_COUNT=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('issues',[])))")
echo "Found ${ISSUE_COUNT} issues to fix." | tee -a "$LOGFILE"

if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "No actionable issues." | tee -a "$LOGFILE"
  exit 0
fi

# ── Prepare prompt template ──────────────────────────────────────
PROMPT_TEMPLATE=$(cat "${AUTOMATION_DIR}/../prompts/fixer.md")

# ── Process each issue ───────────────────────────────────────────
FIXES_SUMMARY=""
FIX_COUNT=0
FAIL_COUNT=0

# Load state for tracking attempts
STATE=$(cat "$STATE_FILE" 2>/dev/null || echo '{"attempted":{}}')

for i in $(seq 0 $((ISSUE_COUNT - 1))); do
  # Extract issue fields
  ISSUE_ID=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['issues'][$i]['identifier'])")
  ISSUE_TITLE=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['issues'][$i]['title'])")
  ISSUE_DESC=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['issues'][$i]['description'])")
  ISSUE_UUID=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['issues'][$i]['id'])")

  echo "" | tee -a "$LOGFILE"
  echo "--- Fixing [${ISSUE_ID}]: ${ISSUE_TITLE} ---" | tee -a "$LOGFILE"

  # ── Git sync (ensure latest code) ────────────────────────────────
  echo "Syncing latest code..." | tee -a "$LOGFILE"
  cd "$PROJECT_DIR"
  SYNC_OK=false
  for sync_try in 1 2 3; do
    if git fetch origin "$PROJECT_BRANCH" 2>&1 | tee -a "$LOGFILE" && \
       git reset --hard "origin/${PROJECT_BRANCH}" 2>&1 | tee -a "$LOGFILE"; then
      SYNC_OK=true
      break
    fi
    echo "Sync attempt ${sync_try} failed, retrying in 3s..." | tee -a "$LOGFILE"
    sleep 3
  done
  if [ "$SYNC_OK" = "false" ]; then
    echo "ERROR: git sync failed after 3 attempts, skipping issue." | tee -a "$LOGFILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # ── Build prompt ─────────────────────────────────────────────
  PROMPT="${PROMPT_TEMPLATE//\{ISSUE_TITLE\}/$ISSUE_TITLE}"
  PROMPT="${PROMPT//\{ISSUE_DESCRIPTION\}/$ISSUE_DESC}"
  PROMPT="${PROMPT//\{PROJECT_PATH\}/$PROJECT_DIR}"

  # ── Call Codex to fix the code ─────────────────────────────────
  echo "Calling ${CLI_COMMAND} to fix..." | tee -a "$LOGFILE"

  TMPFILE_IN=$(mktemp)
  TMPFILE_OUT=$(mktemp)
  echo "$PROMPT" > "$TMPFILE_IN"

  set -m
  codex exec \
    --dangerously-bypass-approvals-and-sandbox \
    -C "$PROJECT_DIR" \
    --ephemeral \
    < "$TMPFILE_IN" > "$TMPFILE_OUT" 2>&1 &
  CLI_PID=$!
  CLI_PGID=$(ps -o pgid= -p $CLI_PID 2>/dev/null | tr -d ' ')
  set +m

  # Watchdog: kill process group after timeout
  ( sleep "$FIX_TIMEOUT"; kill -- -"${CLI_PGID:-$CLI_PID}" 2>/dev/null; sleep 5; kill -9 -- -"${CLI_PGID:-$CLI_PID}" 2>/dev/null ) &
  WD_PID=$!

  # Wait for CLI to finish (or be killed)
  wait $CLI_PID 2>/dev/null
  CLI_EXIT=$?

  # Cancel watchdog
  kill $WD_PID 2>/dev/null; wait $WD_PID 2>/dev/null || true

  FIX_OUTPUT=$(cat "$TMPFILE_OUT")
  rm -f "$TMPFILE_IN" "$TMPFILE_OUT"

  # Check if killed by timeout (128+15=143 SIGTERM, 128+9=137 SIGKILL)
  TIMED_OUT=false
  if [ "$CLI_EXIT" -eq 143 ] || [ "$CLI_EXIT" -eq 137 ]; then
    echo "TIMEOUT: ${CLI_COMMAND} killed after ${FIX_TIMEOUT}s, cleaning git state." | tee -a "$LOGFILE"
    cd "$PROJECT_DIR"
    git checkout -- . 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    TIMED_OUT=true
  fi

  echo "${CLI_COMMAND} response (exit ${CLI_EXIT}):" | tee -a "$LOGFILE"
  echo "$FIX_OUTPUT" | tail -50 | tee -a "$LOGFILE"

  if [ "$TIMED_OUT" = "true" ] || [ "$CLI_EXIT" -ne 0 ] || [ -z "$FIX_OUTPUT" ]; then
    echo "${CLI_COMMAND} failed/timed out, skipping." | tee -a "$LOGFILE"
    STATE=$(echo "$STATE" | python3 -c "
import sys, json
s = json.load(sys.stdin)
a = s.setdefault('attempted', {})
entry = a.setdefault('${ISSUE_ID}', {'fail_count': 0})
entry['fail_count'] = entry.get('fail_count', 0) + 1
print(json.dumps(s))
")
    echo "$STATE" > "$STATE_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # ── Validate: check if there are actual changes ────────────────
  cd "$PROJECT_DIR"
  if git diff --quiet && git diff --cached --quiet; then
    echo "No code changes detected, ${CLI_COMMAND} may not have found a fix." | tee -a "$LOGFILE"
    STATE=$(echo "$STATE" | python3 -c "
import sys, json
s = json.load(sys.stdin)
a = s.setdefault('attempted', {})
entry = a.setdefault('${ISSUE_ID}', {'fail_count': 0})
entry['fail_count'] = entry.get('fail_count', 0) + 1
print(json.dumps(s))
")
    echo "$STATE" > "$STATE_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # ── Show what changed ──────────────────────────────────────────
  echo "Changes:" | tee -a "$LOGFILE"
  git diff --stat 2>&1 | tee -a "$LOGFILE"

  # ── Git commit + push ──────────────────────────────────────────
  COMMIT_MSG="${COMMIT_PREFIX} Fix (codex): ${ISSUE_TITLE}"
  echo "Committing: ${COMMIT_MSG}" | tee -a "$LOGFILE"

  git add -A
  git commit -m "$COMMIT_MSG" 2>&1 | tee -a "$LOGFILE"

  echo "Pushing to origin/${PROJECT_BRANCH}..." | tee -a "$LOGFILE"
  PUSH_OK=false
  for attempt in 1 2 3; do
    if git push origin "$PROJECT_BRANCH" 2>&1 | tee -a "$LOGFILE"; then
      PUSH_OK=true
      break
    fi
    echo "Push failed (attempt ${attempt}/3), rebasing and retrying..." | tee -a "$LOGFILE"
    git pull --rebase origin "$PROJECT_BRANCH" 2>&1 | tee -a "$LOGFILE" || break
    sleep 2
  done
  if [ "$PUSH_OK" = "false" ]; then
    echo "ERROR: git push failed after 3 attempts, reverting commit." | tee -a "$LOGFILE"
    git rebase --abort 2>/dev/null || true
    git reset --soft HEAD~1 2>&1 | tee -a "$LOGFILE"
    git checkout -- . 2>&1 | tee -a "$LOGFILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  # ── Update Linear: mark Done + add comment ─────────────────────
  echo "Updating Linear issue ${ISSUE_ID}..." | tee -a "$LOGFILE"

  FIX_SUMMARY=$(echo "$FIX_OUTPUT" | grep -i "^Fixed:" | tail -1 || echo "$FIX_OUTPUT" | tail -1)

  python3 "${AUTOMATION_DIR}/linear-tool.py" update "$ISSUE_ID" --status "Done" 2>&1 | tee -a "$LOGFILE" || true
  python3 "${AUTOMATION_DIR}/linear-tool.py" comment "$ISSUE_ID" "Auto-fixed by AI Fixer (${CLI_COMMAND}): ${FIX_SUMMARY}" 2>&1 | tee -a "$LOGFILE" || true

  # ── Track success in state ─────────────────────────────────────
  STATE=$(echo "$STATE" | python3 -c "
import sys, json
s = json.load(sys.stdin)
a = s.setdefault('attempted', {})
if '${ISSUE_ID}' in a:
    del a['${ISSUE_ID}']
print(json.dumps(s))
")
  echo "$STATE" > "$STATE_FILE"

  FIX_COUNT=$((FIX_COUNT + 1))
  FIXES_SUMMARY="${FIXES_SUMMARY}
${ISSUE_ID}: ${FIX_SUMMARY}"

  echo "Issue ${ISSUE_ID} fixed and pushed." | tee -a "$LOGFILE"
done

# ── Send Telegram summary ────────────────────────────────────────
if [ "$FIX_COUNT" -gt 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
  TELEGRAM_MSG="${FIXER_NAME}: ${FIX_COUNT} fixed, ${FAIL_COUNT} failed
${FIXES_SUMMARY}"

  echo "" | tee -a "$LOGFILE"
  echo "Sending Telegram summary..." | tee -a "$LOGFILE"
  echo "$TELEGRAM_MSG" | python3 "${AUTOMATION_DIR}/send-telegram.py" 2>&1 | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo "=== ${FIXER_NAME} complete: $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"
exit 0
