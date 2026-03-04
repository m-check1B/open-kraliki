#!/usr/bin/env python3
"""precheck.py — Search Linear for open issues matching a prefix (no LLM).

Finds issues filed by an automated pipeline that need fixing.
Outputs JSON to stdout. Exit 0 = issues found, exit 1 = no issues, exit 2 = error.

Env vars:
  LINEAR_API_KEY        — Linear API key (required)
  LINEAR_TEAM_ID        — Team UUID to query (required)
  ISSUE_PREFIX          — Title prefix to match, e.g. "[AI-QA]" (default: "[AI-QA]")
  COMMIT_PREFIX         — Additional title prefix to match (optional)
  FIXER_SLOT            — Slot for splitting work: "0"/"1"/"2"/"3" (mod 4) or "even"/"odd" (mod 2)
  QA_FIXER_STATE_FILE   — Path to JSON state file tracking attempted issues
  MAX_ISSUES            — Max issues to return per cycle (default: 10)
  SKIP_LABELS           — Comma-separated label names to skip (default: "wont-fix,manual,flaky")
"""

import glob
import hashlib
import json
import os
import sys
from datetime import datetime
from urllib.error import URLError
from urllib.request import Request, urlopen

LINEAR_API_URL = "https://api.linear.app/graphql"
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")
LINEAR_TEAM_ID = os.environ.get("LINEAR_TEAM_ID", "")
ISSUE_PREFIX = os.environ.get("ISSUE_PREFIX", "[AI-QA]")
COMMIT_PREFIX = os.environ.get("COMMIT_PREFIX", "")
FIXER_SLOT = os.environ.get("FIXER_SLOT", "")
try:
    MAX_ISSUES = int(os.environ.get("MAX_ISSUES", "10"))
except ValueError:
    print("WARNING: MAX_ISSUES is not a valid integer, using default 10", file=sys.stderr)
    MAX_ISSUES = 10

SKIP_LABELS = {
    s.strip().lower()
    for s in os.environ.get("SKIP_LABELS", "wont-fix,manual,flaky").split(",")
    if s.strip()
}

STATE_FILE = os.environ.get(
    "QA_FIXER_STATE_FILE",
    os.path.expanduser("~/logs/claude-fixer/state.json"),
)


def gql(query: str, variables: dict | None = None) -> dict:
    """Execute a GraphQL query against Linear API."""
    if not LINEAR_API_KEY:
        print("ERROR: LINEAR_API_KEY not set", file=sys.stderr)
        sys.exit(2)
    if not LINEAR_TEAM_ID:
        print("ERROR: LINEAR_TEAM_ID not set", file=sys.stderr)
        sys.exit(2)
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = Request(
        LINEAR_API_URL,
        data=payload,
        headers={"Content-Type": "application/json", "Authorization": LINEAR_API_KEY},
    )
    with urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
        if "errors" in data:
            print(f"GraphQL error: {data['errors']}", file=sys.stderr)
            sys.exit(2)
        return data.get("data", {})


def load_state() -> dict:
    """Load state file tracking attempted issues."""
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"attempted": {}, "last_cycle": ""}


def search_issues() -> list[dict]:
    """Search Linear for open issues in the configured team."""
    query = """
    query {
      issues(
        filter: {
          team: { id: { eq: "%s" } }
          state: { type: { in: ["backlog", "unstarted", "started"] } }
        }
        first: 50
        orderBy: createdAt
      ) {
        nodes {
          id
          identifier
          title
          description
          priority
          url
          state { name }
          labels { nodes { name } }
          createdAt
        }
      }
    }
    """ % LINEAR_TEAM_ID
    data = gql(query)
    return data.get("issues", {}).get("nodes", [])


def _matches_prefix(title: str) -> bool:
    """Check whether a title matches the configured prefixes."""
    prefixes = [ISSUE_PREFIX]
    if COMMIT_PREFIX:
        prefixes.append(COMMIT_PREFIX)
    return any(title.startswith(p) for p in prefixes)


def filter_issues(issues: list[dict], state: dict) -> list[dict]:
    """Filter to matching-prefix issues, excluding skipped labels and already-attempted."""
    result = []
    for issue in issues:
        title = issue.get("title", "")
        if not _matches_prefix(title):
            continue

        # Skip issues with excluded labels
        labels = {lbl["name"].lower() for lbl in issue.get("labels", {}).get("nodes", [])}
        if labels & SKIP_LABELS:
            continue

        # Skip issues already attempted too many times
        issue_id = issue["identifier"]
        attempted = state.get("attempted", {}).get(issue_id, {})
        fail_count = attempted.get("fail_count", 0)
        if fail_count >= 3:
            continue

        result.append({
            "id": issue["id"],
            "identifier": issue["identifier"],
            "title": title,
            "description": issue.get("description", "") or "",
            "priority": issue.get("priority", 0),
            "url": issue.get("url", ""),
            "state": issue.get("state", {}).get("name", ""),
        })

        if len(result) >= MAX_ISSUES:
            break

    return result


def _load_all_fixer_states() -> list[dict]:
    """Load state files from ALL fixers (for escalation across CLIs)."""
    states = []
    for path in glob.glob(os.path.expanduser("~/logs/*-fixer/state.json")):
        try:
            with open(path) as f:
                states.append(json.load(f))
        except (FileNotFoundError, json.JSONDecodeError):
            pass
    return states


def _issue_hash(identifier: str) -> int:
    """Stable hash for slot assignment (deterministic across runs)."""
    return int(hashlib.md5(identifier.encode()).hexdigest(), 16)


def _get_escalation_level(issue_id: str, all_states: list[dict]) -> int:
    """Count how many fixers have maxed out (fail_count >= 3) on this issue.

    Each max-out shifts the issue to the next slot in line, so a different
    CLI gets a chance to fix it.
    """
    level = 0
    for state in all_states:
        fc = state.get("attempted", {}).get(issue_id, {}).get("fail_count", 0)
        if fc >= 3:
            level += 1
    return level


def split_by_slot(issues: list[dict]) -> list[dict]:
    """Split issues between fixers based on FIXER_SLOT with automatic escalation.

    Each issue hashes to a primary slot. If that slot's fixer maxes out (3 fails),
    the issue escalates to the next slot so a different CLI gets a chance.

    Example with 4 fixers:
      PROJ-42 hashes to slot 0 (Claude). Claude fails 3 times.
      → escalation_level=1 → new slot = (hash+1) % 4 = slot 1 (Codex gets it)
      Codex fails 3 times → escalation_level=2 → slot 2 (Opencode gets it)
      All 4 fail → issue is truly stuck (all state files show fail_count >= 3)
    """
    fixer_count = int(os.environ.get("FIXER_COUNT", "4"))
    if FIXER_SLOT.isdigit():
        slot = int(FIXER_SLOT)
        all_states = _load_all_fixer_states()
        result = []
        for q in issues:
            h = _issue_hash(q["identifier"])
            escalation = _get_escalation_level(q["identifier"], all_states)
            assigned_slot = (h + escalation) % fixer_count
            if assigned_slot == slot:
                result.append(q)
        return result
    elif FIXER_SLOT == "even":
        return [q for q in issues if _issue_hash(q["identifier"]) % 2 == 0]
    elif FIXER_SLOT == "odd":
        return [q for q in issues if _issue_hash(q["identifier"]) % 2 == 1]
    return issues


def main():
    try:
        state = load_state()
        all_issues = search_issues()
        matched = filter_issues(all_issues, state)
        matched = split_by_slot(matched)

        total_open = len([i for i in all_issues if _matches_prefix(i.get("title", ""))])

        output = {
            "timestamp": datetime.now().isoformat(),
            "total_open": total_open,
            "issues": matched,
            "has_issues": len(matched) > 0,
        }

        print(json.dumps(output, indent=2, ensure_ascii=False))
        sys.exit(0 if matched else 1)

    except URLError as e:
        print(json.dumps({"error": f"Linear API failed: {e}"}), file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(json.dumps({"error": f"Precheck failed: {e}"}), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
