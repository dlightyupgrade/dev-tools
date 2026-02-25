#!/usr/bin/env python3
"""Hook: PreToolUse — capture all tool calls."""
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

    tool_name: str = hook_data.get("tool_name", hook_data.get("toolName", ""))
    session_id = hook_data.get("session_id", hook_data.get("sessionId", ""))
    ctx = read_context(session_id)
    tool_input: dict = hook_data.get("tool_input", hook_data.get("toolInput", {}))

    invoked_skill = tool_input.get("skill", "") if tool_name == "Skill" else ""

    payload: dict = {"tool_input": tool_input}
    if invoked_skill:
        payload["invoked_skill"] = invoked_skill

    event = {
        "hook_event_type": "PreToolUse",
        "session_id": session_id,
        "source_app": "claude-observer",
        "agent_type": "",
        "tool_name": tool_name,
        "skill_name": invoked_skill or ctx.get("skill", ""),
        "ticket_id": ctx.get("ticket", ""),
        "payload": payload,
        "timestamp": int(time.time() * 1000),
    }

    post_event(event)


if __name__ == "__main__":
    main()
