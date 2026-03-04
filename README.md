# Code Automation Template

A self-contained template for running **4 parallel AI coding agents** that automatically fix issues from your Linear backlog, push commits, and report via Telegram.

## What This Does

```
Linear Backlog                    Your Repo
┌────────────────┐               ┌──────────────┐
│ [AI-QA] Bug #1 │──┐            │              │
│ [AI-QA] Bug #2 │  │  Fixers    │  auto-fixed  │
│ [AI-QA] Bug #3 │  ├──────────► │  commits     │
│ [AI-QA] Bug #4 │  │  (4 CLIs)  │  pushed      │
│ ...            │──┘            │              │
└────────────────┘               └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │  Telegram     │
                                 │  Notifications│
                                 └──────────────┘
```

**Every 15 minutes**, the orchestrator:

1. Queries Linear for open issues with your configured prefix
2. Splits issues across 4 fixer slots (modulo 4)
3. Each fixer: syncs code → calls its AI CLI → validates changes → commits → pushes → updates Linear
4. Sends a Telegram summary

**Additional components:**
- **Watchdog** (hourly): monitors fixer health, kills stuck processes, resets failed state
- **Heartbeat** (every 30 min): checks Linear + Calendar + Telegram, sends briefings
- **Telegram Relay** (always-on): chat with your AI assistant via Telegram, including voice messages

## Prerequisites

- **macOS** with launchd (the scheduler)
- **4 AI coding CLIs** (any combination): `claude`, `codex`, `opencode`, `gemini`
- **Python 3.10+**
- **Git** with SSH access to your repo
- **Linear** account with API key
- **Telegram** bot (via @BotFather)
- Optional: **Groq** API key (for voice transcription)
- Optional: `icalBuddy` (for calendar integration in heartbeat)

## Quick Start

```bash
# 1. Clone this template
git clone <this-repo> ~/github/code-automation-template
cd ~/github/code-automation-template

# 2. Configure environment
cp env.example .env
# Edit .env with your API keys, project path, team ID, etc.

# 3. Run the installer
chmod +x install.sh
./install.sh

# 4. Verify
launchctl list | grep com.automation
```

That's it. The fixers will start picking up Linear issues on the next cycle.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   launchd (macOS)                        │
│                                                         │
│  ┌─────────────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ fixer-orchestr.  │  │ watchdog │  │   heartbeat   │  │
│  │ (every 15 min)  │  │ (hourly) │  │ (every 30min) │  │
│  └───────┬─────────┘  └──────────┘  └───────────────┘  │
│          │                                              │
│  ┌───────┴───────────────────────────┐                  │
│  │        4 Parallel Fixers          │                  │
│  │  ┌─────┐ ┌─────┐ ┌──────┐ ┌────┐ │                  │
│  │  │slot0│ │slot1│ │slot 2│ │sl.3│ │                  │
│  │  │claude│ │codex│ │openc.│ │gem.│ │                  │
│  │  └─────┘ └─────┘ └──────┘ └────┘ │                  │
│  └───────────────────────────────────┘                  │
│                                                         │
│  ┌─────────────────────────────────────┐                │
│  │  telegram-relay (always-on daemon)  │                │
│  └─────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────┘
```

### Shared Components

| File | Purpose |
|------|---------|
| `automation/precheck.py` | Linear query + slot filtering (no LLM) |
| `automation/send-telegram.py` | Send messages via Telegram Bot API |
| `automation/linear-tool.py` | Full Linear CLI (list/get/create/update/comment/search) |
| `prompts/fixer.md` | System prompt for fixer agents |

### Issue Routing

Issues are split by index modulo 4:
- Issue 0, 4, 8... → Slot 0 (Claude)
- Issue 1, 5, 9... → Slot 1 (Codex)
- Issue 2, 6, 10... → Slot 2 (Opencode)
- Issue 3, 7, 11... → Slot 3 (Gemini)

This prevents conflicts — each fixer works on different issues.

## Configuration

All scripts read from environment variables. See `env.example` for the full list.

Each fixer script has a `# === CONFIGURATION ===` block at the top for CLI-specific settings (command, arguments, timeout).

## File Structure

```
code-automation-template/
├── README.md                   # This file
├── SETUP.md                    # Detailed installation guide
├── env.example                 # Environment variable template
├── install.sh                  # One-shot installer
├── automation/                 # All automation scripts
│   ├── fixer-orchestrator.sh   # Master orchestrator
│   ├── fixers/                 # Individual fixer scripts
│   │   ├── claude-fixer.sh
│   │   ├── codex-fixer.sh
│   │   ├── opencode-fixer.sh
│   │   └── gemini-fixer.sh
│   ├── precheck.py             # Linear issue query + filtering
│   ├── watchdog.sh             # Health monitor + auto-recovery
│   ├── heartbeat.sh            # Periodic status briefing
│   ├── heartbeat-precheck.py   # Calendar + Linear + Telegram check
│   ├── telegram-relay.py       # Always-on Telegram bot
│   ├── send-telegram.py        # Simple message sender
│   └── linear-tool.py          # Linear API CLI
├── prompts/                    # System prompts (customizable)
│   ├── fixer.md
│   ├── relay.md
│   └── heartbeat.md
├── launchd/                    # macOS launchd plist templates
├── product-roadmap/            # Product audit methodology
│   ├── METHODOLOGY.md
│   ├── CHECKLIST.md
│   ├── VERTICAL-TEMPLATE.md
│   └── examples/
├── cookbooks/                  # Operations reference
│   ├── AUTOMATION-COOKBOOK.md
│   └── DOCTOR-COOKBOOK.md
└── personality/                # AI identity templates
    ├── IDENTITY.md
    ├── SOUL.md
    └── USER.md
```

## Customization

### Using Different AI CLIs

Each fixer script is a thin wrapper. To swap a CLI:

1. Edit the `CLI_COMMAND` and `CLI_ARGS` in the fixer's `# === CONFIGURATION ===` block
2. Ensure the CLI is on your PATH
3. The CLI must accept a prompt via stdin and write output to stdout

### Adding More Fixers

1. Copy any fixer script, change `FIXER_SLOT` and `CLI_COMMAND`
2. Update `fixer-orchestrator.sh` to launch the new slot
3. Update `precheck.py` modulo if changing from 4 slots

### Disabling Components

Unload any plist you don't need:
```bash
launchctl unload ~/Library/LaunchAgents/com.automation.heartbeat.plist
```

## Further Reading

- [SETUP.md](SETUP.md) — Step-by-step installation checklist
- [cookbooks/AUTOMATION-COOKBOOK.md](cookbooks/AUTOMATION-COOKBOOK.md) — Full operations reference
- [cookbooks/DOCTOR-COOKBOOK.md](cookbooks/DOCTOR-COOKBOOK.md) — Troubleshooting playbooks
- [product-roadmap/METHODOLOGY.md](product-roadmap/METHODOLOGY.md) — Product audit framework

## License

MIT
