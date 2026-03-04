# Setup Guide

Step-by-step installation checklist for Kraliki OS automation.

## Prerequisites Checklist

- [ ] macOS (launchd required)
- [ ] Python 3.10+ (`python3 --version`)
- [ ] Git with SSH access to your repo
- [ ] At least one AI coding CLI installed (`claude`, `codex`, or `opencode`)

## Installation Steps

### 1. Clone This Repository

```bash
git clone https://github.com/m-check1B/open-kraliki.git ~/github/open-kraliki
cd ~/github/open-kraliki
```

### 2. Configure Environment Variables

```bash
cp env.example .env
```

Edit `.env` and fill in:

| Variable | Where to Get It |
|----------|----------------|
| `LINEAR_API_KEY` | [Linear Settings → API](https://linear.app/settings/api) |
| `LINEAR_TEAM_ID` | Linear Settings → Your Team → copy UUID from URL |
| `LINEAR_TEAM_KEY` | Your team's short prefix (e.g., `PROJ`, `APP`) |
| `TELEGRAM_BOT_TOKEN` | Message [@BotFather](https://t.me/BotFather) on Telegram |
| `PA_OWNER_CHAT_ID` | Message [@userinfobot](https://t.me/userinfobot) on Telegram |
| `PROJECT_DIR` | Absolute path to your project repo |
| `GROQ_API_KEY` | (Optional) [Groq Console](https://console.groq.com/keys) |

Then source it in your shell:
```bash
echo 'source ~/github/open-kraliki/.env' >> ~/.zshrc
source ~/.zshrc
```

### 3. Create Linear Team + Labels

In your Linear team:
1. Create labels: `wont-fix`, `manual`, `flaky` (issues with these labels are skipped by fixers)
2. File a test issue: `[AI-QA] Test: Sample issue for automation`

### 4. Create Telegram Bot

1. Message @BotFather: `/newbot`
2. Choose a name and username
3. Copy the token to `TELEGRAM_BOT_TOKEN` in your `.env`
4. Message your bot once (this creates the chat)
5. Get your chat ID from @userinfobot

### 5. Run the Installer

```bash
chmod +x install.sh
./install.sh
```

This will:
- Validate all required env vars
- Create log directories under `~/logs/`
- Copy launchd plists to `~/Library/LaunchAgents/`
- Replace placeholder paths in plists with your actual paths
- Load all 4 agents via `launchctl`

### 6. Verify Installation

```bash
# Check all agents are registered
launchctl list | grep com.automation

# Expected output (PIDs may vary):
# -  0  com.automation.fixer-orchestrator
# 123  0  com.automation.telegram-relay
# -  0  com.automation.watchdog
# -  0  com.automation.heartbeat
```

The telegram-relay should have a PID (it's always-on). Others run on schedule.

### 7. Test Each Component

```bash
# Test Linear connection
python3 automation/linear-tool.py list --team "$LINEAR_TEAM_KEY"

# Test Telegram
echo "Hello from Code Automation!" | python3 automation/send-telegram.py

# Test precheck
FIXER_SLOT=0 python3 automation/precheck.py

# Manual fixer run (optional)
bash automation/fixer-orchestrator.sh
```

### 8. Create Your First Roadmap (Optional)

```bash
# Copy the vertical template
cp product-roadmap/VERTICAL-TEMPLATE.md product-roadmap/my-module.md

# Edit it following the methodology
# See: product-roadmap/METHODOLOGY.md
```

### 9. Create Your First Auto-Fix Issue

In Linear, create an issue with your configured prefix:
```
Title: [AI-QA] Fix: Typo in README.md
Description: The word "recieve" should be "receive" on line 42 of README.md
```

Wait for the next fixer cycle (15 minutes) or trigger manually:
```bash
bash automation/fixer-orchestrator.sh
```

Watch the fix get committed and the issue marked as Done.

## Checking Logs

```bash
# Orchestrator logs
ls ~/logs/fixer-orchestrator/

# Individual fixer logs
ls ~/logs/claude-fixer/
ls ~/logs/codex-fixer/

# Watchdog logs
ls ~/logs/watchdog/

# Relay logs
ls ~/logs/relay/

# Heartbeat logs
ls ~/logs/heartbeat/
```

## Stopping Everything

```bash
# Unload all agents
launchctl unload ~/Library/LaunchAgents/com.automation.*.plist

# Or stop individual components
launchctl unload ~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist
```

## Updating

Pull the latest template and re-run the installer:
```bash
cd ~/github/open-kraliki
git pull
./install.sh
```

## Troubleshooting

See [cookbooks/DOCTOR-COOKBOOK.md](cookbooks/DOCTOR-COOKBOOK.md) for common issues and fixes.

Common problems:
- **"command not found"**: Ensure AI CLIs are in `/opt/homebrew/bin` or update PATH in plist
- **No issues picked up**: Check `LINEAR_API_KEY` and `LINEAR_TEAM_ID` in env
- **409 Conflict on relay**: Two relay instances running — stop the duplicate
- **Fixer stuck**: Watchdog will auto-kill after 120 minutes; check logs for root cause
