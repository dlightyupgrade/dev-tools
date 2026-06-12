"""Claude Observer — FastAPI server.

Endpoints:
  POST /events              — ingest hook events
  GET  /events              — paginated/filtered query
  GET  /events/filter-options — distinct filter values
  GET  /health              — liveness
  WS   /stream              — live event broadcast
  GET  /memory              — list all memory files
  GET  /memory/dream        — SSE: Claude analyzes all memories
  GET  /memory/export       — export memories as JSON bundle
  GET  /memory/{slug}       — get single memory with full body
  PUT  /memory/{slug}       — update memory body
  DELETE /memory/{slug}     — delete memory + update MEMORY.md
  POST /memory/merge        — merge two memories into one
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shlex
import signal
import subprocess
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, AsyncIterator

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


# ── Memory API ────────────────────────────────────────────────────────────────

def _memory_dir() -> Path:
    home = Path.home()
    slug = str(home).replace("/", "-")
    return home / ".claude" / "projects" / slug / "memory"


def _safe_slug(slug: str) -> bool:
    return bool(re.match(r"^[a-zA-Z0-9_\-]+$", slug))


def _parse_memory(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8")
    parts = raw.split("---", 2)
    if len(parts) >= 3:
        fm_text = parts[1].strip()
        body = parts[2].strip()
    else:
        fm_text = ""
        body = raw.strip()

    name = path.stem
    description = ""
    mem_type = "unknown"

    for line in fm_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("name:"):
            name = stripped[5:].strip().strip('"\'')
        elif stripped.startswith("description:"):
            description = stripped[12:].strip().strip('"\'')
        elif stripped.startswith("type:") and "metadata" not in line:
            mem_type = stripped[5:].strip().strip('"\'')

    stat = path.stat()
    age_days = int((time.time() - stat.st_mtime) / 86400)

    return {
        "slug": path.stem,
        "name": name,
        "description": description,
        "type": mem_type,
        "age_days": age_days,
        "size": stat.st_size,
        "body": body,
    }


def _update_memory_index(mem_dir: Path, slug: str, title: str, description: str, action: str = "add") -> None:
    index_path = mem_dir / "MEMORY.md"
    if not index_path.exists():
        return

    lines = index_path.read_text(encoding="utf-8").splitlines(keepends=True)
    pattern = f"({slug}.md)"

    if action == "remove":
        lines = [l for l in lines if pattern not in l]
        index_path.write_text("".join(lines), encoding="utf-8")
    elif action == "add":
        new_line = f"- [{title}]({slug}.md) — {description}\n"
        if not any(pattern in l for l in lines):
            lines.append(new_line)
            index_path.write_text("".join(lines), encoding="utf-8")


@app.get("/memory")
async def list_memories() -> list[dict[str, Any]]:
    mem_dir = _memory_dir()
    if not mem_dir.exists():
        return []
    memories = []
    for p in sorted(mem_dir.glob("*.md")):
        if p.name == "MEMORY.md":
            continue
        try:
            m = _parse_memory(p)
            memories.append({k: v for k, v in m.items() if k != "body"})
        except Exception:
            pass
    return memories


@app.get("/memory/export")
async def export_memories() -> list[dict[str, Any]]:
    mem_dir = _memory_dir()
    if not mem_dir.exists():
        return []
    result = []
    for p in sorted(mem_dir.glob("*.md")):
        if p.name == "MEMORY.md":
            continue
        try:
            result.append(_parse_memory(p))
        except Exception:
            pass
    return result


@app.get("/memory/dream")
async def dream_memories() -> Any:
    from fastapi.responses import StreamingResponse

    mem_dir = _memory_dir()
    if not mem_dir.exists():
        return {"error": "Memory directory not found"}

    memories = []
    for p in sorted(mem_dir.glob("*.md")):
        if p.name == "MEMORY.md":
            continue
        try:
            memories.append(_parse_memory(p))
        except Exception:
            pass

    if not memories:
        return {"error": "No memories found"}

    by_type: dict[str, list[dict]] = {}
    for m in memories:
        by_type.setdefault(m["type"], []).append(m)

    sections = []
    for t, mems in sorted(by_type.items()):
        sections.append(f"\n### {t.upper()} ({len(mems)} memories)\n")
        for m in mems:
            sections.append(f"\n**{m['slug']}** (age: {m['age_days']}d)\n{m['description']}\n\n{m['body']}\n---")

    memory_dump = "\n".join(sections)

    prompt = f"""You are analyzing a developer's personal Claude Code memory system. These memories guide Claude's behavior across all coding sessions.

MEMORY INVENTORY ({len(memories)} memories total):
{memory_dump}

Analyze these memories and produce a structured report with exactly these sections:

## 🔍 Patterns
What recurring themes cluster together? Identify 3-5 dominant behavioral patterns with the memory names that represent them.

## ⚠️ Potentially Stale
Which memories (especially project/*) may be outdated? Look for: referenced PRs, ticket numbers, time-specific project states. List slug + reason.

## 💡 Missing Memories
Based on patterns in the feedback memories, what 3-5 obvious corollary memories seem to be missing? Describe what each would say.

## 🔀 Top 3 Consolidation Candidates
Identify 3 pairs of memories that overlap enough to benefit from merging. For each: list both slugs and explain the overlap in one sentence.

## 🌟 Five Strongest Memories
Which 5 memories are most impactful and frequently applicable to daily work? Name them and say why.

Be specific. Cite exact slug names. Keep the report focused and actionable."""

    async def stream() -> AsyncIterator[str]:
        # Write prompt to a temp file and use @file syntax to avoid arg length limits
        tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8")
        tmp.write(prompt)
        tmp.flush()
        tmp.close()
        try:
            proc = await asyncio.create_subprocess_exec(
                "claude", "-p", f"@{tmp.name}",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            assert proc.stdout is not None
            while True:
                chunk = await proc.stdout.read(128)
                if not chunk:
                    break
                text = chunk.decode("utf-8", errors="replace")
                yield f"data: {json.dumps({'text': text})}\n\n"
            await proc.wait()
        except Exception as exc:
            yield f"data: {json.dumps({'error': str(exc)})}\n\n"
        finally:
            os.unlink(tmp.name)
        yield f"data: {json.dumps({'done': True})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})


@app.get("/memory/{slug}")
async def get_memory(slug: str) -> dict[str, Any]:
    if not _safe_slug(slug):
        return {"error": "Invalid slug"}
    mem_dir = _memory_dir()
    path = mem_dir / f"{slug}.md"
    if not path.exists():
        return {"error": "Not found"}
    return _parse_memory(path)


@app.put("/memory/{slug}")
async def update_memory(slug: str, payload: dict[str, Any]) -> dict[str, str]:
    if not _safe_slug(slug):
        return {"error": "Invalid slug"}
    mem_dir = _memory_dir()
    path = mem_dir / f"{slug}.md"
    if not path.exists():
        return {"error": "Not found"}

    raw = path.read_text(encoding="utf-8")
    parts = raw.split("---", 2)
    if len(parts) >= 3:
        new_content = f"---{parts[1]}---\n\n{payload.get('body', '')}\n"
    else:
        new_content = payload.get("body", "")

    path.write_text(new_content, encoding="utf-8")
    return {"status": "updated"}


@app.delete("/memory/{slug}")
async def delete_memory(slug: str) -> dict[str, str]:
    if not _safe_slug(slug):
        return {"error": "Invalid slug"}
    mem_dir = _memory_dir()
    path = mem_dir / f"{slug}.md"
    if not path.exists():
        return {"error": "Not found"}
    path.unlink()
    _update_memory_index(mem_dir, slug, slug, "", action="remove")
    return {"status": "deleted"}


@app.post("/memory/merge")
async def merge_memories(payload: dict[str, Any]) -> dict[str, Any]:
    source_slug = payload.get("source", "")
    target_slug = payload.get("target", "")

    if not _safe_slug(source_slug) or not _safe_slug(target_slug):
        return {"error": "Invalid slug"}

    mem_dir = _memory_dir()
    source_path = mem_dir / f"{source_slug}.md"
    target_path = mem_dir / f"{target_slug}.md"

    if not source_path.exists() or not target_path.exists():
        return {"error": "One or both memories not found"}

    source = _parse_memory(source_path)
    target = _parse_memory(target_path)

    merge_prompt = f"""Merge these two Claude Code memories into one stronger, concise memory. Keep the most important guidance from both. Preserve the Why and How to apply structure if present.

MEMORY 1 — {source['slug']} ({source['type']}):
Description: {source['description']}

{source['body']}

MEMORY 2 — {target['slug']} ({target['type']}):
Description: {target['description']}

{target['body']}

Output ONLY the merged memory body content (no frontmatter, no explanation). Start directly with the rule/fact."""

    try:
        proc = await asyncio.create_subprocess_exec(
            "claude", "-p", merge_prompt,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        merged_body = stdout.decode("utf-8", errors="replace").strip()
    except Exception as exc:
        return {"error": str(exc)}

    return {
        "merged_body": merged_body,
        "source_slug": source_slug,
        "target_slug": target_slug,
        "source_description": source["description"],
        "target_description": target["description"],
    }
