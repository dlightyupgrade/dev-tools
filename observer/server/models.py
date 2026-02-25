"""Pydantic models for Observer events."""
from __future__ import annotations

from typing import Any
import json
from pydantic import BaseModel, Field, model_validator


class IncomingEvent(BaseModel):
    """Raw event POSTed from hook scripts."""
    hook_event_type: str
    session_id: str = ""
    source_app: str = "claude-observer"
    agent_type: str = ""
    tool_name: str = ""
    skill_name: str = ""
    ticket_id: str = ""
    payload: dict[str, Any] = Field(default_factory=dict)
    timestamp: int = 0  # epoch ms; if 0, server sets it

    @model_validator(mode="before")
    @classmethod
    def coerce_payload(cls, v: Any) -> Any:
        if isinstance(v, dict) and isinstance(v.get("payload"), str):
            try:
                v["payload"] = json.loads(v["payload"])
            except Exception:
                v["payload"] = {"raw": v["payload"]}
        return v


class StoredEvent(BaseModel):
    """Event as returned from the API."""
    id: str
    session_id: str
    hook_event_type: str
    source_app: str
    agent_type: str
    droid_name: str
    droid_color: str
    droid_emoji: str
    skill_name: str
    ticket_id: str
    tool_name: str
    payload: dict[str, Any]
    timestamp: int


class FilterOptions(BaseModel):
    sessions: list[str]
    droids: list[str]
    skills: list[str]
    event_types: list[str]
