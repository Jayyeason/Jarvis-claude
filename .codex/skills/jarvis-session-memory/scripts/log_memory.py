#!/usr/bin/env python3
"""Append a structured progress entry to AGENTS.md session memory ledger."""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path


DEFAULT_LOG_FILE = Path("/Users/kk/Jarvis-claude/AGENTS.md")
LEDGER_HEADER = "## Session Memory Ledger"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Append a memory ledger entry to AGENTS.md")
    parser.add_argument("--summary", required=True, help="What milestone was completed")
    parser.add_argument("--files", default="none", help="Comma-separated list of touched files")
    parser.add_argument("--decision", default="none", help="Key decision made in this step")
    parser.add_argument("--next", dest="next_step", default="none", help="Next planned action")
    parser.add_argument(
        "--log-file",
        default=str(DEFAULT_LOG_FILE),
        help="Path to AGENTS.md file",
    )
    return parser.parse_args()


def ensure_ledger(content: str) -> str:
    if LEDGER_HEADER in content:
        return content
    suffix = "\n\n" if content.rstrip() else ""
    return (
        f"{content.rstrip()}{suffix}{LEDGER_HEADER}\n"
        "- Structured milestone logs are appended here by `jarvis-session-memory`.\n"
    )


def append_entry(content: str, summary: str, files: str, decision: str, next_step: str) -> str:
    timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    entry = (
        f"\n### {timestamp} | milestone\n"
        f"- Summary: {summary.strip()}\n"
        f"- Files: {files.strip()}\n"
        f"- Decision: {decision.strip()}\n"
        f"- Next: {next_step.strip()}\n"
    )
    return f"{content.rstrip()}{entry}\n"


def main() -> int:
    args = parse_args()
    log_file = Path(args.log_file)
    if not log_file.exists():
        raise FileNotFoundError(f"Log file does not exist: {log_file}")

    content = log_file.read_text(encoding="utf-8")
    content = ensure_ledger(content)
    content = append_entry(content, args.summary, args.files, args.decision, args.next_step)
    log_file.write_text(content, encoding="utf-8")
    print(f"Appended milestone memory to {log_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
