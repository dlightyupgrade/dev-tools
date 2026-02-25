#!/usr/bin/env python3
"""Hook: SubagentStart — forward droid invocation events to observer."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from droids import resolve_droid

SERVER_URL = os.environ.get("OBSERVER_SERVER_URL", "http://localhost:4001")
CONTEXT_FILE = Path.home() / ".claude" / "observer-context.json"
TIMEOUT = 3


def read_context(session_id: str) -> dict[str, str]:
    try:
        ctx = json.loads(CONTEXT_FILE.read_text())
        return ctx.get(session_id, {})
    except Exception:
        return {}


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
    ctx = read_context(session_id)
    agent_type = hook_data.get("agent_type", hook_data.get("agentType", ""))
    droid_name, droid_color, droid_emoji = resolve_droid(agent_type)

    event = {
        "hook_event_type": "SubagentStart",
        "session_id": session_id,
        "source_app": "claude-observer",
        "agent_type": agent_type,
        "tool_name": "",
        "skill_name": ctx.get("skill", ""),
        "ticket_id": ctx.get("ticket", ""),
        "payload": {
            "droid_name": droid_name,
            "droid_color": droid_color,
            "droid_emoji": droid_emoji,
            "description": hook_data.get("description", ""),
        },
        "timestamp": int(time.time() * 1000),
    }

    post_event(event)


if __name__ == "__main__":
    main()
