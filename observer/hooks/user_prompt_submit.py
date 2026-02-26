#!/usr/bin/env python3
"""Hook: UserPromptSubmit — detect skill invocations and persist context.

Detects patterns like:
  /quick-ticket SI-1234
  /feature-ticket SI-567
  /some-skill

Writes ~/.claude/observer-context.json keyed by session_id so downstream
hooks know which skill/ticket is active per session.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from droids import resolve_droid

SERVER_URL = os.environ.get("OBSERVER_SERVER_URL", "http://localhost:4001")
CONTEXT_FILE = Path.home() / ".claude" / "observer-context.json"
TIMEOUT = 3

# Match /skill-name at start of prompt or after whitespace (not inside URLs)
SKILL_RE = re.compile(r"(?:^|\s)/([a-zA-Z0-9_:-]+)(?:\s+((?:SI|SD|PROJ)-\d+))?", re.IGNORECASE)
TICKET_RE = re.compile(r"\b((?:SI|SD|PROJ)-\d+)\b", re.IGNORECASE)


def parse_prompt(prompt: str) -> tuple[str, str]:
    """Return (skill_name, ticket_id) from the user prompt text."""
    skill = ""
    ticket = ""

    m = SKILL_RE.search(prompt)
    if m:
        skill = m.group(1).strip()
        if m.group(2):
            ticket = m.group(2).upper()

    if not ticket:
        t = TICKET_RE.search(prompt)
        if t:
            ticket = t.group(1).upper()

    return skill, ticket


def write_context(session_id: str, skill: str, ticket: str) -> None:
    CONTEXT_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        ctx: dict = json.loads(CONTEXT_FILE.read_text())
    except Exception:
        ctx = {}

    if session_id not in ctx:
        ctx[session_id] = {}

    if skill:
        ctx[session_id]["skill"] = skill
    if ticket:
        ctx[session_id]["ticket"] = ticket

    # Capture the iTerm2 tab ID on first prompt so we can jump back to it later.
    # TERM_SESSION_ID format: "w0t1p0:UUID" — AppleScript unique id is just the UUID part.
    iterm_id = os.environ.get("TERM_SESSION_ID", "")
    if iterm_id and "iterm_session_id" not in ctx[session_id]:
        uuid_part = iterm_id.split(":")[-1] if ":" in iterm_id else iterm_id
        ctx[session_id]["iterm_session_id"] = uuid_part

    CONTEXT_FILE.write_text(json.dumps(ctx))


def post_event(event: dict) -> None:
    data = json.dumps(event).encode()
    req = urllib.request.Request(
        f"{SERVER_URL}/events",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT):
            pass
    except Exception:
        pass


def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        return

    try:
        hook_data: dict = json.loads(raw)
    except json.JSONDecodeError:
        return

    prompt = hook_data.get("prompt", hook_data.get("userPrompt", ""))
    session_id = hook_data.get("session_id", hook_data.get("sessionId", ""))
    skill, ticket = parse_prompt(prompt)

    write_context(session_id, skill, ticket)

    event = {
        "hook_event_type": "UserPromptSubmit",
        "session_id": session_id,
        "source_app": "claude-observer",
        "agent_type": "",
        "tool_name": "",
        "skill_name": skill,
        "ticket_id": ticket,
        "payload": {"prompt_preview": prompt[:200]},
        "timestamp": int(time.time() * 1000),
    }

    post_event(event)


if __name__ == "__main__":
    main()
