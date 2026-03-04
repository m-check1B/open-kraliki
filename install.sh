#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Code Automation Template — Installer
# =============================================================================
# Usage: ./install.sh
# Expects .env in the same directory as this script.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# -----------------------------------------------------------------------------
# 1. Source .env
# -----------------------------------------------------------------------------
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE"
  echo "       Copy env.example to .env and fill in your values:"
  echo "       cp $SCRIPT_DIR/env.example $SCRIPT_DIR/.env"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
echo "[1/5] Sourced $ENV_FILE"

# -----------------------------------------------------------------------------
# 2. Validate required env vars
# -----------------------------------------------------------------------------
REQUIRED_VARS=(
  LINEAR_API_KEY
  LINEAR_TEAM_ID
  LINEAR_TEAM_KEY
  TELEGRAM_BOT_TOKEN
  PA_OWNER_CHAT_ID
  PROJECT_DIR
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: The following required environment variables are not set:"
  for var in "${missing[@]}"; do
    echo "       - $var"
  done
  echo ""
  echo "       Edit $ENV_FILE and fill in all required values."
  exit 1
fi

echo "[2/5] All required env vars validated"

# -----------------------------------------------------------------------------
# 3. Create log directories
# -----------------------------------------------------------------------------
LOG_DIRS=(
  "$HOME/logs/fixer-orchestrator"
  "$HOME/logs/claude-fixer"
  "$HOME/logs/codex-fixer"
  "$HOME/logs/opencode-fixer"
  "$HOME/logs/kimi-fixer"
  "$HOME/logs/watchdog"
  "$HOME/logs/heartbeat"
  "$HOME/logs/relay"
  "$HOME/logs/relay/conversations"
)

for dir in "${LOG_DIRS[@]}"; do
  mkdir -p "$dir"
done

echo "[3/5] Log directories created under $HOME/logs/"

# -----------------------------------------------------------------------------
# 4. Copy launchd plists (from ./launchd/) and substitute placeholders
#    Falls back to generating plists inline if the launchd/ dir is empty.
# -----------------------------------------------------------------------------

PLIST_SOURCE_DIR="$SCRIPT_DIR/launchd"
AUTOMATION_DIR="$SCRIPT_DIR/automation"

# Helper: write a plist from the launchd/ directory (if present) or inline.
install_plist() {
  local label="$1"          # e.g. com.automation.fixer-orchestrator
  local filename="$label.plist"
  local source="$PLIST_SOURCE_DIR/$filename"
  local dest="$LAUNCH_AGENTS_DIR/$filename"

  if [[ -f "$source" ]]; then
    cp "$source" "$dest"
  else
    # Generate inline using the label to pick the right template
    generate_plist "$label" "$dest"
  fi

  # Substitute placeholders that templates may contain
  perl -i -pe "s|__AUTOMATION_DIR__|${AUTOMATION_DIR}|g" "$dest"
  perl -i -pe "s|__HOME__|${HOME}|g" "$dest"
}

generate_plist() {
  local label="$1"
  local dest="$2"

  case "$label" in
    com.automation.fixer-orchestrator)
      cat > "$dest" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${AUTOMATION_DIR}/fixer-orchestrator.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>900</integer>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>${HOME}/logs/fixer-orchestrator/launchd_stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/logs/fixer-orchestrator/launchd_stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
PLIST
      ;;

    com.automation.telegram-relay)
      cat > "$dest" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/python3</string>
    <string>${AUTOMATION_DIR}/telegram-relay.py</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${SCRIPT_DIR}</string>
  <key>StandardOutPath</key>
  <string>${HOME}/logs/relay/launchd_stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/logs/relay/launchd_stderr.log</string>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
PLIST
      ;;

    com.automation.watchdog)
      cat > "$dest" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${AUTOMATION_DIR}/watchdog.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>${HOME}/logs/watchdog/launchd_stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/logs/watchdog/launchd_stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
PLIST
      ;;

    com.automation.heartbeat)
      cat > "$dest" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${AUTOMATION_DIR}/heartbeat.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>1800</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${SCRIPT_DIR}</string>
  <key>StandardOutPath</key>
  <string>${HOME}/logs/heartbeat/launchd_stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/logs/heartbeat/launchd_stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
PLIST
      ;;

    *)
      echo "ERROR: Unknown plist label '$label' and no template found in $PLIST_SOURCE_DIR/"
      exit 1
      ;;
  esac
}

AGENT_LABELS=(
  com.automation.fixer-orchestrator
  com.automation.telegram-relay
  com.automation.watchdog
  com.automation.heartbeat
)

mkdir -p "$LAUNCH_AGENTS_DIR"

for label in "${AGENT_LABELS[@]}"; do
  install_plist "$label"
  echo "       Installed: $LAUNCH_AGENTS_DIR/$label.plist"
done

echo "[4/5] launchd plists installed to $LAUNCH_AGENTS_DIR"

# -----------------------------------------------------------------------------
# 5. Load agents via launchctl
# -----------------------------------------------------------------------------
loaded=()
failed=()

for label in "${AGENT_LABELS[@]}"; do
  plist="$LAUNCH_AGENTS_DIR/$label.plist"

  # Unload first (in case of reinstall) — ignore errors if not loaded
  launchctl unload "$plist" 2>/dev/null || true

  if launchctl load "$plist" 2>/dev/null; then
    loaded+=("$label")
  else
    failed+=("$label")
  fi
done

echo "[5/5] launchd agents loaded"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo " Code Automation Template — Installation Complete"
echo "======================================================================"
echo ""
echo " Template directory : $SCRIPT_DIR"
echo " Automation scripts : $AUTOMATION_DIR"
echo " Log root           : $HOME/logs/"
echo " LaunchAgents dir   : $LAUNCH_AGENTS_DIR"
echo ""
echo " Agents loaded (${#loaded[@]}):"
for label in "${loaded[@]}"; do
  echo "   + $label"
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo ""
  echo " Agents that FAILED to load (${#failed[@]}):"
  for label in "${failed[@]}"; do
    echo "   ! $label"
  done
  echo ""
  echo " Run: launchctl load $LAUNCH_AGENTS_DIR/<label>.plist"
  echo " and check: tail -f $HOME/logs/<component>/launchd_stderr.log"
fi

echo ""
echo " Verify with:"
echo "   launchctl list | grep com.automation"
echo ""
echo " Schedules:"
echo "   fixer-orchestrator : every 15 min"
echo "   telegram-relay     : always-on daemon"
echo "   watchdog           : every 60 min"
echo "   heartbeat          : every 30 min (runs at load)"
echo ""
echo " Logs:"
echo "   tail -f $HOME/logs/fixer-orchestrator/launchd_stdout.log"
echo "   tail -f $HOME/logs/relay/launchd_stdout.log"
echo "   tail -f $HOME/logs/watchdog/launchd_stdout.log"
echo "   tail -f $HOME/logs/heartbeat/launchd_stdout.log"
echo ""
echo " To stop all agents:"
echo "   launchctl unload $LAUNCH_AGENTS_DIR/com.automation.*.plist"
echo "======================================================================"
