#!/usr/bin/env python3
"""Hook: SessionStart — record session start/resume and capture iTerm2 tab ID."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

SERVER_URL = os.environ.get("OBSERVER_SERVER_URL", "http://localhost:4001")
CONTEXT_FILE = Path.home() / ".claude" / "observer-context.json"
TIMEOUT = 3


def update_iterm_id(session_id: str) -> None:
    """Always update the iTerm2 session ID — captures the new tab on resume."""
    iterm_id = os.environ.get("TERM_SESSION_ID", "")
    if not iterm_id or not session_id:
        return
    uuid_part = iterm_id.split(":")[-1] if ":" in iterm_id else iterm_id
    try:
        ctx: dict = json.loads(CONTEXT_FILE.read_text())
    except Exception:
        ctx = {}
    if session_id not in ctx:
        ctx[session_id] = {}
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

    session_id = hook_data.get("session_id", hook_data.get("sessionId", ""))
    reason = hook_data.get("reason", "startup")

    # Always capture/update the iTerm2 tab ID (critical for resume)
    update_iterm_id(session_id)

    event = {
        "hook_event_type": "SessionStart",
        "session_id": session_id,
        "source_app": "claude-observer",
        "agent_type": "",
        "tool_name": "",
        "skill_name": "",
        "ticket_id": "",
        "payload": {"reason": reason},
        "timestamp": int(time.time() * 1000),
    }

    post_event(event)


if __name__ == "__main__":
    main()
