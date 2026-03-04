#!/usr/bin/env python3
"""telegram-relay.py — Poll Telegram for owner messages, route to an LLM CLI, reply.

Long-running polling daemon. Checks getUpdates every few seconds, pipes new
owner messages through a configurable CLI command with personality context,
and sends the response back via sendMessage.

Designed to run as a launchd agent (KeepAlive) or systemd service.

Env vars:
  TELEGRAM_BOT_TOKEN  — Telegram bot token (required)
  PA_OWNER_CHAT_ID    — Owner's Telegram chat ID (required)
  GROQ_API_KEY        — Groq API key for voice transcription (optional)
  WHISPER_LANGUAGE    — Language code for voice transcription (default: "en")
  RELAY_CLI_CMD       — CLI command to invoke, e.g. "claude --print" (default: "claude --print")
  RELAY_CLI_TIMEOUT   — Max seconds for CLI response (default: 120)
  RELAY_ACTIVE_START  — Hour to start accepting messages (default: 8)
  RELAY_ACTIVE_END    — Hour to stop accepting messages (default: 23)
  RELAY_POLL_INTERVAL — Seconds between polls (default: 3)
  RELAY_LOG_DIR       — Directory for conversation logs (default: ~/logs/relay/conversations)
"""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.request import Request, urlopen

# ── Bootstrap env vars (launchd does not inherit shell env) ───────────
def _load_env():
    """Source env vars from the repo .env file when running under launchd."""
    # Primary: repo-level .env (same directory as project root)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    env_file = os.environ.get("ENV_FILE", os.path.join(project_root, ".env"))

    for path in [env_file, os.path.join(os.path.expanduser("~"), ".env")]:
        if os.path.exists(path):
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("export ") and "=" in line:
                        kv = line[len("export "):]
                        key, _, val = kv.partition("=")
                        os.environ.setdefault(key.strip(), val.strip().strip("'\""))
            break


_load_env()

# ── Config ────────────────────────────────────────────────────────────
AUTOMATION_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.environ.get("PROJECT_DIR", os.path.dirname(AUTOMATION_DIR))

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("PA_OWNER_CHAT_ID", "")
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
WHISPER_LANGUAGE = os.environ.get("WHISPER_LANGUAGE", "en")

CLI_CMD = os.environ.get("RELAY_CLI_CMD", "claude --print")
CLI_TIMEOUT = int(os.environ.get("RELAY_CLI_TIMEOUT", os.environ.get("FIX_TIMEOUT", "120")))
ACTIVE_START = int(os.environ.get("RELAY_ACTIVE_START", "8"))
ACTIVE_END = int(os.environ.get("RELAY_ACTIVE_END", "23"))
POLL_INTERVAL = int(os.environ.get("RELAY_POLL_INTERVAL", "3"))
LOG_DIR = os.environ.get("RELAY_LOG_DIR", os.path.expanduser("~/logs/relay/conversations"))

PERSONALITY_DIR = os.path.join(PROJECT_ROOT, "personality")
PROMPT_TEMPLATE = os.path.join(PROJECT_ROOT, "prompts", "relay.md")

# Track last processed update to avoid duplicates
last_update_id = 0
running = True


def log(msg: str):
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"[{ts}] {msg}", flush=True)


def log_conversation(user_message: str, response: str, msg_id: int | None = None):
    """Append conversation to daily JSONL log."""
    os.makedirs(LOG_DIR, exist_ok=True)
    date_str = time.strftime("%Y-%m-%d")
    log_path = os.path.join(LOG_DIR, f"{date_str}.jsonl")
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "msg_id": msg_id,
        "user": user_message,
        "assistant": response,
    }
    try:
        with open(log_path, "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        log(f"log_conversation failed: {e}")


def signal_handler(sig, frame):
    global running
    log(f"Received signal {sig}, shutting down...")
    running = False


signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


def get_updates(offset: int) -> list[dict]:
    """Fetch new updates from Telegram Bot API."""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/getUpdates"
    params = {"offset": offset, "timeout": 30, "limit": 10}
    try:
        req = Request(
            f"{url}?{'&'.join(f'{k}={v}' for k, v in params.items())}",
            headers={"Content-Type": "application/json"},
        )
        with urlopen(req, timeout=35) as resp:
            data = json.loads(resp.read())
        return data.get("result", [])
    except (URLError, Exception) as e:
        log(f"getUpdates failed: {e}")
        return []


def send_message(text: str, reply_to: int | None = None) -> bool:
    """Send a reply via Telegram Bot API."""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": text[:4096],
        "parse_mode": "Markdown",
        "disable_web_page_preview": True,
    }
    if reply_to:
        payload["reply_to_message_id"] = reply_to
    try:
        req = Request(
            url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
            return result.get("ok", False)
    except (URLError, Exception) as e:
        log(f"sendMessage failed: {e}")
        # Retry without Markdown in case of parse errors
        try:
            payload.pop("parse_mode", None)
            req = Request(
                url,
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"},
            )
            with urlopen(req, timeout=15) as resp:
                return json.loads(resp.read()).get("ok", False)
        except Exception:
            return False


def get_file_url(file_id: str) -> str | None:
    """Get download URL for a Telegram file by file_id."""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/getFile?file_id={file_id}"
    try:
        with urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
        file_path = data.get("result", {}).get("file_path")
        if file_path:
            return f"https://api.telegram.org/file/bot{BOT_TOKEN}/{file_path}"
    except Exception as e:
        log(f"getFile failed: {e}")
    return None


def download_file(url: str, suffix: str) -> str | None:
    """Download a file to a temp path, return path."""
    try:
        with urlopen(url, timeout=30) as resp:
            data = resp.read()
        fd, path = tempfile.mkstemp(suffix=suffix)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return path
    except Exception as e:
        log(f"download_file failed: {e}")
    return None


def transcribe_voice(ogg_path: str) -> str | None:
    """Transcribe an OGG voice file using Groq Whisper API."""
    if not GROQ_API_KEY:
        log("GROQ_API_KEY not set, cannot transcribe")
        return None

    boundary = f"----WebKitFormBoundary{os.urandom(8).hex()}"

    try:
        with open(ogg_path, "rb") as f:
            file_data = f.read()

        parts = []
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(b'Content-Disposition: form-data; name="file"; filename="audio.ogg"\r\n')
        parts.append(b"Content-Type: audio/ogg\r\n\r\n")
        parts.append(file_data)
        parts.append(b"\r\n")
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(b'Content-Disposition: form-data; name="model"\r\n\r\n')
        parts.append(b"whisper-large-v3-turbo\r\n")
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(b'Content-Disposition: form-data; name="language"\r\n\r\n')
        parts.append(WHISPER_LANGUAGE.encode() + b"\r\n")
        parts.append(f"--{boundary}--\r\n".encode())

        body = b"".join(parts)

        req = Request(
            "https://api.groq.com/openai/v1/audio/transcriptions",
            data=body,
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
        )
        with urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return data.get("text", "").strip() or None
    except Exception as e:
        log(f"transcribe_voice (Groq API) failed: {e}")
    return None


def send_typing(chat_id: str):
    """Send 'typing' chat action so owner sees we are working."""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendChatAction"
    payload = {"chat_id": chat_id, "action": "typing"}
    try:
        req = Request(url, data=json.dumps(payload).encode(),
                      headers={"Content-Type": "application/json"})
        urlopen(req, timeout=5)
    except Exception:
        pass


def load_recent_conversation(n: int = 8) -> str:
    """Load last N exchanges from today's JSONL conversation log."""
    date_str = time.strftime("%Y-%m-%d")
    log_path = os.path.join(LOG_DIR, f"{date_str}.jsonl")
    if not os.path.exists(log_path):
        return ""
    entries = []
    try:
        with open(log_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    except Exception:
        return ""
    if not entries:
        return ""
    recent = entries[-n:]
    lines = ["## Previous Conversation (today)"]
    for e in recent:
        lines.append(f"**User:** {e.get('user', '')}")
        lines.append(f"**Assistant:** {e.get('assistant', '')}")
    lines.append("")
    return "\n".join(lines) + "\n"


def build_prompt(user_message: str) -> str:
    """Build the relay prompt with user's message and recent conversation history."""
    history = load_recent_conversation(n=8)
    try:
        with open(PROMPT_TEMPLATE) as f:
            template = f.read()
        return (template
                .replace("{CONVERSATION_HISTORY}", history)
                .replace("{USER_MESSAGE}", user_message))
    except FileNotFoundError:
        prefix = f"{history}\n" if history else ""
        return f"{prefix}Respond to this Telegram message from the user:\n\n{user_message}"


def get_system_context() -> str:
    """Load personality files (IDENTITY.md, SOUL.md, USER.md) as system context."""
    parts = []
    for fname in ("IDENTITY.md", "SOUL.md", "USER.md"):
        path = os.path.join(PERSONALITY_DIR, fname)
        try:
            with open(path) as f:
                content = f.read().strip()
                if content:
                    parts.append(content)
        except FileNotFoundError:
            pass
    return "\n\n".join(parts)


def call_cli(prompt: str, system_context: str) -> str:
    """Call the configured CLI command and return the response."""
    env = os.environ.copy()
    env.pop("CLAUDECODE", None)

    cmd_parts = CLI_CMD.split()
    cmd = list(cmd_parts)

    # Add CLI-specific flags (each CLI has its own interface)
    cli_name = cmd_parts[0].lower()
    if "claude" in cli_name:
        cmd += ["--dangerously-skip-permissions", "--no-session-persistence"]
        if system_context:
            cmd += ["--append-system-prompt", system_context]
    elif "codex" in cli_name:
        cmd += ["--quiet"]
    elif "opencode" in cli_name:
        cmd += ["run", "--agent", "build"]
    elif "kimi" in cli_name:
        cmd += ["--yes"]

    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            timeout=CLI_TIMEOUT,
            cwd=PROJECT_ROOT,
            env=env,
        )
        output = result.stdout.strip()
        if not output:
            output = result.stderr.strip()
        return output or "(empty response)"
    except subprocess.TimeoutExpired:
        return "Timeout -- processing took too long. Try a simpler request."
    except FileNotFoundError:
        return f"Error: CLI command not found: {cmd_parts[0]}"
    except Exception as e:
        return f"Error: {e}"


def is_active_hours() -> bool:
    hour = int(time.strftime("%H"))
    return ACTIVE_START <= hour < ACTIVE_END


def process_message(update: dict):
    """Process a single Telegram message from owner."""
    msg = update.get("message", {})
    msg_id = msg.get("message_id")
    text = msg.get("text", "")
    voice = msg.get("voice") or msg.get("audio")
    chat_id = str(msg.get("chat", {}).get("id", ""))

    # Only process owner's messages
    if chat_id != CHAT_ID:
        return

    # Handle voice messages via transcription
    if voice and not text:
        file_id = voice.get("file_id")
        log(f"Voice message received (file_id: {file_id})")
        send_typing(chat_id)
        file_url = get_file_url(file_id)
        if not file_url:
            send_message("Failed to download voice message.", reply_to=msg_id)
            return
        ogg_path = download_file(file_url, ".ogg")
        if not ogg_path:
            send_message("Failed to download audio file.", reply_to=msg_id)
            return
        try:
            text = transcribe_voice(ogg_path)
        finally:
            os.unlink(ogg_path)
        if not text:
            send_message("Failed to transcribe voice message.", reply_to=msg_id)
            return
        log(f"Transcribed: {text[:80]}")
        text = f"[Voice message] {text}"

    if not text:
        return

    log(f"Message from owner: {text[:80]}...")

    send_typing(chat_id)

    prompt = build_prompt(text)
    system_context = get_system_context()
    response = call_cli(prompt, system_context)

    log(f"CLI response ({len(response)} chars): {response[:80]}...")

    log_conversation(text, response, msg_id)

    success = send_message(response, reply_to=msg_id)
    if success:
        log("Reply sent successfully")
    else:
        log("Failed to send reply")


def main():
    global last_update_id, running

    if not BOT_TOKEN or not CHAT_ID:
        log("ERROR: TELEGRAM_BOT_TOKEN and PA_OWNER_CHAT_ID must be set")
        sys.exit(1)

    log(f"Telegram Relay starting (poll every {POLL_INTERVAL}s, active {ACTIVE_START}-{ACTIVE_END})")
    log(f"Owner chat_id: {CHAT_ID}")
    log(f"CLI command: {CLI_CMD}, timeout: {CLI_TIMEOUT}s")

    # Bootstrap: get current update_id to skip old messages
    updates = get_updates(0)
    if updates:
        last_update_id = updates[-1]["update_id"] + 1
        log(f"Skipping {len(updates)} old updates, starting from {last_update_id}")

    while running:
        if not is_active_hours():
            time.sleep(60)
            continue

        updates = get_updates(last_update_id)

        for update in updates:
            uid = update["update_id"]
            last_update_id = uid + 1

            if "message" in update:
                process_message(update)

        # Short sleep between polls (getUpdates already blocks for 30s if no updates)
        if not updates:
            time.sleep(POLL_INTERVAL)

    log("Relay stopped")


if __name__ == "__main__":
    main()
