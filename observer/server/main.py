"""Claude Observer — FastAPI server.

Endpoints:
  POST /events              — ingest hook events
  GET  /events              — paginated/filtered query
  GET  /events/filter-options — distinct filter values
  GET  /health              — liveness
  WS   /stream              — live event broadcast
"""
from __future__ import annotations

import asyncio
import json
import os
import shlex
import signal
import subprocess
import tempfile
import time
from contextlib import asynccontextmanager
from typing import Any

SERVER_START_TIME = time.time()

WCLDS = os.path.expanduser("~/code/personal-dev-tools/cli/wclds")

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware

from db import init_db, insert_event, query_events, get_filter_options, reset_db, delete_session_events
from droids import resolve_droid
from models import IncomingEvent, StoredEvent, FilterOptions

try:
    from ulid import ULID
    def new_id() -> str:
        return str(ULID())
except ImportError:
    import uuid
    def new_id() -> str:
        return str(uuid.uuid4())


# ── WebSocket manager ─────────────────────────────────────────────────────────

class ConnectionManager:
    def __init__(self) -> None:
        self._clients: list[WebSocket] = []

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self._clients.append(ws)

    def disconnect(self, ws: WebSocket) -> None:
        self._clients.remove(ws)

    async def broadcast(self, data: dict[str, Any]) -> None:
        dead: list[WebSocket] = []
        for client in list(self._clients):
            try:
                await client.send_text(json.dumps(data))
            except Exception:
                dead.append(client)
        for ws in dead:
            if ws in self._clients:
                self._clients.remove(ws)

    @property
    def count(self) -> int:
        return len(self._clients)


manager = ConnectionManager()


# ── App lifecycle ─────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(title="Claude Observer", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "clients": str(manager.count)}


@app.get("/status")
async def status() -> dict[str, Any]:
    from db import get_event_count
    uptime_s = int(time.time() - SERVER_START_TIME)
    h, m, s = uptime_s // 3600, (uptime_s % 3600) // 60, uptime_s % 60
    return {
        "status": "ok",
        "uptime": f"{h:02d}:{m:02d}:{s:02d}",
        "uptime_s": uptime_s,
        "clients": manager.count,
        "event_count": await get_event_count(),
        "port": 4001,
    }


@app.post("/shutdown")
async def shutdown() -> dict[str, str]:
    async def _kill():
        await asyncio.sleep(0.2)
        os.kill(os.getpid(), signal.SIGTERM)
    asyncio.create_task(_kill())
    return {"status": "shutting down"}


@app.post("/events", response_model=StoredEvent)
async def create_event(incoming: IncomingEvent) -> dict[str, Any]:
    now_ms = int(time.time() * 1000)
    droid_name, droid_color, droid_emoji = resolve_droid(incoming.agent_type)

    event: dict[str, Any] = {
        "id": new_id(),
        "session_id": incoming.session_id,
        "hook_event_type": incoming.hook_event_type,
        "source_app": incoming.source_app,
        "agent_type": incoming.agent_type,
        "droid_name": droid_name,
        "droid_color": droid_color,
        "droid_emoji": droid_emoji,
        "skill_name": incoming.skill_name,
        "ticket_id": incoming.ticket_id,
        "tool_name": incoming.tool_name,
        "payload": incoming.payload,
        "timestamp": incoming.timestamp if incoming.timestamp else now_ms,
    }

    await insert_event(event)
    asyncio.create_task(manager.broadcast(event))
    return event


@app.get("/events", response_model=list[StoredEvent])
async def list_events(
    limit: int = Query(200, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    session: str = Query(""),
    droid: str = Query(""),
    skill: str = Query(""),
    event_type: str = Query(""),
) -> list[dict[str, Any]]:
    return await query_events(
        limit=limit,
        offset=offset,
        session=session,
        droid=droid,
        skill=skill,
        event_type=event_type,
    )


@app.get("/events/filter-options", response_model=FilterOptions)
async def filter_options() -> dict[str, list[str]]:
    return await get_filter_options()


@app.get("/launch-new")
async def launch_new(cmd: str = Query("")) -> dict[str, Any]:
    if not cmd:
        return {"ok": False, "error": "cmd is required"}

    # Write prompt to a temp script to safely handle newlines, quotes, backslashes
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False)
    tmp.write("#!/bin/bash\n")
    tmp.write(f"claude {shlex.quote(cmd)}\n")
    tmp.close()
    os.chmod(tmp.name, 0o755)

    script = f"""
tell application "iTerm2"
    activate
    tell current window
        create tab with default profile
        set s to current session of current tab
        tell s
            write text "{tmp.name}"
        end tell
    end tell
end tell
"""
    subprocess.Popen(["osascript", "-e", script])
    return {"ok": True, "cmd": cmd}


CONTEXT_FILE = os.path.expanduser("~/.claude/observer-context.json")


@app.get("/focus-session")
async def focus_session(session_id: str = Query("")) -> dict[str, Any]:
    if not session_id:
        return {"ok": False, "error": "session_id is required"}
    try:
        with open(CONTEXT_FILE) as f:
            ctx = json.load(f)
        iterm_id = ctx.get(session_id, {}).get("iterm_session_id", "")
    except Exception:
        iterm_id = ""

    if not iterm_id:
        return {"ok": False, "error": "No iTerm2 session ID recorded for this session"}

    script = f"""
tell application "iTerm2"
    set tabIndex to 0
    set targetWindow to missing value
    set targetTabIdx to 0
    repeat with w in windows
        set tabIndex to 0
        repeat with t in tabs of w
            set tabIndex to tabIndex + 1
            repeat with s in sessions of t
                if unique id of s is "{iterm_id}" then
                    set targetWindow to w
                    set targetTabIdx to tabIndex
                end if
            end repeat
        end repeat
    end repeat
    if targetWindow is not missing value then
        activate
        set index of targetWindow to 1
        tell targetWindow to select (tab targetTabIdx)
    end if
end tell
"""
    subprocess.Popen(["osascript", "-e", script])
    return {"ok": True, "iterm_session_id": iterm_id}


@app.get("/launch")
async def launch_session(session_id: str = Query("")) -> dict[str, Any]:
    if not session_id:
        return {"ok": False, "error": "session_id is required"}
    script = f"""
tell application "iTerm2"
    activate
    tell current window
        create tab with default profile
        set s to current session of current tab
        tell s
            write text "claude --resume {session_id}"
        end tell
    end tell
end tell
"""
    subprocess.Popen(["osascript", "-e", script])
    return {"ok": True, "session_id": session_id}


@app.delete("/events/session/{session_id}")
async def delete_session(session_id: str) -> dict[str, str]:
    await delete_session_events(session_id)
    return {"status": "deleted", "session_id": session_id}


@app.delete("/events")
async def clear_events() -> dict[str, str]:
    await reset_db()
    return {"status": "cleared"}


@app.websocket("/stream")
async def websocket_stream(ws: WebSocket) -> None:
    await manager.connect(ws)
    try:
        while True:
            # Keep-alive ping loop; client sends nothing, server broadcasts events
            await asyncio.sleep(30)
            try:
                await ws.send_text(json.dumps({"type": "ping"}))
            except Exception:
                break
    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(ws)
