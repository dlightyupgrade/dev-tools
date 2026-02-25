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
import subprocess
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware

from db import init_db, insert_event, query_events, get_filter_options, reset_db
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
