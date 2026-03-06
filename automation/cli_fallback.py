#!/usr/bin/env python3
"""Shared CLI fallback runner for automation flows."""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path


DEFAULT_FALLBACKS = "codex,opencode,kimi"


def _split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def build_cli_chain(primary: str, fallbacks: str) -> list[str]:
    chain: list[str] = []
    for raw in [primary, *_split_csv(fallbacks)]:
        if raw and raw not in chain:
            chain.append(raw)
    return chain


def load_system_context(system_dir: str | None) -> str:
    if not system_dir:
        return ""

    path = Path(system_dir)
    if not path.is_dir():
        return ""

    parts: list[str] = []
    for item in sorted(path.glob("*.md")):
        try:
            content = item.read_text().strip()
        except OSError:
            continue
        if content:
            parts.append(content)
    return "\n\n".join(parts)


def _which(name: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _ensure_arg(cmd: list[str], *args: str) -> None:
    for arg in args:
        if arg not in cmd:
            cmd.append(arg)


def prepare_command(cli_cmd: str, cwd: str, system_context: str) -> list[str]:
    cmd = shlex.split(cli_cmd)
    if not cmd:
        raise ValueError("empty CLI command")

    cli_name = os.path.basename(cmd[0]).lower()

    if "claude" in cli_name:
        _ensure_arg(cmd, "--print", "--dangerously-skip-permissions", "--no-session-persistence")
        if system_context and "--append-system-prompt" not in cmd:
            cmd.extend(["--append-system-prompt", system_context])
        if "--allowedTools" not in cmd and "--allowed-tools" not in cmd:
            cmd.extend(["--allowedTools", "Read,Grep,Glob"])
    elif "codex" in cli_name:
        if "exec" not in cmd[1:]:
            cmd.append("exec")
        if "-C" not in cmd and "--cd" not in cmd:
            cmd.extend(["-C", cwd])
        _ensure_arg(
            cmd,
            "--skip-git-repo-check",
            "--ephemeral",
            "--dangerously-bypass-approvals-and-sandbox",
        )
    elif "opencode" in cli_name:
        if "run" not in cmd[1:]:
            cmd.append("run")
        if "--agent" not in cmd:
            cmd.extend(["--agent", "build"])
        if "--dir" not in cmd:
            cmd.extend(["--dir", cwd])
    elif "kimi" in cli_name:
        _ensure_arg(cmd, "--yes")

    return cmd


def _looks_rate_limited(output: str) -> bool:
    lowered = output.lower()
    return "hit your limit" in lowered or "rate limit" in lowered or "quota" in lowered


def run_cli_chain(
    prompt: str,
    primary: str,
    fallbacks: str = DEFAULT_FALLBACKS,
    cwd: str | None = None,
    system_context: str = "",
    timeout: int = 120,
) -> tuple[str, str]:
    cwd = cwd or os.getcwd()
    last_output = ""

    for cli_cmd in build_cli_chain(primary, fallbacks):
        base = shlex.split(cli_cmd)[0] if cli_cmd.strip() else cli_cmd
        if not base or not _which(base):
            print(f"[cli-fallback] skipping {cli_cmd}: not installed", file=sys.stderr)
            continue

        cmd = prepare_command(cli_cmd, cwd, system_context)
        print(f"[cli-fallback] trying {cli_cmd}", file=sys.stderr)

        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=cwd,
                env={k: v for k, v in os.environ.items() if k != "CLAUDECODE"},
            )
        except subprocess.TimeoutExpired:
            last_output = f"Timeout from {cli_cmd} after {timeout}s"
            print(f"[cli-fallback] {last_output}", file=sys.stderr)
            continue
        except FileNotFoundError:
            last_output = f"CLI not found: {cli_cmd}"
            print(f"[cli-fallback] {last_output}", file=sys.stderr)
            continue
        except Exception as exc:  # pragma: no cover
            last_output = f"{cli_cmd} failed: {exc}"
            print(f"[cli-fallback] {last_output}", file=sys.stderr)
            continue

        output = (result.stdout or "").strip() or (result.stderr or "").strip()
        last_output = output

        if result.returncode == 0 and output and not _looks_rate_limited(output):
            print(f"[cli-fallback] success via {cli_cmd}", file=sys.stderr)
            return output, cli_cmd

        print(f"[cli-fallback] {cli_cmd} failed: {output or f'exit {result.returncode}'}", file=sys.stderr)

    return last_output or "No CLI produced a response", ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a prompt through a CLI fallback chain")
    parser.add_argument("--primary", required=True, help="Primary CLI command, e.g. 'claude'")
    parser.add_argument("--fallbacks", default=DEFAULT_FALLBACKS, help="Comma-separated fallback CLIs")
    parser.add_argument("--cwd", default=os.getcwd(), help="Working directory for CLI execution")
    parser.add_argument("--timeout", type=int, default=120, help="Per-CLI timeout in seconds")
    parser.add_argument("--system-dir", default="", help="Directory of *.md files to append as system context")
    args = parser.parse_args()

    prompt = sys.stdin.read()
    system_context = load_system_context(args.system_dir)
    output, used = run_cli_chain(
        prompt=prompt,
        primary=args.primary,
        fallbacks=args.fallbacks,
        cwd=args.cwd,
        system_context=system_context,
        timeout=args.timeout,
    )
    if used:
        print(output)
        return 0

    print(output, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
