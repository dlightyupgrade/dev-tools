"""Local state under ~/.servicing-triage-ui: the latest report, known-issue notes, investigation results and an audit log.

Only what the triage service already returns (ids, dollar amounts, error text) plus notes the user types is stored.
"""

from __future__ import annotations

import getpass
import json
import os
import re
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path

KNOWN_STATES = ("open", "known", "ticketed", "ignore")
TICKET = re.compile(r"[A-Z][A-Z0-9]+-\d+\Z")
NOTE_MAX = 300
SESSION_ID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")


def default_home() -> Path:
    return Path(os.environ.get("TRIAGE_UI_HOME", Path.home() / ".servicing-triage-ui"))


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Store:
    def __init__(self, home: Path | None = None) -> None:
        self.home = home or default_home()
        self.home.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._lock = threading.Lock()

    def _read(self, name: str, default):
        path = self.home / name
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            return default

    def _write(self, name: str, value) -> None:
        with self._lock:
            handle, temp = tempfile.mkstemp(dir=self.home, prefix=name + ".")
            with os.fdopen(handle, "w") as out:
                json.dump(value, out, indent=1)
            os.chmod(temp, 0o600)
            os.replace(temp, self.home / name)

    def latest_report(self) -> dict | None:
        return self._read("latest.json", None)

    def save_report(self, report: dict, source: str) -> dict:
        envelope = {"fetched_at": now(), "source": source, **report}
        self._write("latest.json", envelope)
        return envelope

    def latest_stats(self) -> dict | None:
        return self._read("stats.json", None)

    def save_stats(self, stats: dict, source: str) -> dict:
        envelope = {"fetched_at": now(), "source": source, **stats}
        self._write("stats.json", envelope)
        return envelope

    def known(self) -> dict:
        return self._read("known.json", {})

    def set_known(self, finding_id: str, state: str, note: str, ticket: str) -> dict:
        if state not in KNOWN_STATES:
            raise ValueError("state must be one of " + ", ".join(KNOWN_STATES))
        if len(note) > NOTE_MAX:
            raise ValueError(f"note is limited to {NOTE_MAX} characters")
        if ticket and not TICKET.match(ticket):
            raise ValueError("ticket must look like ABC-123")
        known = self.known()
        if state == "open":
            known.pop(finding_id, None)
        else:
            known[finding_id] = {"state": state, "note": note, "ticket": ticket, "updated_at": now(), "by": getpass.getuser()}
        self._write("known.json", known)
        return known

    def investigations(self) -> dict:
        return self._read("investigations.json", {})

    def save_investigation(self, finding_id: str, record: dict) -> None:
        investigations = self.investigations()
        investigations[finding_id] = record
        self._write("investigations.json", investigations)

    def pins(self) -> list:
        return self._read("pins.json", [])

    def set_pin(self, finding_id: str, pinned: bool) -> list:
        pins = [pin for pin in self.pins() if pin != finding_id]
        if pinned:
            pins.append(finding_id)
        self._write("pins.json", pins)
        return pins

    def seen(self) -> dict:
        return self._read("seen.json", {})

    def mark_seen(self, finding_id: str, token: str) -> None:
        seen = self.seen()
        seen[finding_id] = token
        self._write("seen.json", seen)

    def audit(self, action: str, **fields) -> None:
        line = json.dumps({"at": now(), "user": getpass.getuser(), "action": action, **fields})
        with self._lock, open(self.home / "audit.jsonl", "a") as out:
            out.write(line + "\n")
        os.chmod(self.home / "audit.jsonl", 0o600)
