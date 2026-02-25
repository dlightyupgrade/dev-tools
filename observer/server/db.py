"""Async SQLite database layer using aiosqlite."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import aiosqlite

DB_PATH = Path(os.environ.get("OBSERVER_DB_PATH", Path.home() / ".claude" / "observer.db"))

CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS events (
    id          TEXT PRIMARY KEY,
    session_id  TEXT NOT NULL DEFAULT '',
    hook_event_type TEXT NOT NULL,
    source_app  TEXT NOT NULL DEFAULT 'claude-observer',
    agent_type  TEXT NOT NULL DEFAULT '',
    droid_name  TEXT NOT NULL DEFAULT '',
    droid_color TEXT NOT NULL DEFAULT '',
    droid_emoji TEXT NOT NULL DEFAULT '',
    skill_name  TEXT NOT NULL DEFAULT '',
    ticket_id   TEXT NOT NULL DEFAULT '',
    tool_name   TEXT NOT NULL DEFAULT '',
    payload     TEXT NOT NULL DEFAULT '{}',
    timestamp   INTEGER NOT NULL
)
"""

CREATE_INDEX = """
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);
"""

CREATE_SESSION_INDEX = """
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
"""


async def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(CREATE_TABLE)
        await db.execute(CREATE_INDEX)
        await db.execute(CREATE_SESSION_INDEX)
        await db.commit()


async def insert_event(event: dict[str, Any]) -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """INSERT INTO events
               (id, session_id, hook_event_type, source_app, agent_type,
                droid_name, droid_color, droid_emoji, skill_name, ticket_id,
                tool_name, payload, timestamp)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                event["id"],
                event["session_id"],
                event["hook_event_type"],
                event["source_app"],
                event["agent_type"],
                event["droid_name"],
                event["droid_color"],
                event["droid_emoji"],
                event["skill_name"],
                event["ticket_id"],
                event["tool_name"],
                json.dumps(event["payload"]),
                event["timestamp"],
            ),
        )
        await db.commit()


async def query_events(
    limit: int = 200,
    offset: int = 0,
    session: str = "",
    droid: str = "",
    skill: str = "",
    event_type: str = "",
) -> list[dict[str, Any]]:
    filters: list[str] = []
    params: list[Any] = []

    if session:
        filters.append("session_id = ?")
        params.append(session)
    if droid:
        filters.append("droid_name = ?")
        params.append(droid)
    if skill:
        filters.append("skill_name = ?")
        params.append(skill)
    if event_type:
        filters.append("hook_event_type = ?")
        params.append(event_type)

    where = ("WHERE " + " AND ".join(filters)) if filters else ""
    params += [limit, offset]

    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            f"SELECT * FROM events {where} ORDER BY timestamp DESC LIMIT ? OFFSET ?",
            params,
        ) as cursor:
            rows = await cursor.fetchall()
    return [_row_to_dict(r) for r in rows]


async def get_filter_options() -> dict[str, list[str]]:
    async with aiosqlite.connect(DB_PATH) as db:
        async def distinct(col: str) -> list[str]:
            async with db.execute(
                f"SELECT DISTINCT {col} FROM events WHERE {col} != '' ORDER BY {col}"
            ) as cur:
                return [r[0] async for r in cur]

        sessions = await distinct("session_id")
        droids = await distinct("droid_name")
        skills = await distinct("skill_name")
        event_types = await distinct("hook_event_type")

    return {
        "sessions": sessions,
        "droids": droids,
        "skills": skills,
        "event_types": event_types,
    }


async def reset_db() -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("DELETE FROM events")
        await db.commit()


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    d = dict(row)
    try:
        d["payload"] = json.loads(d["payload"])
    except Exception:
        d["payload"] = {}
    return d
