#!/usr/bin/env python3
"""heartbeat-precheck.py — Cheap pre-check for heartbeat automation (no LLM calls).

Checks Linear issues, Calendar events, and Telegram unread messages.
Outputs JSON to stdout. Exit 0 = findings exist, exit 1 = nothing found.

Env vars:
  LINEAR_API_KEY      — Linear API key (required for Linear check)
  LINEAR_TEAM_ID      — Team UUID to query (required for Linear check)
  TELEGRAM_BOT_TOKEN  — Telegram bot token (required for Telegram check)
  PA_OWNER_CHAT_ID    — Owner's Telegram chat ID (required for Telegram check)
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime
from urllib.error import URLError
from urllib.request import Request, urlopen

LINEAR_API_URL = "https://api.linear.app/graphql"
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
LINEAR_TEAM_ID = os.environ.get("LINEAR_TEAM_ID", "")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
PA_OWNER_CHAT_ID = os.environ.get("PA_OWNER_CHAT_ID", "")


def check_linear() -> list[dict]:
    """Check Linear for open issues assigned to me or urgent unassigned items."""
    if not LINEAR_API_KEY:
        return [{"error": "LINEAR_API_KEY not set"}]
    if not LINEAR_TEAM_ID:
        return [{"error": "LINEAR_TEAM_ID not set"}]

    query = """
    query {
      mine: issues(
        filter: {
          team: { id: { eq: "%s" } }
          state: { type: { in: ["started", "unstarted", "backlog"] } }
          assignee: { isMe: { eq: true } }
        }
        first: 10
        orderBy: updatedAt
      ) {
        nodes {
          identifier
          title
          priority
          state { name }
          updatedAt
        }
      }
      unassigned: issues(
        filter: {
          team: { id: { eq: "%s" } }
          state: { type: { in: ["started", "unstarted", "backlog"] } }
          assignee: { null: true }
          priority: { lte: 2 }
        }
        first: 5
        orderBy: updatedAt
      ) {
        nodes {
          identifier
          title
          priority
          state { name }
          updatedAt
        }
      }
    }
    """ % (LINEAR_TEAM_ID, LINEAR_TEAM_ID)

    try:
        req = Request(
            LINEAR_API_URL,
            data=json.dumps({"query": query}).encode(),
            headers={
                "Content-Type": "application/json",
                "Authorization": LINEAR_API_KEY,
            },
        )
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())

        d = data.get("data", {})
        all_issues = d.get("mine", {}).get("nodes", []) + d.get("unassigned", {}).get("nodes", [])

        # Deduplicate by identifier
        seen = set()
        issues = []
        for i in all_issues:
            if i["identifier"] not in seen:
                seen.add(i["identifier"])
                issues.append(i)

        results = []
        for issue in issues:
            priority = issue.get("priority", 0)
            label = {1: "urgent", 2: "high", 3: "normal", 4: "low"}.get(priority, "none")
            results.append({
                "id": issue["identifier"],
                "title": issue["title"],
                "priority": label,
                "status": issue["state"]["name"],
                "updated": issue["updatedAt"],
            })
        return results
    except (URLError, Exception) as e:
        return [{"error": f"Linear API failed: {e}"}]


def check_calendar() -> list[dict]:
    """Check macOS Calendar for upcoming events via icalBuddy.

    icalBuddy uses EventKit internally, so it works from launchd without
    TCC/sandbox issues (unlike direct sqlite3 access to the Calendar DB).
    """
    try:
        result = subprocess.run(
            [
                "icalBuddy",
                "-n",                 # only events from now on
                "-b", "",             # no bullet prefix
                "-nc",                # no calendar names
                "-nrd",               # no relative dates (use absolute)
                "-ea",                # exclude all-day events
                "-npn",               # no property names
                "-iep", "title,datetime",
                "-po", "datetime,title",
                "-ps", "/ | /",       # property separator
                "-df", "%Y-%m-%d",
                "-tf", "%H:%M",
                "eventsToday",
            ],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return [{"error": f"icalBuddy failed: {result.stderr.strip()}"}]

        events = []
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if not line:
                continue
            # Format: "2026-02-27 at 16:00 - 17:00 | Event Title"
            parts = line.split(" | ", 1)
            if len(parts) == 2:
                datetime_part, title = parts[0].strip(), parts[1].strip()
                today = datetime.now().strftime("%Y-%m-%d")
                # Full: "2026-02-27 at 16:00 - 17:00"
                m = re.match(r"(\d{4}-\d{2}-\d{2}) at (\d{2}:\d{2}) - (\d{2}:\d{2})", datetime_part)
                if m:
                    date, start_t, end_t = m.groups()
                    events.append({"title": title, "start": f"{date} {start_t}", "end": f"{date} {end_t}"})
                else:
                    # Today-only: "16:00 - 17:00"
                    m2 = re.match(r"(\d{2}:\d{2}) - (\d{2}:\d{2})", datetime_part)
                    if m2:
                        events.append({"title": title, "start": f"{today} {m2.group(1)}", "end": f"{today} {m2.group(2)}"})
                    else:
                        events.append({"title": title, "start": datetime_part, "end": ""})
            else:
                events.append({"title": line, "start": "", "end": ""})
        return events
    except FileNotFoundError:
        return [{"error": "icalBuddy not installed (brew install ical-buddy)"}]
    except Exception as e:
        return [{"error": f"Calendar check failed: {e}"}]


def check_telegram() -> list[dict]:
    """Check Telegram bot API for unread updates from the owner."""
    if not TELEGRAM_BOT_TOKEN:
        return [{"error": "TELEGRAM_BOT_TOKEN not set"}]

    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getUpdates?limit=10&timeout=0"
        req = Request(url)
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())

        updates = data.get("result", [])
        if not updates:
            return []

        # Filter to owner's messages only
        owner_msgs = []
        for u in updates:
            msg = u.get("message", {})
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if chat_id == PA_OWNER_CHAT_ID and msg.get("text"):
                owner_msgs.append({
                    "text": msg["text"][:100],
                    "date": msg.get("date", 0),
                })
        return owner_msgs
    except (URLError, Exception) as e:
        return [{"error": f"Telegram API failed: {e}"}]


def main():
    findings = {
        "timestamp": datetime.now().isoformat(),
        "linear": check_linear(),
        "calendar": check_calendar(),
        "telegram": check_telegram(),
    }

    # Determine if there is anything worth reporting
    has_findings = False
    for key in ("linear", "calendar", "telegram"):
        items = findings[key]
        real_items = [i for i in items if "error" not in i]
        if real_items:
            has_findings = True
            break

    findings["has_findings"] = has_findings
    print(json.dumps(findings, indent=2, ensure_ascii=False))

    sys.exit(0 if has_findings else 1)


if __name__ == "__main__":
    main()
