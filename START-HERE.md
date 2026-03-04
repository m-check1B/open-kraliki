# Welcome to Kraliki OS

## What is this?

You have a coding project. You have bugs. This tool **automatically fixes them for you**.

Here's what happens after setup:
1. You write a bug report in Linear (a free project tracker)
2. Every 15 minutes, an AI reads your bug reports
3. The AI opens your code, figures out the fix, and applies it
4. It pushes the fix to your repo and tells you on Telegram

You also get a **Telegram chatbot** — message it from your phone to ask questions about your code, check on issues, or get status updates. It can even understand voice messages.

**Time to set up: about 30 minutes.** No coding required — just copy-paste commands.

Let's do this step by step. Check off each box as you go.

---

## Phase 1: Install the Basics (10 min)

You need a Mac for this. (Linux users: you'll need to adapt the scheduling — see the cookbooks.)

### 1.1 Open Terminal

Press `Cmd + Space`, type `Terminal`, press Enter. This is where you'll paste all the commands below.

### 1.2 Install Homebrew (the Mac package manager)

If you've never installed anything from the command line before, you need Homebrew first. Paste this into Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It may ask for your Mac password (the one you use to log in). Type it and press Enter — you won't see the characters as you type, that's normal.

> **Already have Homebrew?** Type `brew --version` — if it shows a version number, skip this step.

### 1.3 Install Python, Node.js, and Git

```bash
brew install python3 node git
```

Verify they installed:
```bash
python3 --version   # Should show 3.10 or higher
node --version      # Should show 18 or higher
git --version       # Should show any version
```

### 1.4 Set up your Git identity

The automation commits code on your behalf, so Git needs to know your name:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

> **Already set?** Run `git config user.name` — if it shows your name, skip this step.

### 1.5 Install Claude Code (the AI that fixes your bugs)

```bash
npm install -g @anthropic-ai/claude-code
```

Then check it works:
```bash
claude --version
```

> **Want more AI fixers?** You can add up to 3 more later. For now, Claude is enough to get started. See the [Tools Reference](#tools--services-reference) at the bottom for the full list.

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

### 3.1 Create a dedicated copy of your project

The automation needs its own copy of your code. **Do not** point it at the folder where you do your daily work — the AI resets the code to the latest version before each fix, which would erase any unsaved work.

```bash
# Create a separate copy for the automation (replace the URL with YOUR repo)
git clone git@github.com:you/your-project.git ~/github/my-project-automation
```

### 3.2 Set up your configuration file

```bash
cd ~/github/open-kraliki
cp env.example .env
```

- [ ] Open `.env` in a text editor (you can use `open -e .env` to open it in TextEdit)
- [ ] Fill in the values you collected in Phase 2:

```bash
# Paste your values here:
export LINEAR_API_KEY="lin_api_..."        # From step 2.1
export LINEAR_TEAM_ID="uuid-here"          # From step 2.1
export LINEAR_TEAM_KEY="PROJ"              # Your team prefix
export TELEGRAM_BOT_TOKEN="123456:ABC..."  # From step 2.2
export PA_OWNER_CHAT_ID="123456789"        # From step 2.2
export PROJECT_DIR="$HOME/github/my-project-automation"  # The clone from 3.1
```

### 3.3 Make the settings load automatically

- [ ] Run this so your settings load every time you open Terminal:

```bash
grep -qxF 'source ~/github/open-kraliki/.env' ~/.zshrc || echo 'source ~/github/open-kraliki/.env' >> ~/.zshrc
source ~/.zshrc
```

> This is safe to run multiple times — it only adds the line if it's not already there.

### 3.4 Verify it worked

```bash
echo "Linear: ${LINEAR_API_KEY:0:15}..."
echo "Telegram: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "Project: $PROJECT_DIR"
```

All three lines should print something that's not blank. If any is empty, open `.env` again and double-check your values.

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
FIXERS=("claude" "codex" "opencode" "kimi")

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

### Pause everything (on/off switch)

Want to pause the automation without uninstalling anything? Just flip one setting in `.env`:

```bash
# In your .env file:
export AUTOMATION_ENABLED=false   # Pause — all scripts exit immediately
export AUTOMATION_ENABLED=true    # Resume — back to normal
```

The launchd agents still fire on schedule, but every script checks this value first and exits immediately when set to `false`. Your hours, settings, and schedules stay untouched — flip it back to `true` and everything resumes exactly as before.

**When to use this:**
- Doing manual work on your project and don't want AI commits interfering
- Debugging an issue and want peace and quiet
- Going on vacation and want to save API costs

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
🎤 (voice message)               →  Transcribes → processes → replies with voice
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
- [ ] The bot transcribes it via Groq Whisper, processes it, and **replies with a voice message** (text in → text out, voice in → voice out)
- [ ] Requires `ffmpeg` for voice replies: `brew install ffmpeg`

> **Language:** Voice transcription defaults to English. To change it, set `WHISPER_LANGUAGE` in your `.env` (e.g., `cs` for Czech, `de` for German, `es` for Spanish).
>
> **Voice:** The reply voice defaults to "Ava (Premium)". Run `say -v '?'` to see all available macOS voices, then set `RELAY_TTS_VOICE` in your `.env`.

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
- **Relay status**: whether the Telegram relay process is running

If nothing noteworthy is found, it stays silent (costs $0). Only messages you when there's something worth knowing.

```bash
# Test heartbeat manually
bash automation/heartbeat.sh

# Check heartbeat logs
tail -20 ~/logs/heartbeat/heartbeat-*.log
```

---

## Phase 8: You're Done! Here's Your Daily Workflow

The automation runs by itself. Here's what your day looks like now:

### When you find a bug

1. Go to Linear
2. Create an issue with the title starting with `[AI-QA]` (e.g., `[AI-QA] Fix: Button not working on mobile`)
3. That's it! The AI picks it up within 15 minutes

### What to keep an eye on

- Check Telegram for fix notifications
- Review the auto-fix commits in your repo (they push directly to your branch)
- If the AI can't fix something after 3 attempts, it stops trying — you may need to fix it yourself or rewrite the bug report with more detail

### If something stops working

```bash
# Run the health checker
bash automation/watchdog.sh

# Check what the fixer was doing
ls -lt ~/logs/claude-fixer/fixer-*.log | head -3

# Clear a stuck process
rm ~/logs/fixer-orchestrator/orchestrator.lock

# For more help, see:
# → cookbooks/DOCTOR-COOKBOOK.md
```

### Pause the automation (recommended)

The easiest way — edit `.env` and set:

```bash
export AUTOMATION_ENABLED=false
```

Everything pauses instantly (on the next cycle). Set it back to `true` to resume.

### Fully stop everything (nuclear option)

This completely unloads the agents from macOS:

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
  Linear issues → 4 AI fixers (sequential) → commits → push → Telegram

Every 30 min:
  Linear + Calendar + relay status → heartbeat briefing → Telegram

Every 60 min:
  Watchdog checks health → kills stuck processes → resets state

Always-on:
  Telegram relay → chat with AI → voice messages → project access
```

---

## Tools & Services Reference

Everything this system uses, with install links.

### AI Coding CLIs

| Slot | CLI | Install | Auth |
|------|-----|---------|------|
| 0 | **Claude Code** | `npm install -g @anthropic-ai/claude-code` | [Claude Pro/Max](https://claude.ai/upgrade) plan → `claude` (browser login) |
| 1 | **Codex CLI** | `npm install -g @openai/codex` | [OpenAI](https://platform.openai.com/) plan → `codex auth login` (browser login) |
| 2 | **Opencode CLI** | `curl -fsSL https://opencode.ai/install \| bash` | [Z.AI Coding Plan](https://z.ai/subscribe) subscription → API key → `opencode auth login` |
| 3 | **Kimi Code CLI** | `pip install kimi-cli` | [Kimi Membership](https://www.kimi.com/code/en) subscription → API key → `kimi auth login` |

> **You only need 1 CLI** to get started. Claude Code (slot 0) is recommended as the primary fixer. Add others for more coverage. See **[CLI-SETUP.md](./CLI-SETUP.md)** for detailed setup instructions for each CLI.

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

# Optional: Install additional CLIs for more fixing coverage
npm install -g @openai/codex                    # Codex (slot 1)
curl -fsSL https://opencode.ai/install | bash   # Opencode (slot 2)
pip install kimi-cli                            # Kimi Code (slot 3)

# Optional: Calendar integration
brew install ical-buddy
```

---

## Need Help?

- **Operations reference**: [cookbooks/AUTOMATION-COOKBOOK.md](./cookbooks/AUTOMATION-COOKBOOK.md)
- **Troubleshooting**: [cookbooks/DOCTOR-COOKBOOK.md](./cookbooks/DOCTOR-COOKBOOK.md)
- **Product roadmap methodology**: [product-roadmap/METHODOLOGY.md](./product-roadmap/METHODOLOGY.md)
- **Issues**: Open an issue on this repo

---

## Glossary (What Do These Words Mean?)

| Term | Plain English |
|------|-------------|
| **CLI** | Command Line Interface — a program you run by typing commands in Terminal |
| **Git** | A tool that tracks every change to your code, like "Track Changes" in Word |
| **Repo** (repository) | Your project folder that Git is tracking |
| **Commit** | A saved snapshot of your code changes (like saving a document) |
| **Push** | Uploading your commits to the cloud (GitHub, etc.) |
| **Branch** | A separate copy of your code for trying things without breaking the original |
| **API key** | A password that lets a program talk to a service (like Linear or Telegram) |
| **launchd** | macOS's built-in scheduler — it runs your automation on a timer |
| **plist** | A settings file that tells launchd what to run and when |
| **Linear** | A project tracker where you write bug reports and feature requests |
| **Telegram** | A messaging app — your bot lives here |
| **ENV file (.env)** | A file with all your passwords and settings (never share this!) |
| **Precheck** | A quick check that costs nothing — it looks at Linear before calling the AI |
| **Watchdog** | A safety program that checks if everything is healthy every hour |
| **Heartbeat** | A periodic summary sent to your Telegram (like a status report) |

Welcome aboard. Let the machines do the boring work.
