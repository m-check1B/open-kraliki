# Agents Configuration

How the AI coding agents are configured, assigned work, and interact with each other.

## Agent Slots

| Slot | CLI | Install | Fixer Script |
|------|-----|---------|-------------|
| 0 | Claude Code | `npm install -g @anthropic-ai/claude-code` | `automation/fixers/claude-fixer.sh` |
| 1 | Codex CLI | `npm install -g @openai/codex` | `automation/fixers/codex-fixer.sh` |
| 2 | Opencode CLI | `curl -fsSL https://opencode.ai/install \| bash` | `automation/fixers/opencode-fixer.sh` |
| 3 | Kimi Code CLI | `pip install kimi-cli` | `automation/fixers/kimi-fixer.sh` |

**You only need 1 CLI.** The orchestrator auto-detects which CLIs are installed and skips missing ones.

## How Work Gets Assigned

Each Linear issue gets a **deterministic slot** based on its identifier:

```
slot = md5(issue_id) % fixer_count
```

This means:
- The same issue always goes to the same CLI (stable across runs)
- Work is evenly distributed across installed CLIs
- Adding/removing a CLI redistributes some issues but doesn't cause chaos

### Escalation

When a CLI fails on an issue 3 times (tracked in `state.json`), the issue **escalates** to the next CLI:

```
assigned_slot = (md5(issue_id) + escalation_level) % fixer_count
```

The escalation level is computed by counting how many CLIs have already maxed out on that issue (reading all `~/logs/*-fixer/state.json` files).

```
Example: 4 CLIs installed
  PROJ-42 hashes to slot 0 (Claude)
  Claude fails 3x → escalation_level=1 → slot 1 (Codex)
  Codex fails 3x  → escalation_level=2 → slot 2 (Opencode)
  Opencode fails 3x → escalation_level=3 → slot 3 (Kimi)
  All 4 fail → issue is stuck, needs manual attention
```

## Execution Model

**Sequential, not parallel.** All fixers share one git worktree (`$PROJECT_DIR`), so they must run one at a time to avoid git conflicts.

The orchestrator loops through installed CLIs:

```bash
for i in "${!FIXERS[@]}"; do
  export FIXER_SLOT="$i"
  export FIXER_COUNT="${#FIXERS[@]}"
  bash "automation/fixers/${FIXERS[$i]}-fixer.sh"
done
```

Each fixer run:
1. Sources `.env`
2. Checks `AUTOMATION_ENABLED` — exits if `false`
3. Checks active hours — exits if outside window
4. Acquires lock file (prevents overlap)
5. Runs `precheck.py` — gets assigned issues from Linear
6. For each issue:
   - `git fetch && git reset --hard origin/$BRANCH`
   - Builds prompt from `prompts/fixer.md` + issue description
   - Calls CLI with timeout (default 10 min)
   - Validates: did files change?
   - `git add && commit && push` (3 retries)
   - Updates Linear (mark Done + comment)
   - Sends Telegram notification
7. Updates `state.json` (increment `fail_count` on failure)

## State Tracking

Each fixer maintains a state file at `~/logs/{name}-fixer/state.json`:

```json
{
  "attempted": {
    "PROJ-123": {"fail_count": 2},
    "PROJ-456": {"fail_count": 3}
  }
}
```

- `fail_count < 3` — issue will be retried next cycle
- `fail_count >= 3` — issue skipped by this CLI, escalated to next
- Watchdog resets all counts when >80% of issues are maxed out

## Telegram Relay Agent

The relay (`automation/telegram-relay.py`) is a separate always-on agent — not part of the fixer loop.

- Long-polls Telegram for owner messages
- Pipes messages through configured CLI (default: `claude --print`)
- **Text in → text out** / **Voice in → voice out**
- Voice: Groq Whisper transcription → AI response → macOS TTS (`say`) → OGG via ffmpeg → Telegram `sendVoice`
- Loads personality from `personality/` (IDENTITY.md, SOUL.md, USER.md)
- Keeps daily conversation history in `~/logs/relay/conversations/YYYY-MM-DD.jsonl`

## Heartbeat Agent

The heartbeat (`automation/heartbeat.sh`) runs every 30 minutes:

1. `heartbeat-precheck.py` checks Linear, Calendar, relay status — **no LLM cost**
2. If nothing noteworthy → exits silently ($0)
3. If findings → calls CLI to compose a Telegram briefing
4. Sends summary (unless CLI says "SKIP")

## Adding a New CLI

To add a 5th fixer:

1. Create `automation/fixers/newcli-fixer.sh` (copy any existing fixer, change the CLI command)
2. Add `"newcli"` to the `ALL_FIXERS` array in `automation/fixer-orchestrator.sh`
3. Ensure `newcli` is on your PATH
4. The orchestrator auto-detects it on next run
5. `FIXER_COUNT` adjusts automatically — issues redistribute across 5 slots

## Removing a CLI

Just uninstall it. The orchestrator skips CLIs that aren't found via `command -v`. Issues assigned to the missing slot get picked up by remaining CLIs through escalation.
