#!/usr/bin/env python3
"""Universal hook event forwarder.

Reads JSON from stdin (Claude Code hook data), enriches it with
context (skill/ticket from observer-context.json scoped to session_id),
then POSTs to the observer server.  Fails silently if server is unreachable.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from droids import resolve_droid

SERVER_URL = os.environ.get("OBSERVER_SERVER_URL", "http://localhost:4001")
CONTEXT_FILE = Path.home() / ".claude" / "observer-context.json"
TIMEOUT = 3  # seconds


def read_context(session_id: str) -> dict[str, str]:
    """Read skill/ticket context for the given session_id."""
    try:
        ctx = json.loads(CONTEXT_FILE.read_text())
        return ctx.get(session_id, {})
    except Exception:
        return {}


def post_event(payload: dict) -> None:
    data = json.dumps(payload).encode()
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
        pass  # Server not running — silent failure


def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        return

    try:
        hook_data: dict = json.loads(raw)
    except json.JSONDecodeError:
        return

    session_id = hook_data.get("session_id", hook_data.get("sessionId", ""))
    ctx = read_context(session_id)
    agent_type = hook_data.get("agent_type", hook_data.get("agentType", ""))

    event = {
        "hook_event_type": hook_data.get("hook_event_type", hook_data.get("event", "Unknown")),
        "session_id": session_id,
        "source_app": "claude-observer",
        "agent_type": agent_type,
        "tool_name": hook_data.get("tool_name", hook_data.get("toolName", "")),
        "skill_name": ctx.get("skill", hook_data.get("skill_name", "")),
        "ticket_id": ctx.get("ticket", hook_data.get("ticket_id", "")),
        "payload": {k: v for k, v in hook_data.items()
                    if k not in ("hook_event_type", "session_id", "agent_type")},
        "timestamp": int(time.time() * 1000),
    }

    post_event(event)


if __name__ == "__main__":
    main()
