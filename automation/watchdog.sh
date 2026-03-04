#!/bin/bash
# watchdog.sh — Hourly progress watchdog (runs via launchd)
# Checks if fixers are producing commits. If not, diagnoses and fixes.
# Uses a CLI agent for analysis when intervention is needed.
#
# NOTE: NEVER hardcode model names (e.g. "Opus", "Sonnet", "o4-mini", "GLM-4.7").
#       CLIs manage their own models internally. Reference CLIs only by name.
#
# LaunchAgent: com.automation.watchdog
# Schedule: Every 60 minutes

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────
AUTOMATION_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$AUTOMATION_DIR/.." && pwd)}"
LOGDIR="${HOME}/logs/watchdog"
LOCKFILE="${LOGDIR}/watchdog.lock"
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%SZ)"
LOGFILE="${LOGDIR}/watchdog-$(date +%Y%m%d-%H%M).log"
ENV_FILE="${ENV_FILE:-$(cd "$AUTOMATION_DIR/.." && pwd)/.env}"
RECOVERY_CLI="${RECOVERY_CLI:-opencode}"
SEND_TELEGRAM="${AUTOMATION_DIR}/send-telegram.py"
COMMIT_FRESHNESS_HOURS="${COMMIT_FRESHNESS_HOURS:-2}"

# LaunchAgent identifiers (override via env if needed)
ORCHESTRATOR_AGENT="${ORCHESTRATOR_AGENT:-com.automation.fixer-orchestrator}"
RELAY_AGENT="${RELAY_AGENT:-com.automation.telegram-relay}"

# Optional remote server (only checked if set)
# PRODUCTION_SERVER="user@host"

mkdir -p "$LOGDIR"

# ── Source env vars (launchd doesn't inherit shell env) ──────────
if [ -f "$ENV_FILE" ]; then
  set +e
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set -e
fi
export PATH="/opt/homebrew/bin:${PATH}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"

# Rotate logs older than retention period
find "$LOGDIR" -name 'watchdog-*.log' -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true

echo "=== Watchdog: ${TIMESTAMP} ===" | tee "$LOGFILE"

# ── Lock file ────────────────────────────────────────────────────
if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Another watchdog is running (PID ${LOCK_PID}), skipping." | tee -a "$LOGFILE"
    exit 0
  else
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# ======================================================================
# CHECK 1: Are commits landing?
# ======================================================================
echo "--- Check 1: Commit freshness ---" | tee -a "$LOGFILE"

PROGRESS_OK=true
if [ -d "${PROJECT_DIR}/.git" ]; then
  cd "$PROJECT_DIR"
  git fetch origin main --quiet 2>/dev/null || true

  COMMITS_LAST_HOUR=$(git log --since="1 hour ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
  COMMITS_LAST_WINDOW=$(git log --since="${COMMIT_FRESHNESS_HOURS} hours ago" --oneline 2>/dev/null | wc -l | tr -d ' ')

  echo "Commits last hour: ${COMMITS_LAST_HOUR}" | tee -a "$LOGFILE"
  echo "Commits last ${COMMIT_FRESHNESS_HOURS}h: ${COMMITS_LAST_WINDOW}" | tee -a "$LOGFILE"

  if [ "$COMMITS_LAST_WINDOW" -eq 0 ]; then
    echo "WARNING: No commits in ${COMMIT_FRESHNESS_HOURS} hours!" | tee -a "$LOGFILE"
    PROGRESS_OK=false
  fi
else
  COMMITS_LAST_HOUR=0
  COMMITS_LAST_WINDOW=0
  echo "No git repo at ${PROJECT_DIR}, skipping commit check." | tee -a "$LOGFILE"
fi

# ======================================================================
# CHECK 2: Are fixer processes alive?
# ======================================================================
echo "" | tee -a "$LOGFILE"
echo "--- Check 2: Fixer processes ---" | tee -a "$LOGFILE"

FIXERS_OK=true

ORCH_PID=$(launchctl list 2>/dev/null | grep "$ORCHESTRATOR_AGENT" | awk '{print $1}' || echo "-")
if [ "$ORCH_PID" = "-" ] || [ -z "$ORCH_PID" ]; then
  echo "Fixer Orchestrator: IDLE (waiting for next cycle)" | tee -a "$LOGFILE"
else
  echo "Fixer Orchestrator: RUNNING (PID ${ORCH_PID})" | tee -a "$LOGFILE"
  ORCH_ELAPSED=$(ps -p "$ORCH_PID" -o etime= 2>/dev/null | tr -d ' ' || echo "0:00")
  echo "  Elapsed: ${ORCH_ELAPSED}" | tee -a "$LOGFILE"

  # Parse elapsed time - format is [[DD-]HH:]MM:SS
  ORCH_MINUTES=$(echo "$ORCH_ELAPSED" | awk -F'[:-]' '{
    if (NF==2) print $1;
    else if (NF==3) print $1*60+$2;
    else if (NF==4) print $1*24*60+$2*60+$3;
  }')

  if [ "${ORCH_MINUTES:-0}" -gt 120 ]; then
    echo "  WARNING: Fixer Orchestrator stuck (>120 min). Killing." | tee -a "$LOGFILE"
    pkill -P "$ORCH_PID" 2>/dev/null || true
    kill "$ORCH_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$ORCH_PID" 2>/dev/null || true
    # Clear orchestrator lock and all fixer locks
    rm -f "${HOME}/logs/fixer-orchestrator/orchestrator.lock"
    for fixer_lock in "${HOME}"/logs/*-fixer/*-fixer.lock; do
      rm -f "$fixer_lock" 2>/dev/null || true
    done
    echo "  Killed stuck Orchestrator and cleared all locks." | tee -a "$LOGFILE"
    FIXERS_OK=false
  fi
fi

# ======================================================================
# CHECK 3: CLI auth
# ======================================================================
echo "" | tee -a "$LOGFILE"
echo "--- Check 3: CLI auth ---" | tee -a "$LOGFILE"

AUTH_OK=true
TODAY=$(date +%Y%m%d)
RECENT_AUTH_ERR=$(grep -rl "Not logged in" "${HOME}/logs/fixer-orchestrator/orchestrator-${TODAY}"*.log "${HOME}/logs/"*-fixer/fixer-"${TODAY}"*.log 2>/dev/null | wc -l | tr -d ' ')

if [ "$RECENT_AUTH_ERR" -gt 0 ]; then
  echo "CLI: AUTH ERROR detected in recent logs" | tee -a "$LOGFILE"
  # If commits are landing, auth is actually fine (transient error)
  if [ "$COMMITS_LAST_HOUR" -gt 0 ]; then
    echo "  But commits are landing - auth is OK now (transient error)." | tee -a "$LOGFILE"
  else
    AUTH_OK=false
  fi
else
  echo "CLI: OK (no auth errors in today's logs)" | tee -a "$LOGFILE"
fi

# ======================================================================
# CHECK 4: Relay status (409 conflict)
# ======================================================================
echo "" | tee -a "$LOGFILE"
echo "--- Check 4: Relay status ---" | tee -a "$LOGFILE"

RELAY_OK=true
RELAY_PID=$(launchctl list 2>/dev/null | grep "$RELAY_AGENT" | awk '{print $1}' || echo "")

if [ "$RELAY_PID" = "-" ] || [ -z "$RELAY_PID" ]; then
  echo "Relay: NOT RUNNING" | tee -a "$LOGFILE"
  RELAY_OK=false
else
  # Check for recent 409s in relay logs
  RELAY_LOG_DIR="${HOME}/logs/relay"
  if [ -d "$RELAY_LOG_DIR" ]; then
    RECENT_409=$(grep "409 Conflict" "${RELAY_LOG_DIR}/"*.log 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]')
    if [ -n "$RECENT_409" ]; then
      LAST_409_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$RECENT_409" "+%s" 2>/dev/null || echo "0")
      NOW_TS=$(date "+%s")
      DIFF=$(( (NOW_TS - LAST_409_TS) / 60 ))

      if [ "$DIFF" -lt 10 ]; then
        echo "Relay: 409 CONFLICT (${DIFF} min ago)" | tee -a "$LOGFILE"
        echo "  Restarting relay..." | tee -a "$LOGFILE"
        launchctl unload "${HOME}/Library/LaunchAgents/${RELAY_AGENT}.plist" 2>/dev/null || true
        sleep 2
        launchctl load "${HOME}/Library/LaunchAgents/${RELAY_AGENT}.plist" 2>/dev/null || true
        echo "  Relay restarted." | tee -a "$LOGFILE"
        RELAY_OK=false
      else
        echo "Relay: OK (last 409 was ${DIFF} min ago, recovered)" | tee -a "$LOGFILE"
      fi
    else
      echo "Relay: OK (no 409s)" | tee -a "$LOGFILE"
    fi
  else
    echo "Relay: OK (no relay log directory)" | tee -a "$LOGFILE"
  fi
fi

# ======================================================================
# CHECK 5: Fixer state - too many maxed-out issues?
# ======================================================================
echo "" | tee -a "$LOGFILE"
echo "--- Check 5: Fixer state ---" | tee -a "$LOGFILE"

STATE_OK=true
for state_file in "${HOME}"/logs/*-fixer/state.json; do
  if [ -f "$state_file" ]; then
    FIXER_NAME=$(basename "$(dirname "$state_file")")
    MAXED=$(python3 -c "
import json
with open('$state_file') as f:
    d = json.load(f)
a = d.get('attempted', d)
maxed = sum(1 for v in a.values() if (v.get('fail_count',0) if isinstance(v, dict) else 0) >= 3)
total = len(a)
print(f'{maxed}/{total}')
" 2>/dev/null || echo "?/?")
    echo "${FIXER_NAME}: ${MAXED} at max failures" | tee -a "$LOGFILE"

    MAXED_COUNT=$(echo "$MAXED" | cut -d/ -f1)
    TOTAL_COUNT=$(echo "$MAXED" | cut -d/ -f2)

    # If >80% of tracked issues are maxed, reset them all
    if [ "$TOTAL_COUNT" -gt 0 ] && [ "$MAXED_COUNT" -gt 0 ]; then
      RATIO=$((MAXED_COUNT * 100 / TOTAL_COUNT))
      if [ "$RATIO" -gt 80 ]; then
        echo "  WARNING: ${RATIO}% issues maxed out. Resetting fail counts." | tee -a "$LOGFILE"
        python3 -c "
import json
with open('$state_file', 'r+') as f:
    d = json.load(f)
    a = d.get('attempted', d)
    for k in a:
        if isinstance(a[k], dict):
            a[k]['fail_count'] = 0
    f.seek(0); f.truncate(); json.dump(d, f)
" 2>/dev/null
        STATE_OK=false
      fi
    fi
  fi
done

# ======================================================================
# CHECK 6: Remote server (optional - only if PRODUCTION_SERVER is set)
# ======================================================================
echo "" | tee -a "$LOGFILE"
echo "--- Check 6: Remote server ---" | tee -a "$LOGFILE"

DEV_OK=true
if [ -n "${PRODUCTION_SERVER:-}" ]; then
  DEV_STATUS=$(ssh -o ConnectTimeout=5 "$PRODUCTION_SERVER" "pm2 jlist 2>/dev/null" 2>/dev/null || echo "SSH_FAILED")

  if [ "$DEV_STATUS" = "SSH_FAILED" ]; then
    echo "Remote server (${PRODUCTION_SERVER}): SSH FAILED" | tee -a "$LOGFILE"
    DEV_OK=false
  else
    # Check for relay process on remote
    REMOTE_RELAY_STATUS=$(echo "$DEV_STATUS" | python3 -c "
import sys, json
try:
    procs = json.load(sys.stdin)
    for p in procs:
        if 'relay' in p['name']:
            print(p['pm2_env']['status'])
            break
    else:
        print('not_found')
except: print('parse_error')
" 2>/dev/null)
    echo "Remote relay: ${REMOTE_RELAY_STATUS}" | tee -a "$LOGFILE"

    if [ "$REMOTE_RELAY_STATUS" != "online" ] && [ "$REMOTE_RELAY_STATUS" != "not_found" ]; then
      echo "  Attempting remote relay restart..." | tee -a "$LOGFILE"
      ssh -o ConnectTimeout=5 "$PRODUCTION_SERVER" "pm2 restart all --filter relay 2>/dev/null" 2>/dev/null || true
      DEV_OK=false
    fi
  fi
else
  echo "No PRODUCTION_SERVER set, skipping remote check." | tee -a "$LOGFILE"
fi

# ======================================================================
# DECISION: If issues detected, call CLI for auto-fix
# ======================================================================
echo "" | tee -a "$LOGFILE"
echo "--- Summary ---" | tee -a "$LOGFILE"
echo "Progress: ${PROGRESS_OK}" | tee -a "$LOGFILE"
echo "Fixers: ${FIXERS_OK}" | tee -a "$LOGFILE"
echo "Auth: ${AUTH_OK}" | tee -a "$LOGFILE"
echo "Relay: ${RELAY_OK}" | tee -a "$LOGFILE"
echo "State: ${STATE_OK}" | tee -a "$LOGFILE"
echo "Remote: ${DEV_OK}" | tee -a "$LOGFILE"

ALL_OK=true
PROBLEMS=""
if [ "$PROGRESS_OK" = "false" ]; then ALL_OK=false; PROBLEMS="${PROBLEMS} no-commits"; fi
if [ "$FIXERS_OK" = "false" ]; then ALL_OK=false; PROBLEMS="${PROBLEMS} fixer-stuck"; fi
if [ "$AUTH_OK" = "false" ]; then ALL_OK=false; PROBLEMS="${PROBLEMS} auth-broken"; fi
if [ "$RELAY_OK" = "false" ]; then ALL_OK=false; PROBLEMS="${PROBLEMS} relay-409"; fi
if [ "$STATE_OK" = "false" ]; then ALL_OK=false; PROBLEMS="${PROBLEMS} state-reset"; fi
if [ "$DEV_OK" = "false" ]; then ALL_OK=false; PROBLEMS="${PROBLEMS} remote-down"; fi

if [ "$ALL_OK" = "true" ]; then
  echo "All checks passed. No intervention needed." | tee -a "$LOGFILE"
  echo "=== Watchdog complete (all clear): $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"

  # Run optional post-check report script
  if [ -f "${AUTOMATION_DIR}/watchdog-report.sh" ]; then
    source "${AUTOMATION_DIR}/watchdog-report.sh" 2>/dev/null || true
  fi

  exit 0
fi

echo "" | tee -a "$LOGFILE"
echo "PROBLEMS DETECTED:${PROBLEMS}" | tee -a "$LOGFILE"
echo "Calling ${RECOVERY_CLI} for diagnosis and repair..." | tee -a "$LOGFILE"

# ── Build recovery prompt ────────────────────────────────────────
RECOVERY_STEPS=""
if echo "$PROBLEMS" | grep -q "no-commits\|fixer-stuck"; then
  RECOVERY_STEPS="${RECOVERY_STEPS}
- Kill stuck fixer processes: pkill -f 'claude.*--print' ; pkill -f 'codex.*exec'
- Clear locks: rm -f ${HOME}/logs/fixer-orchestrator/orchestrator.lock ${HOME}/logs/*-fixer/*-fixer.lock
- Check recent logs: tail -20 \$(ls -t ${HOME}/logs/fixer-orchestrator/orchestrator-*.log 2>/dev/null | head -1)
- Reset maxed state if needed"
fi
if echo "$PROBLEMS" | grep -q "auth-broken"; then
  RECOVERY_STEPS="${RECOVERY_STEPS}
- Auth is broken. Check: claude auth status
- If not logged in, this requires interactive login (cannot auto-fix)
- Send Telegram alert about auth failure"
fi
if echo "$PROBLEMS" | grep -q "relay-409"; then
  RECOVERY_STEPS="${RECOVERY_STEPS}
- Check for duplicate relay: ps aux | grep telegram-relay
- Restart relay: launchctl unload ${HOME}/Library/LaunchAgents/${RELAY_AGENT}.plist && sleep 2 && launchctl load ${HOME}/Library/LaunchAgents/${RELAY_AGENT}.plist"
fi
if echo "$PROBLEMS" | grep -q "remote-down"; then
  RECOVERY_STEPS="${RECOVERY_STEPS}
- SSH to remote server: ssh ${PRODUCTION_SERVER:-unknown}
- Check processes: pm2 list
- Restart services: pm2 restart all"
fi

RECOVERY_PROMPT="You are the automation watchdog agent. Problems detected:${PROBLEMS}

State:
- Commits last hour: ${COMMITS_LAST_HOUR:-0}, last ${COMMIT_FRESHNESS_HOURS}h: ${COMMITS_LAST_WINDOW:-0}
- CLI auth: ${AUTH_OK}, Relay: ${RELAY_OK}, Fixers: ${FIXERS_OK}, State: ${STATE_OK}, Remote: ${DEV_OK}

Recovery steps to follow:
${RECOVERY_STEPS}

Execute the recovery steps above. Verify each fix worked. Do NOT create new files. Only fix existing processes. Be surgical and fast."

cd "${PROJECT_DIR}"
WATCHDOG_TIMEOUT="${WATCHDOG_RECOVERY_TIMEOUT:-300}"
# macOS-safe timeout using perl alarm (no GNU coreutils needed)
RECOVERY_OUTPUT=$(echo "$RECOVERY_PROMPT" | perl -e "alarm $WATCHDOG_TIMEOUT; exec @ARGV" "$RECOVERY_CLI" run 2>&1) || true
echo "$RECOVERY_OUTPUT" | tail -50 | tee -a "$LOGFILE"

# ── Send Telegram alert ──────────────────────────────────────────
if [ -f "$SEND_TELEGRAM" ]; then
  TELEGRAM_MSG="Watchdog: problems detected:${PROBLEMS}
Commits last ${COMMIT_FRESHNESS_HOURS}h: ${COMMITS_LAST_WINDOW:-0}
${RECOVERY_CLI} intervention triggered.
Check: ${LOGDIR}/"

  echo "$TELEGRAM_MSG" | python3 "$SEND_TELEGRAM" 2>&1 | tee -a "$LOGFILE" || true
fi

echo "" | tee -a "$LOGFILE"
echo "=== Watchdog complete (intervention): $(date +%Y-%m-%dT%H:%M:%SZ) ===" | tee -a "$LOGFILE"

# Run optional post-check report script
if [ -f "${AUTOMATION_DIR}/watchdog-report.sh" ]; then
  source "${AUTOMATION_DIR}/watchdog-report.sh" 2>/dev/null || true
fi

exit 0
