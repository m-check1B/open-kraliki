#!/usr/bin/env python3
"""send-telegram.py — Send a message to the owner via Telegram Bot API.

Usage:
  python3 send-telegram.py "Your message here"
  echo "message" | python3 send-telegram.py

Env vars:
  TELEGRAM_BOT_TOKEN  — Telegram bot token (required)
  PA_OWNER_CHAT_ID    — Owner's Telegram chat ID (required)
"""

import json
import os
import sys
from urllib.error import URLError
from urllib.request import Request, urlopen

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("PA_OWNER_CHAT_ID", "")


def send_message(text: str) -> bool:
    """Send a Telegram message. Returns True on success."""
    if not BOT_TOKEN or not CHAT_ID:
        print("ERROR: TELEGRAM_BOT_TOKEN and PA_OWNER_CHAT_ID must be set", file=sys.stderr)
        return False

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "Markdown",
        "disable_web_page_preview": True,
    }

    try:
        req = Request(
            url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
            if result.get("ok"):
                return True
            print(f"Telegram API error: {result}", file=sys.stderr)
            return False
    except URLError as e:
        print(f"Telegram send failed: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
    elif not sys.stdin.isatty():
        text = sys.stdin.read().strip()
    else:
        print("Usage: send-telegram.py 'message' OR echo 'message' | send-telegram.py", file=sys.stderr)
        sys.exit(1)

    if not text:
        print("Empty message, skipping", file=sys.stderr)
        sys.exit(0)

    success = send_message(text)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
