# Doctor Cookbook

Diagnosis and recovery guide for all automation processes.

**Companion doc:** [AUTOMATION-COOKBOOK.md](./AUTOMATION-COOKBOOK.md) — process configs, schedules, and operations

---

## 1. Quick Health Check

### One-liner: All Processes

```bash
echo "=== AUTOMATION PROCESSES ===" && \
launchctl list | grep com.automation && \
echo "=== LOCK FILES ===" && \
ls -la ~/logs/*/orchestrator.lock ~/logs/*/*.lock 2>/dev/null || echo "(no locks)" && \
echo "=== RECENT LOGS ===" && \
for d in fixer-orchestrator claude-fixer codex-fixer opencode-fixer gemini-fixer watchdog heartbeat relay; do \
  latest=$(ls -t ~/logs/$d/*.log 2>/dev/null | head -1); \
  [ -n "$latest" ] && echo "  $d: $latest ($(wc -l < "$latest") lines)"; \
done
```

---

## 2. Symptom / Diagnosis / Fix Tables

### 2.1 Relay Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `409 Conflict` in relay logs | Two processes polling the same Telegram bot token | Stop the duplicate instance. Only one relay can poll a given bot token. Check: `launchctl list \| grep relay` and `ps aux \| grep telegram-relay`. |
| Relay running but no responses | AI CLI not authenticated or crashed | Check CLI works: `claude --version`. Check relay logs for auth errors. Run `claude login` if needed. |
| Relay exits immediately | Missing env vars or bad config | Check `TELEGRAM_BOT_TOKEN` and `PA_OWNER_CHAT_ID` are set. Check relay logs for error message. |
| Relay lag (slow responses) | CLI timeout or API slowness | Check logs for timeout messages. Consider reducing CLI timeout. |
| Voice messages not transcribed | `GROQ_API_KEY` not set | Set `GROQ_API_KEY` in your env file. Groq Whisper is optional but needed for voice. |

### 2.2 Authentication Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `"Not logged in"` in fixer logs | CLI auth token expired | Run `claude login` (or equivalent for your CLI) interactively. |
| `codex` auth failure | API key missing or expired | Check `OPENAI_API_KEY` env var. Re-export if needed. |
| Fixer commits but Linear update fails | Linear API key invalid | Verify: `curl -s -H "Authorization: $LINEAR_API_KEY" https://api.linear.app/graphql -d '{"query":"{viewer{id}}"}'` |

### 2.3 Fixer Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Fixer stuck at `fail_count` max | Issue hit max retry attempts (default 3) | Reset state: edit `~/logs/<fixer>/state.json`, set `fail_count` to `0`. Or delete the entry. |
| Fixer finds 0 issues | Slot filtering excludes all issues, or no prefixed issues in Linear | Check Linear for issues with your configured prefix. Verify `FIXER_SLOT` matches available issues. Run precheck manually: `FIXER_SLOT=0 python3 automation/precheck.py` |
| Fixer runs but no commits | CLI fixed nothing or `git push` failed | Check fixer log for "No changes detected" or git errors. Verify repo is on correct branch. |
| Lock file prevents fixer | Previous run crashed without cleanup | Remove lock: `rm ~/logs/<fixer>/<fixer>.lock`. Check for zombie CLI processes. |
| Fixer exits with code 143/137 | 10-min timeout triggered | Normal for complex issues. Issue retries next cycle. Check what was being worked on in logs. |
| Orchestrator lock stale | Orchestrator crashed mid-run | Remove: `rm ~/logs/fixer-orchestrator/orchestrator.lock` |
| Git push conflict | Another fixer pushed first | Built-in retry with rebase handles this. If persistent, check all fixers target same branch. |

### 2.4 Heartbeat Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Heartbeat never fires | Outside active hours or plist not loaded | Verify: `launchctl list \| grep heartbeat`. Check `HEARTBEAT_ACTIVE_START`/`HEARTBEAT_ACTIVE_END` env vars. |
| Heartbeat fires but no Telegram | Precheck found nothing (normal, saves cost) or Telegram send failed | Check heartbeat logs. If precheck returns no findings, this is expected behavior. |
| Calendar check fails | `icalBuddy` not installed | Install: `brew install ical-buddy` (macOS only). |

### 2.5 Watchdog Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Watchdog reports "no commits" | Fixers not producing changes | Check if issues exist in Linear. Check fixer logs for errors. May be normal if all issues are at max failures. |
| Watchdog kills orchestrator | Orchestrator ran >120 min | Normal safety mechanism. Check which fixer was stuck (review orchestrator log). |
| Remote server check fails | SSH connection timeout | Verify `PRODUCTION_SERVER` env var. Test manually: `ssh $PRODUCTION_SERVER 'echo ok'`. |

---

## 3. State File Management

### State File Locations

| File | Purpose |
|------|---------|
| `~/logs/claude-fixer/state.json` | Claude fixer attempt tracking |
| `~/logs/codex-fixer/state.json` | Codex fixer attempt tracking |
| `~/logs/opencode-fixer/state.json` | Opencode fixer attempt tracking |
| `~/logs/gemini-fixer/state.json` | Gemini fixer attempt tracking |

### Common State Operations

```bash
# View current state
cat ~/logs/claude-fixer/state.json | python3 -m json.tool

# Reset a single issue's fail count
python3 -c "
import json
with open('$HOME/logs/claude-fixer/state.json', 'r+') as f:
    state = json.load(f)
    a = state.get('attempted', {})
    if 'PROJ-123' in a:
        a['PROJ-123']['fail_count'] = 0
        f.seek(0); f.truncate(); json.dump(state, f, indent=2)
        print('Reset PROJ-123')
"

# Reset ALL fail counts for a fixer
python3 -c "
import json
with open('$HOME/logs/claude-fixer/state.json', 'r+') as f:
    state = json.load(f)
    for v in state.get('attempted', {}).values():
        if isinstance(v, dict): v['fail_count'] = 0
    f.seek(0); f.truncate(); json.dump(state, f, indent=2)
"

# Nuclear reset (delete all state)
echo '{"attempted":{}}' > ~/logs/claude-fixer/state.json
```

---

## 4. Log Investigation

### Finding Errors

```bash
# Search all fixer logs for errors today
grep -i "error\|failed\|timeout" ~/logs/*/fixer-$(date +%Y%m%d)*.log

# Find the most recent fixer log
ls -t ~/logs/claude-fixer/fixer-*.log | head -1

# Check orchestrator for which fixers ran
grep "finished" ~/logs/fixer-orchestrator/orchestrator-$(date +%Y%m%d)*.log

# Find 409 conflicts in relay
grep "409" ~/logs/relay/launchd_stdout.log | tail -5
```

### Log Rotation

All scripts auto-delete logs older than 7 days. To clean manually:

```bash
find ~/logs -name '*.log' -mtime +7 -delete
```

---

## 5. Recovery Playbooks

### 5.1 Full Restart (after reboot or system issue)

```bash
# 1. Source env
source ~/.env  # or wherever your env file is

# 2. Check env vars are set
echo "LINEAR_API_KEY: ${LINEAR_API_KEY:0:10}..."
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:0:10}..."

# 3. Load all agents
launchctl load ~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist
launchctl load ~/Library/LaunchAgents/com.automation.telegram-relay.plist
launchctl load ~/Library/LaunchAgents/com.automation.watchdog.plist
launchctl load ~/Library/LaunchAgents/com.automation.heartbeat.plist

# 4. Verify
launchctl list | grep com.automation

# 5. Test
echo "Automation restarted" | python3 automation/send-telegram.py
```

### 5.2 API Outage Recovery

When an external API (Anthropic, OpenAI, Google, Linear) is down:

1. All fixers fail gracefully and retry next cycle — no action needed
2. Relay will return error messages to Telegram — user sees the failure
3. If outage > 2 hours, consider unloading fixers to save on retry noise:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist
   ```
4. Reload when service recovers

### 5.3 Relay 409 Conflict

```bash
# 1. Find all relay processes
ps aux | grep telegram-relay

# 2. Stop the automation relay
launchctl unload ~/Library/LaunchAgents/com.automation.telegram-relay.plist

# 3. Kill any orphan processes
pkill -f telegram-relay

# 4. Wait 5 seconds
sleep 5

# 5. Restart
launchctl load ~/Library/LaunchAgents/com.automation.telegram-relay.plist
```

### 5.4 Stuck Fixer Recovery

```bash
# 1. Kill stuck CLI processes
pkill -f "claude.*--print"
pkill -f "codex.*exec"
pkill -f "opencode.*run"
pkill -f "gemini.*-p"

# 2. Clear all lock files
rm -f ~/logs/fixer-orchestrator/orchestrator.lock
rm -f ~/logs/claude-fixer/claude-fixer.lock
rm -f ~/logs/codex-fixer/codex-fixer.lock
rm -f ~/logs/opencode-fixer/opencode-fixer.lock
rm -f ~/logs/gemini-fixer/gemini-fixer.lock

# 3. Reset git state in project
cd $PROJECT_DIR
git checkout -- .
git clean -fd
git fetch origin main && git reset --hard origin/main

# 4. Orchestrator will auto-restart on next 15-min cycle
```

### 5.5 Nuclear Reset (start fresh)

```bash
# 1. Stop everything
launchctl unload ~/Library/LaunchAgents/com.automation.*.plist

# 2. Kill all processes
pkill -f "claude.*--print"
pkill -f "codex.*exec"
pkill -f "opencode.*run"
pkill -f "gemini.*-p"
pkill -f telegram-relay

# 3. Clear all state and locks
for fixer in claude-fixer codex-fixer opencode-fixer gemini-fixer; do
  echo '{"attempted":{}}' > ~/logs/$fixer/state.json
  rm -f ~/logs/$fixer/$fixer.lock
done
rm -f ~/logs/fixer-orchestrator/orchestrator.lock

# 4. Clean git
cd $PROJECT_DIR
git checkout -- .
git clean -fd
git fetch origin main && git reset --hard origin/main

# 5. Restart everything
launchctl load ~/Library/LaunchAgents/com.automation.*.plist

# 6. Verify
launchctl list | grep com.automation
echo "Nuclear reset complete" | python3 automation/send-telegram.py
```

---

## 6. Monitoring Commands

### Quick Status Script

```bash
#!/bin/bash
echo "=== Automation Status ==="
echo ""

echo "Processes:"
launchctl list | grep com.automation | while read pid exit label; do
  status="IDLE"
  [ "$pid" != "-" ] && status="RUNNING (PID $pid)"
  echo "  $label: $status"
done

echo ""
echo "Recent commits (last 2h):"
cd $PROJECT_DIR 2>/dev/null && git log --since="2 hours ago" --oneline | head -5

echo ""
echo "Fixer state:"
for fixer in claude-fixer codex-fixer opencode-fixer gemini-fixer; do
  if [ -f ~/logs/$fixer/state.json ]; then
    maxed=$(python3 -c "
import json
with open('$HOME/logs/$fixer/state.json') as f:
    d = json.load(f)
a = d.get('attempted', {})
maxed = sum(1 for v in a.values() if isinstance(v, dict) and v.get('fail_count',0) >= 3)
print(f'{maxed}/{len(a)}')
" 2>/dev/null || echo "?/?")
    echo "  $fixer: $maxed at max failures"
  fi
done

echo ""
echo "Lock files:"
ls ~/logs/*/orchestrator.lock ~/logs/*/*.lock 2>/dev/null || echo "  (none)"
```

---

## 7. Escalation Matrix

| Severity | Condition | Action |
|----------|-----------|--------|
| **Low** | Single fixer failing | Check logs, may self-recover next cycle |
| **Medium** | All fixers failing | Check auth, API status, git state |
| **High** | Relay down | Restart relay, check for 409 conflicts |
| **Critical** | No commits in 4+ hours + issues exist | Full recovery playbook (§5.4) |

---

## 8. Common One-Liners

```bash
# How many issues are open in Linear?
python3 automation/linear-tool.py list | head -1

# What did the fixers do today?
grep "fixed and pushed" ~/logs/*/fixer-$(date +%Y%m%d)*.log

# How many commits today?
cd $PROJECT_DIR && git log --since="today" --oneline | wc -l

# Is the relay alive?
launchctl list | grep com.automation.telegram-relay

# Send a quick Telegram message
echo "your message" | python3 automation/send-telegram.py

# Create a Linear issue for the fixers
python3 automation/linear-tool.py create "[AI-QA] Fix: description here" --priority 2

# Check which issues are at max failures
python3 -c "
import json, glob
for f in glob.glob('$HOME/logs/*-fixer/state.json'):
    d = json.load(open(f))
    for k, v in d.get('attempted', {}).items():
        if isinstance(v, dict) and v.get('fail_count', 0) >= 3:
            print(f'  {k}: {v[\"fail_count\"]} failures ({f})')
"
```
