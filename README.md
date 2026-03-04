# Kraliki OS

Open-source tools and methodologies extracted from the [Kraliki](https://kraliki.com) platform. Battle-tested solutions for AI-powered development workflows, product management, and automation.

> **New here?** Start with **[START-HERE.md](./START-HERE.md)** — a step-by-step onboarding guide that walks you through the entire setup on your project.

## What's Inside

### [Automation](./automation/) — AI Code Fixer Pipeline

Run **4 parallel AI coding agents** that automatically pick up Linear issues, fix code, push commits, and report via Telegram. Every 15 minutes.

```
Linear Backlog ──► 4 AI Fixers (parallel) ──► Auto-commits ──► Telegram
```

Includes: orchestrator, watchdog, heartbeat, Telegram relay with voice, Linear CLI tool.

**[Get started →](./automation/)**

### [Product Roadmap](./product-roadmap/) — Audit Methodology

A 9-section framework for auditing product modules from spec to shipping state. Three-Layer Reality Model (Route/UI/Backend), priority classification (P0/P1/P2), user journey audits, and Linear issue templates.

**[Read the methodology →](./product-roadmap/METHODOLOGY.md)**

### [Cookbooks](./cookbooks/) — Operations Reference

Complete operations guide and troubleshooting playbook for the automation stack. Architecture diagrams, process inventory, recovery playbooks, and monitoring commands.

- [AUTOMATION-COOKBOOK.md](./cookbooks/AUTOMATION-COOKBOOK.md) — How everything works
- [DOCTOR-COOKBOOK.md](./cookbooks/DOCTOR-COOKBOOK.md) — When things break

### [Personality](./personality/) — AI Identity Templates

Templates for defining your AI assistant's identity, values, and communication style. Used by the Telegram relay and heartbeat.

## Quick Start (Automation)

```bash
# 1. Clone
git clone https://github.com/m-check1B/open-kraliki.git
cd open-kraliki

# 2. Configure
cp env.example .env
# Edit .env with your API keys, project path, team ID

# 3. Install
chmod +x install.sh
./install.sh

# 4. Verify
launchctl list | grep com.automation
```

See [SETUP.md](./SETUP.md) for the full installation guide.

## Prerequisites

- **macOS** with launchd
- **Python 3.10+**
- **Git** with SSH access to your repo
- At least one AI coding CLI: `claude`, `codex`, `opencode`, or `gemini`
- **Linear** account with API key
- **Telegram** bot (via @BotFather)

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
│  │  ┌──────┐ ┌─────┐ ┌──────┐ ┌───┐ │                  │
│  │  │claude│ │codex│ │openc.│ │gem│ │                  │
│  │  │ sl.0 │ │sl.1 │ │ sl.2 │ │s.3│ │                  │
│  │  └──────┘ └─────┘ └──────┘ └───┘ │                  │
│  └───────────────────────────────────┘                  │
│                                                         │
│  ┌─────────────────────────────────────┐                │
│  │  telegram-relay (always-on daemon)  │                │
│  └─────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────┘
```

## About Kraliki

Kraliki is an AI-powered platform for education, communication, and workflow automation. These open-source components represent the infrastructure patterns we've developed while building it.

We're sharing them because:
- Good automation shouldn't be reinvented by every team
- The 4-fixer parallel pattern is genuinely useful and non-obvious
- Product audit methodology helps any team ship better software

The Kraliki platform itself remains closed-source.

## License

MIT
