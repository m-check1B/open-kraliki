# Automation Cookbook

Complete reference for all automated agents, their schedules, configs, and operations.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   macOS (launchd)                        │
│                                                         │
│  ┌──────────────────┐  ┌──────────────────┐            │
│  │ Telegram Relay   │  │ Heartbeat        │            │
│  │ (always-on)      │  │ (every 30 min)   │            │
│  │ Telegram bot     │  │ Linear+Calendar  │            │
│  └──────────────────┘  └──────────────────┘            │
│                                                         │
│  ┌───────────────────────────────────────────────┐      │
│  │ Fixer Orchestrator (every 15 min)              │      │
│  │ Runs 4 fixers SEQUENTIALLY:                    │      │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ │      │
│  │  │ Claude     │ │ Codex      │ │ Opencode   │ │      │
│  │  │ Slot 0     │ │ Slot 1     │ │ Slot 2     │ │      │
│  │  └────────────┘ └────────────┘ └────────────┘ │      │
│  │  ┌────────────┐                                │      │
│  │  │ Kimi       │                                │      │
│  │  │ Slot 3     │                                │      │
│  │  └────────────┘                                │      │
│  └───────────────────────────────────────────────┘      │
│                                                         │
│  ┌──────────────────┐                                   │
│  │ Watchdog         │                                   │
│  │ (every 60 min)   │                                   │
│  │ Health monitor   │                                   │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

---

## All Processes at a Glance

| # | Process | Schedule | Active Hours | Script |
|---|---------|----------|--------------|--------|
| 1 | **Telegram Relay** | Always-on (KeepAlive) | Configurable (default 8-23) | `automation/telegram-relay.py` |
| 2 | **Fixer Orchestrator** | Every 15 min | Configurable (default 24/7) | `automation/fixer-orchestrator.sh` |
| 3 | **Watchdog** | Every 60 min | 24/7 | `automation/watchdog.sh` |
| 4 | **Heartbeat** | Every 30 min | Configurable (default 8-23) | `automation/heartbeat.sh` |

---

## 1. Telegram Relay

**Purpose:** Long-polling Telegram bot. Receives messages from owner, pipes through AI CLI, replies.

| Field | Value |
|-------|-------|
| Plist | `~/Library/LaunchAgents/com.automation.telegram-relay.plist` |
| Script | `automation/telegram-relay.py` |
| Logs | `~/logs/relay/launchd_stdout.log` |
| Poll interval | 3 seconds |
| CLI timeout | 120s (configurable) |
| Voice | Groq Whisper (optional, needs `GROQ_API_KEY`) |

### Operations

```bash
# Status
launchctl list | grep com.automation.telegram-relay

# Restart
launchctl unload ~/Library/LaunchAgents/com.automation.telegram-relay.plist
launchctl load ~/Library/LaunchAgents/com.automation.telegram-relay.plist

# Logs
tail -f ~/logs/relay/launchd_stdout.log

# Conversation history
ls ~/logs/relay/conversations/
```

### Known issue: 409 Conflict
When another bot instance polls the same bot token, Telegram returns 409. Fix: stop the duplicate instance. Only one relay process can poll a given bot token at a time.

---

## 2. Fixer Orchestrator

**Purpose:** Runs all 4 fixers sequentially every 15 minutes. Each fixer picks up Linear issues assigned to its slot. Sequential execution prevents git race conditions since all fixers share one worktree.

| Field | Value |
|-------|-------|
| Plist | `~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist` |
| Script | `automation/fixer-orchestrator.sh` |
| Interval | 900 seconds (15 min) |
| Logs | `~/logs/fixer-orchestrator/orchestrator-*.log` |

### Issue Slot System

Issues are split by index modulo 4 to prevent conflicts:

| Slot | Fixer | Issues |
|------|-------|--------|
| 0 | Claude | #0, #4, #8, #12... |
| 1 | Codex | #1, #5, #9, #13... |
| 2 | Opencode | #2, #6, #10, #14... |
| 3 | Kimi | #3, #7, #11, #15... |

### Fixer Flow (each slot)

```
1. Source env vars
2. Check lock file (prevent overlap)
3. Run precheck.py (query Linear, filter by slot)
4. For each issue:
   a. git fetch + reset to latest
   b. Build prompt from template + issue description
   c. Call AI CLI with 10-min timeout
   d. Validate: did any files change?
   e. git add + commit + push (3 retries)
   f. Update Linear: mark Done + add comment
   g. Send Telegram notification
5. Update state.json (track failures)
```

### Operations

```bash
# Manual trigger
bash automation/fixer-orchestrator.sh

# Check individual fixer logs
tail -f ~/logs/claude-fixer/fixer-*.log
tail -f ~/logs/codex-fixer/fixer-*.log
tail -f ~/logs/opencode-fixer/fixer-*.log
tail -f ~/logs/kimi-fixer/fixer-*.log

# Check lock files
ls -la ~/logs/fixer-orchestrator/orchestrator.lock
ls -la ~/logs/claude-fixer/claude-fixer.lock

# Clear stale lock
rm ~/logs/fixer-orchestrator/orchestrator.lock
```

---

## 3. Watchdog

**Purpose:** Hourly health check. Monitors fixer progress, kills stuck processes, resets failed state, checks relay and remote server.

| Field | Value |
|-------|-------|
| Plist | `~/Library/LaunchAgents/com.automation.watchdog.plist` |
| Script | `automation/watchdog.sh` |
| Interval | 3600 seconds (60 min) |
| Logs | `~/logs/watchdog/watchdog-*.log` |

### 6 Health Checks

| # | Check | What it does |
|---|-------|-------------|
| 1 | Commit freshness | Are commits landing in the last 2 hours? |
| 2 | Fixer processes | Is the orchestrator stuck (>120 min)? Kill it. |
| 3 | CLI auth | Any "Not logged in" errors in recent fixer logs? |
| 4 | Relay status | Is the relay running? Any 409 conflicts? |
| 5 | Fixer state | Are >80% of tracked issues at max failures? Reset. |
| 6 | Remote server | (Optional) SSH check if `PRODUCTION_SERVER` is set. |

### Operations

```bash
# Manual trigger
bash automation/watchdog.sh

# Check logs
tail -f ~/logs/watchdog/watchdog-*.log
```

---

## 4. Heartbeat

**Purpose:** Periodic status briefing. Checks Linear issues, calendar events, and Telegram unreads. Sends summary via Telegram if anything noteworthy.

| Field | Value |
|-------|-------|
| Plist | `~/Library/LaunchAgents/com.automation.heartbeat.plist` |
| Script | `automation/heartbeat.sh` |
| Interval | 1800 seconds (30 min) |
| Active hours | Configurable (default 8-23) |
| Logs | `~/logs/heartbeat/heartbeat-*.log` |

### Flow

```
1. Check active hours → skip if outside
2. Run heartbeat-precheck.py (no LLM, checks Linear/Calendar/Relay status)
3. If no findings → exit (cost: $0)
4. If findings → call AI CLI to compose message
5. Send Telegram message (unless CLI says "SKIP")
```

### Operations

```bash
# Manual trigger
bash automation/heartbeat.sh

# Check logs
tail -f ~/logs/heartbeat/heartbeat-*.log
```

---

## Configuration Reference

### Environment Variables

All configuration is via environment variables. See `env.example` for the full list.

| Variable | Used By | Required |
|----------|---------|----------|
| `LINEAR_API_KEY` | precheck, linear-tool, heartbeat-precheck | Yes |
| `LINEAR_TEAM_ID` | precheck, linear-tool, heartbeat-precheck | Yes |
| `LINEAR_TEAM_KEY` | linear-tool | Yes |
| `TELEGRAM_BOT_TOKEN` | relay, send-telegram | Yes |
| `PA_OWNER_CHAT_ID` | relay, send-telegram | Yes |
| `PROJECT_DIR` | all fixers | Yes |
| `PROJECT_BRANCH` | all fixers | No (default: main) |
| `ISSUE_PREFIX` | precheck, fixers | No (default: [AI-QA]) |
| `COMMIT_PREFIX` | fixers | No (default: [AI-FIX]) |
| `GROQ_API_KEY` | relay (voice) | No |
| `ACTIVE_START` / `ACTIVE_END` | fixers, heartbeat | No (default: 0/24 or 8/23) |
| `PRODUCTION_SERVER` | watchdog | No |

### Log Locations

| Component | Log Directory |
|-----------|--------------|
| Fixer Orchestrator | `~/logs/fixer-orchestrator/` |
| Claude Fixer | `~/logs/claude-fixer/` |
| Codex Fixer | `~/logs/codex-fixer/` |
| Opencode Fixer | `~/logs/opencode-fixer/` |
| Kimi Fixer | `~/logs/kimi-fixer/` |
| Watchdog | `~/logs/watchdog/` |
| Heartbeat | `~/logs/heartbeat/` |
| Relay | `~/logs/relay/` |
| Conversations | `~/logs/relay/conversations/` |

All logs rotate automatically (7-day retention).

### State Files

| File | Purpose |
|------|---------|
| `~/logs/claude-fixer/state.json` | Claude fixer attempt tracking |
| `~/logs/codex-fixer/state.json` | Codex fixer attempt tracking |
| `~/logs/opencode-fixer/state.json` | Opencode fixer attempt tracking |
| `~/logs/kimi-fixer/state.json` | Kimi fixer attempt tracking |

State file format:
```json
{
  "attempted": {
    "PROJ-123": {"fail_count": 2},
    "PROJ-456": {"fail_count": 3}
  }
}
```

Issues with `fail_count >= 3` are skipped (need manual attention). Watchdog resets all counts when >80% are maxed out.

---

## Common Operations

### Start/Stop All Agents

```bash
# Start all
launchctl load ~/Library/LaunchAgents/com.automation.*.plist

# Stop all
launchctl unload ~/Library/LaunchAgents/com.automation.*.plist

# List active
launchctl list | grep com.automation
```

### Manual Fixer Run

```bash
# Run orchestrator (all 4 fixers)
bash automation/fixer-orchestrator.sh

# Run single fixer
bash automation/fixers/claude-fixer.sh
```

### Reset Fixer State

```bash
# Reset a single issue
python3 -c "
import json
with open('$HOME/logs/claude-fixer/state.json', 'r+') as f:
    s = json.load(f)
    s.get('attempted', {}).pop('PROJ-123', None)
    f.seek(0); f.truncate(); json.dump(s, f)
"

# Reset all issues for a fixer
echo '{"attempted":{}}' > ~/logs/claude-fixer/state.json
```

### Check Linear Connection

```bash
python3 automation/linear-tool.py list
```

### Send Test Telegram

```bash
echo "Test message from automation" | python3 automation/send-telegram.py
```
