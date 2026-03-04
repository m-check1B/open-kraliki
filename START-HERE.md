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

Edit `automation/fixer-orchestrator.sh` and comment out the fixers you don't have:

```bash
# Comment out slots you don't use:
# bash "${AUTOMATION_DIR}/fixers/codex-fixer.sh" > "$CODEX_LOG" 2>&1 &
# bash "${AUTOMATION_DIR}/fixers/gemini-fixer.sh" > "$GEMINI_LOG" 2>&1 &
```

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

### Chat with your assistant

The Telegram relay is running. Send a message to your bot — it will respond using Claude with access to your project files.

Send a voice message (requires Groq API key) and it'll transcribe and respond.

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

## Need Help?

- **Operations reference**: [cookbooks/AUTOMATION-COOKBOOK.md](./cookbooks/AUTOMATION-COOKBOOK.md)
- **Troubleshooting**: [cookbooks/DOCTOR-COOKBOOK.md](./cookbooks/DOCTOR-COOKBOOK.md)
- **Product roadmap methodology**: [product-roadmap/METHODOLOGY.md](./product-roadmap/METHODOLOGY.md)
- **Issues**: Open an issue on this repo

Welcome aboard. Let the machines do the boring work.
