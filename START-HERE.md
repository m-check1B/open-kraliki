# Welcome to Kraliki OS

Hey! I'm Claude Code — your AI coding assistant. I'll walk you through setting up this automation stack on **your** project. By the end, you'll have 4 AI agents fixing bugs from your Linear backlog every 15 minutes, automatically.

Let's do this step by step. Check off each box as you go.

---

## Phase 1: Prerequisites (5 min)

Before we start, make sure you have these on your Mac:

- [ ] **macOS** (this uses launchd — Linux users: adapt the `launchd/` plists to cron/systemd)
- [ ] **Python 3.10+** → check: `python3 --version`
- [ ] **Git** with SSH access to your project repo → check: `git fetch` works in your repo
- [ ] **At least one AI coding CLI installed:**
  - [ ] `claude` → [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
  - [ ] `codex` → [Codex CLI](https://github.com/openai/codex) (optional, slot 1)
  - [ ] `opencode` → [Opencode CLI](https://github.com/opencode-ai/opencode) (optional, slot 2)
  - [ ] `gemini` → [Gemini CLI](https://github.com/google-gemini/gemini-cli) (optional, slot 3)

> **Don't have all 4?** That's fine. You can run with just 1 CLI. We'll disable the others.

---

## Phase 2: Accounts & Tokens (10 min)

You need 2 external services: Linear (issue tracker) and Telegram (notifications).

### 2.1 Linear

- [ ] Create a [Linear](https://linear.app) account (free tier works)
- [ ] Create a team (e.g., "My Project") — note the **team key** (the short prefix like `PROJ`)
- [ ] Go to [Settings → API](https://linear.app/settings/api) → create a **Personal API Key**
- [ ] Copy the key (starts with `lin_api_...`) — you'll need it soon
- [ ] Find your **Team ID**: Settings → Your Team → the UUID in the URL bar
- [ ] Create these labels in your team: `wont-fix`, `manual`, `flaky`

### 2.2 Telegram Bot

- [ ] Open Telegram, message [@BotFather](https://t.me/BotFather)
- [ ] Send `/newbot`, pick a name and username
- [ ] Copy the **bot token** (looks like `123456:ABC-DEF...`)
- [ ] Message [@userinfobot](https://t.me/userinfobot) to get your **chat ID** (a number like `123456789`)
- [ ] Send any message to your new bot (this creates the chat so it can reply to you)

### 2.3 Groq (Optional — for voice messages)

- [ ] Go to [console.groq.com/keys](https://console.groq.com/keys)
- [ ] Create an API key (starts with `gsk_...`)
- [ ] This lets you send voice messages to the Telegram bot and have them transcribed

---

## Phase 3: Configure (5 min)

Now let's wire everything together.

```bash
cd ~/github/open-kraliki
cp env.example .env
```

- [ ] Open `.env` in your editor and fill in every value:

```bash
# Paste your values here:
export LINEAR_API_KEY="lin_api_..."        # From step 2.1
export LINEAR_TEAM_ID="uuid-here"          # From step 2.1
export LINEAR_TEAM_KEY="PROJ"              # Your team prefix
export TELEGRAM_BOT_TOKEN="123456:ABC..."  # From step 2.2
export PA_OWNER_CHAT_ID="123456789"        # From step 2.2
export PROJECT_DIR="$HOME/github/your-project"  # ← YOUR repo path
```

- [ ] Point `PROJECT_DIR` to your actual project repo (absolute path)
- [ ] Source it in your shell:

```bash
echo 'source ~/github/open-kraliki/.env' >> ~/.zshrc
source ~/.zshrc
```

- [ ] Verify the vars are set:

```bash
echo "Linear: ${LINEAR_API_KEY:0:15}..."
echo "Telegram: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "Project: $PROJECT_DIR"
```

All three should print something. If any is blank, check your `.env` file.

---

## Phase 4: Test the Pieces (5 min)

Before installing the full automation, let's test each piece independently.

### 4.1 Test Linear connection

```bash
python3 automation/linear-tool.py list --team "$LINEAR_TEAM_KEY"
```

- [ ] You should see your team's issues (or "No issues found" if empty). If you get an error, check `LINEAR_API_KEY`.

### 4.2 Test Telegram

```bash
echo "Hello from Kraliki OS!" | python3 automation/send-telegram.py
```

- [ ] You should receive the message in Telegram. If not, check your bot token and chat ID.

### 4.3 Test precheck

```bash
export FIXER_SLOT=0
python3 automation/precheck.py
```

- [ ] This queries Linear for fixable issues. You'll see JSON output. If no issues match your prefix (`[AI-QA]` by default), that's expected — we'll create one soon.

### 4.4 Test your AI CLI

```bash
echo "Say hello in one sentence" | claude --print 2>/dev/null
```

- [ ] You should get a response. If `claude` isn't found, check your PATH includes `/opt/homebrew/bin` (or wherever it's installed).

---

## Phase 5: Install (2 min)

Everything works individually? Let's install the automation.

```bash
chmod +x install.sh
./install.sh
```

- [ ] The installer should report success for all 4 agents
- [ ] Verify:

```bash
launchctl list | grep com.automation
```

You should see 4 entries:
```
-    0    com.automation.fixer-orchestrator
123  0    com.automation.telegram-relay
-    0    com.automation.watchdog
-    0    com.automation.heartbeat
```

The relay should have a PID (it's always-on). The others run on schedule.

---

## Phase 6: First Auto-Fix (5 min)

Let's create an issue and watch the automation fix it.

### 6.1 Create a test issue in Linear

```bash
python3 automation/linear-tool.py create \
  "[AI-QA] Fix: Add missing newline at end of README" \
  --desc "The README.md file is missing a trailing newline. Add one." \
  --priority 3
```

- [ ] You should see "Created: [PROJ-1] ..." (or whatever your team key is)

### 6.2 Trigger a manual fixer run

Don't wait 15 minutes — run it now:

```bash
bash automation/fixers/claude-fixer.sh
```

- [ ] Watch the output. It should:
  1. Find the issue via precheck
  2. Sync your repo
  3. Call Claude to fix the code
  4. Commit and push
  5. Update Linear (mark Done)
  6. Send you a Telegram notification

### 6.3 Verify

- [ ] Check your repo: `cd $PROJECT_DIR && git log -1` — you should see the auto-fix commit
- [ ] Check Linear: the issue should be marked Done with a comment
- [ ] Check Telegram: you should have received a fix summary

If all three check out — **congratulations, your automation is live**.

---

## Phase 7: Customize (Optional)

### Only have 1-2 CLIs?

Edit the `FIXERS` array in `automation/fixer-orchestrator.sh`:

```bash
# Default: all 4 fixers
FIXERS=("claude" "codex" "opencode" "gemini")

# Example: only Claude and Codex
FIXERS=("claude" "codex")

# Example: Claude only
FIXERS=("claude")
```

Each entry maps to `automation/fixers/<name>-fixer.sh`. Remove entries for CLIs you don't have installed.

### Change the issue prefix

By default, fixers look for `[AI-QA]` in issue titles. Change it in `.env`:

```bash
export ISSUE_PREFIX="[AUTO-FIX]"  # or whatever you want
export COMMIT_PREFIX="[AUTO]"     # prefix for commit messages
```

### Change the schedule

Edit the plist interval (in seconds):

```bash
# Fixers every 30 min instead of 15:
# Edit ~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist
# Change <integer>900</integer> to <integer>1800</integer>
# Then reload:
launchctl unload ~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist
launchctl load ~/Library/LaunchAgents/com.automation.fixer-orchestrator.plist
```

### Set active hours

Don't want fixers running at 3am? Set in `.env`:

```bash
export ACTIVE_START=8   # Start at 8am
export ACTIVE_END=22    # Stop at 10pm
```

---

## Phase 7b: Telegram Bot — Your AI Assistant (10 min)

The fixer pipeline sends you notifications. But the Telegram relay is much more than that — it's a **full AI assistant** you can chat with from your phone. It has access to your project files, can run commands, and manages Linear issues for you.

### What the bot can do

```
You (Telegram)                        Bot
─────────────────────────────────────────────
"What's the status of PROJ-42?"  →  Checks Linear, replies with details
"Fix the typo in config.ts"     →  Reads the file, edits it, commits
"List open P0 issues"            →  Queries Linear, sends summary
🎤 (voice message)               →  Transcribes via Groq → processes as text
"Summarize today's commits"      →  Runs git log, sends digest
```

### How it works

```
┌──────────┐    getUpdates     ┌──────────────┐    claude --print    ┌───────┐
│ Telegram │ ◄──────────────── │ telegram-     │ ──────────────────► │ Claude│
│ (you)    │ ──────────────── ►│ relay.py      │ ◄────────────────── │ CLI   │
│          │    sendMessage     │ (always-on)   │    response          │       │
└──────────┘                   └──────────────┘                      └───────┘
                                      │
                                      ├── personality/SOUL.md (personality)
                                      ├── personality/IDENTITY.md (capabilities)
                                      ├── personality/USER.md (your preferences)
                                      ├── prompts/relay.md (system prompt)
                                      └── ~/logs/relay/conversations/ (chat history)
```

The relay long-polls Telegram for your messages, pipes them through Claude with your personality files as context, and sends the response back. It keeps a daily conversation log so the bot remembers what you talked about earlier today.

### Test it

- [ ] Check the relay is running:

```bash
launchctl list | grep com.automation.telegram-relay
# Should show a PID (not "-")
```

- [ ] Send a text message to your bot in Telegram
- [ ] You should see a "typing..." indicator, then a response within 10-30 seconds
- [ ] Check the conversation log:

```bash
cat ~/logs/relay/conversations/$(date +%Y-%m-%d).jsonl
```

### Test voice messages (optional)

If you set `GROQ_API_KEY` in your `.env`:

- [ ] Send a voice message to the bot in Telegram
- [ ] The bot transcribes it via Groq Whisper and processes it as text
- [ ] You get a text response back

> **Language:** Voice transcription defaults to English. To change it, set `WHISPER_LANGUAGE` in your `.env` (e.g., `cs` for Czech, `de` for German, `es` for Spanish).

### Customize the personality

The bot's personality is defined in `personality/`:

- [ ] Edit **`personality/IDENTITY.md`** — give your bot a name and define its role
- [ ] Edit **`personality/SOUL.md`** — set the communication style and tone
- [ ] Edit **`personality/USER.md`** — add your name, timezone, and preferences

The relay loads these files as system context for every message. Changes take effect on the next message (no restart needed).

### Customize the behavior

Edit **`prompts/relay.md`** to change how the bot handles messages. By default it:
- Responds concisely (it's Telegram, not an essay)
- Can use tools (read files, search code, check Linear)
- Can delegate to other CLIs for specialized tasks
- Keeps responses under 2000 characters

### Troubleshooting the relay

```bash
# Check if relay is running
launchctl list | grep com.automation.telegram-relay

# Check relay logs
tail -50 ~/logs/relay/launchd_stdout.log

# Common issues:
# "409 Conflict" → another bot instance is polling the same token. Kill it.
# No response → check Claude CLI auth: claude --version
# Slow responses → normal for complex questions (up to 120s timeout)

# Restart the relay
launchctl unload ~/Library/LaunchAgents/com.automation.telegram-relay.plist
launchctl load ~/Library/LaunchAgents/com.automation.telegram-relay.plist
```

### The heartbeat bot

Separately from the relay, the **heartbeat** sends you periodic briefings (every 30 min during active hours). It checks:

- **Linear**: open issues assigned to you + unassigned urgent issues
- **Calendar**: upcoming events today (requires `icalBuddy`: `brew install ical-buddy`)
- **Telegram**: unread messages from you that the relay might have missed

If nothing noteworthy is found, it stays silent (costs $0). Only messages you when there's something worth knowing.

```bash
# Test heartbeat manually
bash automation/heartbeat.sh

# Check heartbeat logs
tail -20 ~/logs/heartbeat/heartbeat-*.log
```

---

## Phase 8: Ongoing Operations

### Daily

The automation runs itself. You just need to:
- Create `[AI-QA]` issues in Linear when you find bugs
- Check Telegram for fix notifications
- Review auto-fix commits (they push directly to main)

### When things break

```bash
# Quick health check
bash automation/watchdog.sh

# Check fixer logs
ls -lt ~/logs/claude-fixer/fixer-*.log | head -3

# Clear a stuck lock
rm ~/logs/fixer-orchestrator/orchestrator.lock

# Full troubleshooting guide:
# → cookbooks/DOCTOR-COOKBOOK.md
```

### Stop everything

```bash
launchctl unload ~/Library/LaunchAgents/com.automation.*.plist
```

### Restart everything

```bash
launchctl load ~/Library/LaunchAgents/com.automation.*.plist
```

---

## What You Now Have

```
Every 15 min:
  Linear issues → 4 AI fixers (parallel) → commits → push → Telegram

Every 30 min:
  Linear + Calendar + Telegram → heartbeat briefing → Telegram

Every 60 min:
  Watchdog checks health → kills stuck processes → resets state

Always-on:
  Telegram relay → chat with AI → voice messages → project access
```

---

## Tools & Services Reference

Everything this system uses, with install links.

### AI Coding CLIs

| Slot | CLI | Install | API Key Required |
|------|-----|---------|-----------------|
| 0 | **Claude Code** | `npm install -g @anthropic-ai/claude-code` ([docs](https://docs.anthropic.com/en/docs/claude-code)) | `ANTHROPIC_API_KEY` ([get key](https://console.anthropic.com/)) |
| 1 | **Codex CLI** | `npm install -g @openai/codex` ([repo](https://github.com/openai/codex)) | `OPENAI_API_KEY` ([get key](https://platform.openai.com/api-keys)) |
| 2 | **Opencode CLI** | `curl -fsSL https://opencode.ai/install | bash` ([repo](https://github.com/opencode-ai/opencode)) | Depends on configured provider |
| 3 | **Gemini CLI** | `npm install -g @google/gemini-cli` ([repo](https://github.com/google-gemini/gemini-cli)) | `GEMINI_API_KEY` ([get key](https://aistudio.google.com/apikey)) |

> **You only need 1 CLI** to get started. Claude Code (slot 0) is recommended as the primary fixer. Add others to run more fixers in parallel.

### External Services

| Service | Purpose | Sign Up | What You Need |
|---------|---------|---------|---------------|
| **Linear** | Issue tracking — fixers pull issues from here | [linear.app](https://linear.app) (free tier works) | API key + Team ID + Team key |
| **Telegram** | Notifications + AI chat relay | [telegram.org](https://telegram.org) | Bot token (via [@BotFather](https://t.me/BotFather)) + your Chat ID (via [@userinfobot](https://t.me/userinfobot)) |
| **Groq** *(optional)* | Voice message transcription (Whisper) | [console.groq.com](https://console.groq.com) | API key (`gsk_...`) |

### Development Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **VS Code** | Recommended editor — great for reviewing auto-fix diffs | [code.visualstudio.com](https://code.visualstudio.com) |
| **Git Graph** *(VS Code extension)* | Visualize branches and auto-fix commits | Install from VS Code Extensions: search "Git Graph" by mhutchie |
| **Python 3.10+** | Runs precheck, Linear tool, Telegram scripts | `brew install python3` or [python.org](https://www.python.org/downloads/) |
| **Node.js 18+** | Required for npm-based CLI installs | `brew install node` or [nodejs.org](https://nodejs.org) |
| **icalBuddy** *(optional)* | Calendar integration for heartbeat | `brew install ical-buddy` |

### Quick Install (macOS)

```bash
# Install Homebrew (if you don't have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install prerequisites
brew install python3 node git

# Install Claude Code (primary fixer)
npm install -g @anthropic-ai/claude-code

# Optional: Install additional CLIs for parallel fixing
npm install -g @openai/codex                    # Codex (slot 1)
curl -fsSL https://opencode.ai/install | bash   # Opencode (slot 2)
npm install -g @google/gemini-cli               # Gemini (slot 3)

# Optional: Calendar integration
brew install ical-buddy
```

---

## Need Help?

- **Operations reference**: [cookbooks/AUTOMATION-COOKBOOK.md](./cookbooks/AUTOMATION-COOKBOOK.md)
- **Troubleshooting**: [cookbooks/DOCTOR-COOKBOOK.md](./cookbooks/DOCTOR-COOKBOOK.md)
- **Product roadmap methodology**: [product-roadmap/METHODOLOGY.md](./product-roadmap/METHODOLOGY.md)
- **Issues**: Open an issue on this repo

Welcome aboard. Let the machines do the boring work.
