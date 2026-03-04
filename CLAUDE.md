# Kraliki OS — Claude Code Context

Project-level instructions for Claude Code sessions working on this repo.

## What This Repo Is

Open-source automation template: AI agents that pull Linear issues, fix code, push commits, and notify via Telegram. Runs on macOS launchd. No Docker, no cloud infra — just scripts, Python, and AI CLIs.

## Architecture

- **Fixer Orchestrator** (`automation/fixer-orchestrator.sh`) — master loop, runs every 15 min via launchd
- **4 Fixer slots** (`automation/fixers/{claude,codex,opencode,kimi}-fixer.sh`) — run sequentially, share one git worktree
- **Precheck** (`automation/precheck.py`) — queries Linear, assigns issues to slots via `md5(issue_id) % fixer_count`, handles escalation when a CLI fails 3x
- **Telegram Relay** (`automation/telegram-relay.py`) — always-on chatbot, voice in/out (Groq Whisper + macOS TTS)
- **Heartbeat** (`automation/heartbeat.sh`) — periodic status briefing via Telegram
- **Watchdog** (`automation/watchdog.sh`) — health monitor, auto-recovery
- **Linear Tool** (`automation/linear-tool.py`) — CLI for Linear API

## Key Conventions

- **All defaults are 24/7** — no nightly stops. Active hours configurable via env vars but default to 0-24.
- **AUTOMATION_ENABLED** — master on/off switch in `.env`. Every script checks this first.
- **macOS Bash 3.2 compatibility** — no `${var^}`, no GNU coreutils. Use `awk toupper()`, `perl -e "alarm N; exec @ARGV"` for timeouts, BSD `date`.
- **No hardcoded paths** — everything uses `$HOME`, `$PROJECT_DIR`, or relative paths from script location.
- **No model references** — never mention specific AI models (o4-mini, GPT-4, etc.). CLIs manage their own models. Say "Claude Code", "Codex CLI", etc.
- **Sequential execution** — fixers share one git worktree, must run sequentially to avoid race conditions.
- **State files** — `~/logs/{name}-fixer/state.json` track `fail_count` per issue. 3 failures = escalate to next CLI.

## File Layout

```
automation/           — All scripts (shell + Python)
automation/fixers/    — Per-CLI fixer scripts
prompts/              — System prompts for fixer, relay, heartbeat
personality/          — AI identity files (IDENTITY.md, SOUL.md, USER.md)
launchd/              — macOS plist templates
product-roadmap/      — Product audit methodology (separate from automation)
cookbooks/            — Operations + troubleshooting docs
```

## Config

All config is via environment variables in `.env` (sourced from `env.example`). Key vars:

- `LINEAR_API_KEY`, `LINEAR_TEAM_ID`, `LINEAR_TEAM_KEY` — Linear access
- `TELEGRAM_BOT_TOKEN`, `PA_OWNER_CHAT_ID` — Telegram bot
- `PROJECT_DIR` — dedicated clone for automation (not working copy!)
- `AUTOMATION_ENABLED` — `true`/`false` master switch
- `GROQ_API_KEY` — optional, for voice transcription
- `RELAY_TTS_VOICE` — macOS voice for voice replies (default: "Ava (Premium)")

## Testing

No test suite — this is an automation template, not a library. To verify:

```bash
python3 automation/linear-tool.py list              # Linear connection
echo "test" | python3 automation/send-telegram.py   # Telegram
FIXER_SLOT=0 python3 automation/precheck.py         # Precheck
bash automation/watchdog.sh                          # Health check
```

## When Editing

- Keep scripts self-contained — each fixer/script sources its own env and can run standalone.
- `.env` is gitignored. `env.example` is the tracked template.
- Personality files in `personality/` are user-customizable templates — keep them generic.
- All docs reference the same architecture. If you change a component name or flow, update: README.md, START-HERE.md, SETUP.md, cookbooks/*.md.
