#!/usr/bin/env python3
"""linear-tool.py — Linear API tool for automation pipelines.

Usage:
  python3 linear-tool.py list [--team KEY] [--mine] [--urgent]
  python3 linear-tool.py get ISSUE-123
  python3 linear-tool.py create "Title" [--desc "Description"] [--team KEY] [--priority 1]
  python3 linear-tool.py update ISSUE-123 [--status "In Progress"] [--priority 2] [--title "New title"]
  python3 linear-tool.py comment ISSUE-123 "Comment text"
  python3 linear-tool.py search "query"

Priority levels: 0=No, 1=Urgent, 2=High, 3=Medium, 4=Low

Env vars:
  LINEAR_API_KEY    — Linear API key (required)
  LINEAR_TEAM_KEY   — Default team key, e.g. "PROJ" (required)
  LINEAR_TEAM_ID    — Team UUID for LINEAR_TEAM_KEY (required)
  LINEAR_TEAMS      — Additional teams as JSON: {"KEY2": "uuid2", ...} (optional)
"""

import argparse
import json
import os
import sys
from urllib.error import URLError
from urllib.request import Request, urlopen

LINEAR_API_URL = "https://api.linear.app/graphql"
LINEAR_API_KEY = os.environ.get("LINEAR_API_KEY", "")

# Build TEAMS dict from env vars
_DEFAULT_KEY = os.environ.get("LINEAR_TEAM_KEY", "")
_DEFAULT_ID = os.environ.get("LINEAR_TEAM_ID", "")

TEAMS: dict[str, str] = {}
if _DEFAULT_KEY and _DEFAULT_ID:
    TEAMS[_DEFAULT_KEY.upper()] = _DEFAULT_ID

# Merge additional teams from LINEAR_TEAMS JSON env var
_extra = os.environ.get("LINEAR_TEAMS", "")
if _extra:
    try:
        extra_teams = json.loads(_extra)
        for k, v in extra_teams.items():
            TEAMS[k.upper()] = v
    except (json.JSONDecodeError, AttributeError):
        pass

DEFAULT_TEAM = _DEFAULT_KEY.upper() if _DEFAULT_KEY else ""

PRIORITY_NAMES = {0: "No priority", 1: "Urgent", 2: "High", 3: "Medium", 4: "Low"}
PRIORITY_EMOJI = {0: "⚪", 1: "🔴", 2: "🟠", 3: "🟡", 4: "🟢"}


def gql(query: str, variables: dict | None = None) -> dict:
    """Execute a GraphQL query against Linear API."""
    if not LINEAR_API_KEY:
        print("ERROR: LINEAR_API_KEY not set", file=sys.stderr)
        sys.exit(1)
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = Request(
        LINEAR_API_URL,
        data=payload,
        headers={"Content-Type": "application/json", "Authorization": LINEAR_API_KEY},
    )
    try:
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            if "errors" in data:
                print(f"GraphQL error: {data['errors']}", file=sys.stderr)
                sys.exit(1)
            return data.get("data", {})
    except URLError as e:
        print(f"Network error: {e}", file=sys.stderr)
        sys.exit(1)


def _get_team_id(team_key: str) -> str:
    """Resolve a team key to its UUID, falling back to default."""
    team_id = TEAMS.get(team_key.upper())
    if team_id:
        return team_id
    if DEFAULT_TEAM and DEFAULT_TEAM in TEAMS:
        return TEAMS[DEFAULT_TEAM]
    print(f"ERROR: Unknown team '{team_key}' and no default configured", file=sys.stderr)
    sys.exit(1)


def fmt_issue(issue: dict, short: bool = False) -> str:
    """Format a Linear issue for display."""
    pri = issue.get("priority", 0)
    emoji = PRIORITY_EMOJI.get(pri, "⚪")
    state = issue.get("state", {}).get("name", "?")
    ident = issue.get("identifier", "?")
    title = issue.get("title", "?")
    if short:
        return f"{emoji} [{ident}] {title} ({state})"
    desc = issue.get("description", "") or ""
    desc_preview = (desc[:150] + "...") if len(desc) > 150 else desc
    assignee = issue.get("assignee", {})
    assignee_name = assignee.get("name", "Unassigned") if assignee else "Unassigned"
    url = issue.get("url", "")
    lines = [
        f"{emoji} **{ident}**: {title}",
        f"   State: {state} | Priority: {PRIORITY_NAMES.get(pri, 'Unknown')} | Assignee: {assignee_name}",
    ]
    if desc_preview:
        lines.append(f"   {desc_preview}")
    if url:
        lines.append(f"   {url}")
    return "\n".join(lines)


def cmd_list(args):
    """List open issues for a team."""
    team_id = _get_team_id(args.team)
    filters = [
        f'team: {{ id: {{ eq: "{team_id}" }} }}',
        'state: { type: { in: ["started", "unstarted", "backlog"] } }',
    ]
    if args.mine:
        filters.append("assignee: { isMe: { eq: true } }")
    if args.urgent:
        filters.append("priority: { lte: 2 }")

    filter_str = "\n        ".join(filters)
    query = f"""
    query {{
      issues(
        filter: {{
          {filter_str}
        }}
        first: {args.limit}
        orderBy: updatedAt
      ) {{
        nodes {{
          identifier title priority url
          state {{ name }}
          assignee {{ name }}
          description
          updatedAt
        }}
      }}
    }}
    """
    data = gql(query)
    issues = data.get("issues", {}).get("nodes", [])
    if not issues:
        print("No issues found.")
        return
    print(f"Found {len(issues)} issues:\n")
    for issue in issues:
        print(fmt_issue(issue, short=True))


def cmd_get(args):
    """Get full details for a specific issue."""
    issue_id = _resolve_issue_id(args.id)
    if not issue_id:
        print(f"Issue {args.id} not found.")
        return

    query = """
    query($id: String!) {
      issue(id: $id) {
        identifier title priority url description
        state { name }
        assignee { name }
        labels { nodes { name } }
        comments { nodes { body createdAt user { name } } }
        createdAt updatedAt
      }
    }
    """
    data = gql(query, {"id": issue_id})
    issue = data.get("issue")
    if not issue:
        print(f"Issue {args.id} not found.")
        return
    print(fmt_issue(issue))
    comments = issue.get("comments", {}).get("nodes", [])
    if comments:
        print(f"\nComments ({len(comments)}):")
        for c in comments[-3:]:
            user = c.get("user", {}).get("name", "?")
            body = c.get("body", "")[:200]
            print(f"  [{user}]: {body}")


def cmd_create(args):
    """Create a new issue."""
    team_id = _get_team_id(args.team)
    mutation = """
    mutation($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue { identifier title url }
      }
    }
    """
    inp = {
        "teamId": team_id,
        "title": args.title,
    }
    if args.desc:
        inp["description"] = args.desc
    if args.priority is not None:
        inp["priority"] = args.priority
    data = gql(mutation, {"input": inp})
    result = data.get("issueCreate", {})
    if result.get("success"):
        issue = result.get("issue", {})
        print(f"Created: [{issue['identifier']}] {issue['title']}")
        print(f"   {issue['url']}")
    else:
        print("Failed to create issue.")


def _resolve_issue_id(identifier: str) -> str | None:
    """Resolve TEAM-123 style identifier to internal UUID."""
    # If it looks like a UUID already, return it
    if "-" in identifier and len(identifier) > 10 and not identifier.split("-")[1].isdigit():
        return identifier

    # Extract team slug and number
    parts = identifier.split("-", 1)
    if len(parts) != 2 or not parts[1].isdigit():
        return identifier

    team_slug = parts[0].upper()
    number = parts[1]

    team_id = TEAMS.get(team_slug)
    if not team_id:
        if DEFAULT_TEAM and DEFAULT_TEAM in TEAMS:
            team_id = TEAMS[DEFAULT_TEAM]
        else:
            return None

    query = """
    query {
      issues(
        filter: {
          team: { id: { eq: "%s" } }
          number: { eq: %s }
        }
        first: 1
      ) {
        nodes { id identifier }
      }
    }
    """ % (team_id, number)
    data = gql(query)
    nodes = data.get("issues", {}).get("nodes", [])
    return nodes[0]["id"] if nodes else None


def cmd_update(args):
    """Update an existing issue."""
    issue_id = _resolve_issue_id(args.id)
    if not issue_id:
        print(f"Issue {args.id} not found.")
        return

    inp = {}
    if args.title:
        inp["title"] = args.title
    if args.priority is not None:
        inp["priority"] = args.priority
    if args.status:
        # Determine team from the identifier or use default
        parts = args.id.split("-", 1)
        team_slug = parts[0].upper() if len(parts) == 2 and parts[1].isdigit() else DEFAULT_TEAM
        team_id = _get_team_id(team_slug)
        states_data = gql(
            'query { team(id: "%s") { states { nodes { id name } } } }' % team_id
        )
        states = states_data.get("team", {}).get("states", {}).get("nodes", [])
        matched = [s for s in states if args.status.lower() in s["name"].lower()]
        if not matched:
            print(f"State '{args.status}' not found. Available: {[s['name'] for s in states]}")
            return
        inp["stateId"] = matched[0]["id"]

    if not inp:
        print("Nothing to update.")
        return

    mutation = """
    mutation($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue { identifier title state { name } }
      }
    }
    """
    data = gql(mutation, {"id": issue_id, "input": inp})
    result = data.get("issueUpdate", {})
    if result.get("success"):
        issue = result.get("issue", {})
        state_name = issue.get("state", {}).get("name", "?")
        print(f"Updated [{issue['identifier']}]: {issue['title']} -> {state_name}")
    else:
        print("Update failed.")


def cmd_comment(args):
    """Add a comment to an issue."""
    issue_id = _resolve_issue_id(args.id)
    if not issue_id:
        print(f"Issue {args.id} not found.")
        return

    mutation = """
    mutation($issueId: String!, $body: String!) {
      commentCreate(input: { issueId: $issueId, body: $body }) {
        success
        comment { id }
      }
    }
    """
    data = gql(mutation, {"issueId": issue_id, "body": args.body})
    if data.get("commentCreate", {}).get("success"):
        print(f"Comment added to {args.id}")
    else:
        print("Failed to add comment.")


def cmd_search(args):
    """Search issues by title or identifier."""
    team_id = _get_team_id(DEFAULT_TEAM) if DEFAULT_TEAM else None
    if not team_id:
        print("ERROR: No default team configured (set LINEAR_TEAM_KEY + LINEAR_TEAM_ID)", file=sys.stderr)
        sys.exit(1)

    query = """
    query {
      issues(
        filter: {
          team: { id: { eq: "%s" } }
        }
        first: 50
        orderBy: updatedAt
      ) {
        nodes {
          identifier title priority url
          state { name }
          assignee { name }
        }
      }
    }
    """ % team_id
    data = gql(query)
    all_issues = data.get("issues", {}).get("nodes", [])
    q = args.query.lower()
    issues = [i for i in all_issues if q in i.get("title", "").lower() or q in i.get("identifier", "").lower()]
    if not issues:
        print("No results.")
        return
    print(f"Found {len(issues)} results:\n")
    for issue in issues:
        print(fmt_issue(issue, short=True))


def main():
    parser = argparse.ArgumentParser(description="Linear API tool for automation pipelines")
    sub = parser.add_subparsers(dest="cmd")

    p_list = sub.add_parser("list", help="List issues")
    p_list.add_argument("--team", default=DEFAULT_TEAM)
    p_list.add_argument("--mine", action="store_true")
    p_list.add_argument("--urgent", action="store_true")
    p_list.add_argument("--limit", type=int, default=15)

    p_get = sub.add_parser("get", help="Get issue details")
    p_get.add_argument("id")

    p_create = sub.add_parser("create", help="Create issue")
    p_create.add_argument("title")
    p_create.add_argument("--desc", default="")
    p_create.add_argument("--team", default=DEFAULT_TEAM)
    p_create.add_argument("--priority", type=int, default=None)

    p_update = sub.add_parser("update", help="Update issue")
    p_update.add_argument("id")
    p_update.add_argument("--title")
    p_update.add_argument("--status")
    p_update.add_argument("--priority", type=int, default=None)

    p_comment = sub.add_parser("comment", help="Add comment")
    p_comment.add_argument("id")
    p_comment.add_argument("body")

    p_search = sub.add_parser("search", help="Search issues")
    p_search.add_argument("query")

    args = parser.parse_args()
    if not args.cmd:
        parser.print_help()
        sys.exit(1)

    cmds = {
        "list": cmd_list,
        "get": cmd_get,
        "create": cmd_create,
        "update": cmd_update,
        "comment": cmd_comment,
        "search": cmd_search,
    }
    cmds[args.cmd](args)


if __name__ == "__main__":
    main()
