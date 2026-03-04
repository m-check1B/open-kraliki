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
MAX_ISSUES = int(os.environ.get("MAX_ISSUES", "10"))

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


def split_by_slot(issues: list[dict]) -> list[dict]:
    """Split issues between fixers based on FIXER_SLOT."""
    if FIXER_SLOT in ("0", "1", "2"):
        slot = int(FIXER_SLOT)
        return [q for idx, q in enumerate(issues) if idx % 3 == slot]
    elif FIXER_SLOT == "even":
        return [q for idx, q in enumerate(issues) if idx % 2 == 0]
    elif FIXER_SLOT == "odd":
        return [q for idx, q in enumerate(issues) if idx % 2 == 1]
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
