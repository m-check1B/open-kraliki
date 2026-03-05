# Kraliki OS

### AI agents that fix your bugs while you sleep.

An open-source automation system that reads bug reports from [Linear](https://linear.app), fixes the code using AI, pushes the commit, and notifies you on [Telegram](https://telegram.org) — every 15 minutes, hands-free. Extracted from the [Kraliki](https://kraliki.com) platform.

```
You write a bug report  →  AI reads it  →  AI fixes the code  →  commit + push  →  Telegram notification
```

---

## Why This Exists

Most "AI coding" tools require you to sit there and prompt them. This runs **unattended** — you file issues, walk away, and come back to fixed code.

- **Multi-CLI failover** — runs up to 4 AI coding CLIs (Claude, Codex, Opencode, Kimi). If one can't fix an issue after 3 attempts, it automatically escalates to the next CLI.
- **Auto-detects installed CLIs** — only have Claude? It works. Install Codex later and it picks it up automatically.
- **One-switch pause** — set `AUTOMATION_ENABLED=false` in `.env` to pause everything instantly. Set it back to `true` to resume. No uninstalling, no reconfiguring.
- **Telegram chatbot** — message your bot from your phone to ask about code, check issues, or get status. Voice in → voice out (Groq Whisper + macOS TTS).
- **Heartbeat briefings** — every 30 minutes, get a Telegram summary of open issues, upcoming calendar events, and system health. Silent when nothing's happening ($0 cost).
- **Self-healing** — a watchdog checks health every hour, kills stuck processes, resets failed state, and restarts crashed components.
- **Zero dependencies beyond Python + Node** — no Docker, no databases, no cloud services to manage. Just macOS launchd, your repo, and API keys.

---

## What You Get

```
Every 15 min    Linear issues → AI fixers (sequential) → commits → push → Telegram
Every 30 min    Linear + Calendar + system health → heartbeat briefing → Telegram
Every 60 min    Watchdog health check → auto-kill stuck processes → reset state
Always-on       Telegram relay → chat with AI about your code → voice messages
```

### The Full Stack

| Component | What It Does | Script |
|-----------|-------------|--------|
| **Fixer Orchestrator** | Runs all installed fixers sequentially every 15 min | `automation/fixer-orchestrator.sh` |
| **Claude/Codex/Opencode/Kimi Fixers** | Each picks up Linear issues assigned to its slot, fixes code, commits | `automation/fixers/*-fixer.sh` |
| **Precheck** | Queries Linear for fixable issues, assigns to slots via stable hash, handles escalation | `automation/precheck.py` |
| **Telegram Relay** | Always-on chatbot — text + voice, personality files, conversation history | `automation/telegram-relay.py` |
| **Heartbeat** | Periodic status briefing — only messages when something's noteworthy | `automation/heartbeat.sh` |
| **Watchdog** | Health monitor — kills stuck processes, resets state, restarts relay | `automation/watchdog.sh` |
| **Linear Tool** | CLI for Linear API — list, create, update, comment on issues | `automation/linear-tool.py` |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        launchd (macOS)                            │
│                                                                  │
│  ┌──────────────────────┐  ┌────────────┐  ┌─────────────────┐  │
│  │  Fixer Orchestrator  │  │  Watchdog  │  │    Heartbeat    │  │
│  │  (every 15 min)      │  │  (hourly)  │  │  (every 30 min) │  │
│  └──────────┬───────────┘  └────────────┘  └─────────────────┘  │
│             │                                                    │
│  ┌──────────┴────────────────────────────────────┐               │
│  │  Fixers run SEQUENTIALLY (shared git worktree) │               │
│  │                                                │               │
│  │  Claude (slot 0)  →  Codex (slot 1)           │               │
│  │  Opencode (slot 2) →  Kimi (slot 3)           │               │
│  │                                                │               │
│  │  Issue fails 3x? → Escalates to next CLI      │               │
│  │  CLI not installed? → Auto-skipped             │               │
│  └────────────────────────────────────────────────┘               │
│                                                                  │
│  ┌──────────────────────────────────────────┐                    │
│  │  Telegram Relay (always-on long-polling)  │                    │
│  │  Text + Voice → AI CLI → Reply            │                    │
│  └──────────────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────────────┘
```

**How issue assignment works:** Each issue gets a deterministic slot via `md5(issue_id) % fixer_count`. If that fixer fails 3 times, the issue escalates to the next CLI: `(hash + escalation_level) % fixer_count`. If all CLIs fail, the issue needs manual attention.

---

## Quick Start

> **Complete beginner?** Go straight to **[START-HERE.md](./START-HERE.md)** — a step-by-step guide that walks you through everything in 30 minutes. No coding experience needed.

### For developers:

```bash
# Clone
git clone https://github.com/m-check1B/open-kraliki.git
cd open-kraliki

# Configure
cp env.example .env
# Edit .env — fill in LINEAR_API_KEY, TELEGRAM_BOT_TOKEN, PROJECT_DIR, etc.

# Install (creates log dirs, copies launchd plists, loads agents)
chmod +x install.sh && ./install.sh

# Verify
launchctl list | grep com.automation
```

**Prerequisites:** macOS, Python 3.10+, Node.js 18+, Git, at least one AI coding CLI (see **[CLI-SETUP.md](./CLI-SETUP.md)** for install + auth), a [Linear](https://linear.app) account, and a [Telegram](https://t.me/BotFather) bot.

> **Safety:** Point `PROJECT_DIR` at a **dedicated clone**, not your working copy. Fixers run `git reset --hard` before each fix. The AI CLIs run with auto-approve permissions — review commits before merging to production.

---

## Key Features in Detail

### CLI Escalation

When a fixer fails on an issue 3 times, it doesn't just give up — the issue moves to the next CLI in line:

```
Claude fails 3x on PROJ-42  →  Codex gets it
Codex fails 3x              →  Opencode gets it
Opencode fails 3x           →  Kimi gets it
All 4 fail                  →  Issue needs manual fix
```

Each CLI has different strengths. An issue one can't solve, another might crack.

### On/Off Switch

```bash
# In .env:
export AUTOMATION_ENABLED=false   # Everything pauses instantly
export AUTOMATION_ENABLED=true    # Everything resumes
```

launchd agents keep firing on schedule, but scripts check this value first and exit immediately when `false`. Hours, settings, and schedules stay untouched.

### Telegram Chatbot

More than notifications — it's a full AI assistant on your phone:

```
You: "What's the status of PROJ-42?"     →  Checks Linear, replies
You: "Fix the typo in config.ts"         →  Reads file, edits, commits
You: 🎤 (voice message)                  →  Transcribes → processes → voice reply
You: "List open P0 issues"               →  Queries Linear, sends summary
```

Personality, conversation history, and behavior are all configurable via files in `personality/` and `prompts/`.

### Self-Healing Watchdog

Runs 6 health checks every hour:

| Check | What It Does |
|-------|-------------|
| Commit freshness | Are commits landing? Alerts if nothing in 2 hours |
| Stuck processes | Orchestrator running >120 min? Kill it |
| CLI auth | "Not logged in" errors in fixer logs? Alert |
| Relay status | Relay crashed? Auto-restart it |
| State health | >80% of issues maxed out on failures? Reset all counts |
| Remote server | (Optional) SSH health check on production |

---

## Repo Structure

```
open-kraliki/
├── README.md                        # Project overview (this file)
├── CLAUDE.md                        # Claude Code project instructions
├── START-HERE.md                    # Beginner-friendly setup guide
├── SETUP.md                         # Technical installation reference
├── CLI-SETUP.md                     # Per-CLI installation instructions
├── agents.md                        # Agent slots, escalation logic, CLI config
├── env.example                      # All configuration variables
├── install.sh                       # One-shot installer
├── LICENSE                          # Project license
│
├── automation/
│   ├── fixer-orchestrator.sh        # Master orchestrator
│   ├── fixers/                      # Individual fixer scripts (4 CLIs)
│   ├── precheck.py                  # Linear query + slot assignment + escalation
│   ├── telegram-relay.py            # Always-on Telegram chatbot
│   ├── heartbeat.sh                 # Periodic status briefing
│   ├── heartbeat-precheck.py        # Calendar + Linear check (no LLM cost)
│   ├── watchdog.sh                  # Health monitor + auto-recovery
│   ├── send-telegram.py             # Simple message sender
│   └── linear-tool.py              # Linear API CLI
│
├── prompts/                         # System prompts for fixer, relay, heartbeat
├── personality/                     # AI identity, values, user preferences
├── launchd/                         # macOS scheduler plist templates
├── product-roadmap/                 # 9-section product audit methodology
└── cookbooks/                       # Operations + troubleshooting guides
```

---

## Configuration

All settings live in `.env`. Key variables:

| Variable | Purpose | Required |
|----------|---------|----------|
| `LINEAR_API_KEY` | Linear API access | Yes |
| `LINEAR_TEAM_ID` | Your Linear team UUID | Yes |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token | Yes |
| `PA_OWNER_CHAT_ID` | Your Telegram chat ID | Yes |
| `PROJECT_DIR` | Path to dedicated project clone | Yes |
| `AUTOMATION_ENABLED` | `true`/`false` — master on/off switch | No (default: `true`) |
| `ACTIVE_START` / `ACTIVE_END` | Active hours (e.g., 8-22) | No (default: 24/7) |
| `GROQ_API_KEY` | Voice transcription via Groq Whisper | No |
| `ISSUE_PREFIX` | Issue title prefix to match (e.g., `[AI-QA]`) | No |

See [env.example](./env.example) for the full list with comments.

---

## Bonus: Product Roadmap Methodology

Included separately from the automation — a framework for auditing any software product:

- **Three-Layer Reality Model** — Route, UI, Backend for each feature
- **Priority Classification** — P0 (blocks launch), P1 (must-have), P2 (nice-to-have)
- **User Journey Audits** — test what real users do, not what the spec says
- **Issue Templates** — standardized format for Linear issues with effort sizing

See [product-roadmap/METHODOLOGY.md](./product-roadmap/METHODOLOGY.md).

---

## Documentation

| Doc | What It Covers |
|-----|---------------|
| **[START-HERE.md](./START-HERE.md)** | Beginner setup guide (30 min, no experience needed) |
| **[CLI-SETUP.md](./CLI-SETUP.md)** | Install + authenticate each AI coding CLI |
| **[SETUP.md](./SETUP.md)** | Technical installation reference |
| **[AUTOMATION-COOKBOOK.md](./cookbooks/AUTOMATION-COOKBOOK.md)** | Architecture, schedules, configs, operations |
| **[DOCTOR-COOKBOOK.md](./cookbooks/DOCTOR-COOKBOOK.md)** | Troubleshooting, recovery playbooks, diagnostics |
| **[METHODOLOGY.md](./product-roadmap/METHODOLOGY.md)** | Product audit framework |

---

## About

Kraliki OS is the automation infrastructure extracted from the [Kraliki](https://kraliki.com) platform — an AI-powered system for education, communication, and workflow automation.

We open-sourced it because:
- The multi-fixer-with-escalation pattern is genuinely useful and non-obvious
- Good automation shouldn't be reinvented by every team
- Product audit methodology helps any team ship better software

The Kraliki platform itself remains closed-source.

## License

[MIT](./LICENSE) — use it however you want.
