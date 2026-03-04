# CLI Setup Guide

How to install and authenticate each AI coding CLI. You only need **one** to get started — add more later for better coverage through [automatic escalation](./agents.md#escalation).

---

## Slot 0: Claude Code

**By:** Anthropic

```bash
# Install
npm install -g @anthropic-ai/claude-code

# Authenticate (opens browser)
claude

# Verify
claude --version
```

**Auth:** Requires a [Claude Pro or Max plan](https://claude.ai/upgrade). Running `claude` for the first time opens a browser login — no API key needed, it authenticates directly to your plan.

**Docs:** [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code)

---

## Slot 1: Codex CLI

**By:** OpenAI

```bash
# Install
npm install -g @openai/codex

# Authenticate
codex auth login
# → Opens browser for OpenAI login

# Verify
codex --version
```

**Auth:** Requires an [OpenAI plan](https://platform.openai.com/) (ChatGPT Pro/Plus or API). The `codex auth login` command opens a browser login — no API key needed, it authenticates directly to your plan.

**Docs:** [github.com/openai/codex](https://github.com/openai/codex)

---

## Slot 2: Opencode CLI

**By:** [Opencode](https://opencode.ai) — supports 75+ providers, recommended with the [Z.AI GLM Coding Plan](https://z.ai/subscribe)

```bash
# Install
curl -fsSL https://opencode.ai/install | bash
# Or: npm install -g opencode-ai

# Authenticate with Z.AI Coding Plan
opencode auth login
# → Select "Z.AI Coding Plan" (not regular "Z.AI")
# → Enter your Z.AI API key

# Select model
# Inside opencode, type: /models
# → Choose GLM-5 or GLM-4.7
```

**Auth:** Subscribe to the [Z.AI GLM Coding Plan](https://z.ai/subscribe) (starts at ~$3/month, includes GLM-5 and GLM-4.7). Your subscription comes with an API key — get it from the Z.AI console, then enter it when `opencode auth login` prompts you.

Opencode also works with any other provider (OpenAI, Anthropic, Groq, local models, etc.) — run `opencode auth login` and pick your provider.

**Docs:** [opencode.ai/docs](https://opencode.ai/docs/) | [Z.AI Developer Docs](https://docs.z.ai/devpack/tool/opencode)

---

## Slot 3: Kimi Code CLI

**By:** [Moonshot AI](https://www.kimi.com/code/en)

```bash
# Install
curl -L code.kimi.com/install.sh | bash
# Or: pip install kimi-cli

# Authenticate
kimi auth login
# → Enter your Kimi Code API key

# Verify
kimi --version
```

**Auth:** You need the **Kimi Code** plan (the coding-specific plan, not the regular Kimi chat membership). Subscribe at [kimi.com/membership/pricing](https://www.kimi.com/membership/pricing), then get your API key from the [Kimi Code Console](https://www.kimi.com/code/console). Quota refreshes on a 7-day rolling cycle.

> **Important:** Kimi has separate chat and coding plans. You need the **coding** plan for CLI access.

**Docs:** [kimi.com/code/docs](https://www.kimi.com/code/docs/en/benefits.html) | [github.com/MoonshotAI/kimi-cli](https://github.com/MoonshotAI/kimi-cli)

---

## Quick Install (all 4)

```bash
# Prerequisites
brew install python3 node git ffmpeg

# Slot 0: Claude Code
npm install -g @anthropic-ai/claude-code

# Slot 1: Codex CLI
npm install -g @openai/codex

# Slot 2: Opencode CLI
curl -fsSL https://opencode.ai/install | bash

# Slot 3: Kimi Code CLI
curl -L code.kimi.com/install.sh | bash
```

Then authenticate each one you installed:

```bash
claude              # Slot 0 — follow browser auth
codex auth login    # Slot 1 — follow browser auth
opencode auth login # Slot 2 — select Z.AI Coding Plan, enter API key
kimi auth login     # Slot 3 — follow browser auth
```

---

## Which CLI Should I Start With?

| If you already have... | Use | Auth type |
|----------------------|-----|-----------|
| Claude Pro/Max plan | Claude Code (slot 0) | Browser login to plan |
| OpenAI / ChatGPT plan | Codex CLI (slot 1) | Browser login to plan |
| Nothing yet, want cheapest | Opencode + [Z.AI Coding Plan](https://z.ai/subscribe) (~$3/mo) | API key from subscription |
| Kimi Code plan | Kimi Code CLI (slot 3) | API key from subscription |

Start with one. The orchestrator auto-detects installed CLIs and skips missing ones. Add more anytime — issues automatically redistribute.

---

## Verifying Everything Works

After installing and authenticating, test each CLI:

```bash
# Claude
echo "Say hello" | claude --print 2>/dev/null

# Codex
codex exec "Say hello"

# Opencode
echo "Say hello" | opencode run --agent build

# Kimi
echo "Say hello" | kimi --yes
```

Each should return a response. If a CLI fails auth, re-run its login command.
