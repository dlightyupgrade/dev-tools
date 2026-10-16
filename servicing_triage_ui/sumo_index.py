"""Finds the Sumo Logic monitors in a sumologic-config checkout whose definitions mention a finding's error.

A mention is not coverage. It only says a monitor's query or text names the same code, phrase or task. This reads
monitor definitions only. It cannot say whether a monitor fired.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

from .parser import EXCEPTION_PREFIX, SP_CODE

REPO_URL = "git@github.com:Credify/sumologic-config.git"
NON_PROD = re.compile(r"(^|[/_-])(preprod|stage)([/_.-]|$)")
NAME = re.compile(r'^\s*name\s*=\s*"([^"]+)"', re.M)
CHANNELS = re.compile(r"slack_channels\s*=\s*\[([^\]]*)\]")
PRIORITY = re.compile(r'^\s*priority\s*=\s*"(P\d)"', re.M)
TIME_RANGE = re.compile(r'^\s*time_range\s*=\s*"([^"]+)"', re.M)
INCIDENTIO = re.compile(r"^\s*incidentio\s*=", re.M)
MAX_FILE_BYTES = 200_000


def sync(destination: Path) -> str:
    """Shallow clone, or fast-forward, the monitors repo into the tool's own directory. Never touches other checkouts."""
    if (destination / ".git").is_dir():
        subprocess.run(["git", "-C", str(destination), "fetch", "--depth", "1", "origin", "master"], check=True, capture_output=True, timeout=300)
        subprocess.run(["git", "-C", str(destination), "reset", "--hard", "origin/master"], check=True, capture_output=True, timeout=60)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--depth", "1", REPO_URL, str(destination)], check=True, capture_output=True, timeout=600)
    return head_info(destination)["sha"]


def head_info(root: Path) -> dict[str, str]:
    def git(*args: str) -> str:
        try:
            return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=15).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    return {"sha": git("rev-parse", "--short", "HEAD"), "date": git("log", "-1", "--format=%cd", "--date=short"), "branch": git("branch", "--show-current")}


class SumoIndex:
    def __init__(self, root: Path | None) -> None:
        self.root = root
        self.monitors: list[dict] = []
        self.info: dict[str, str] = {}
        if root and (root / "monitors").is_dir():
            self._scan(root)

    @property
    def available(self) -> bool:
        return bool(self.monitors)

    def _scan(self, root: Path) -> None:
        self.info = head_info(root)
        for path in sorted((root / "monitors").rglob("*.tf")):
            relative = path.relative_to(root).as_posix()
            if NON_PROD.search(relative) or path.stat().st_size > MAX_FILE_BYTES:
                continue
            text = path.read_text(errors="replace")
            name = NAME.search(text)
            if not name:
                continue
            channels = CHANNELS.search(text)
            priority = PRIORITY.search(text)
            time_range = TIME_RANGE.search(text)
            self.monitors.append({
                "name": name.group(1),
                "path": relative,
                "team": relative.split("/")[1] if relative.count("/") >= 2 else "",
                "channels": re.findall(r'"([^"]+)"', channels.group(1)) if channels else [],
                "priority": priority.group(1) if priority else "",
                "window": time_range.group(1) if time_range else "",
                "incidentio": bool(INCIDENTIO.search(text)),
                "_text": text.lower(),
            })

    def find(self, needles: list[tuple[str, str]], limit: int = 6) -> dict:
        matches = []
        for monitor in self.monitors:
            matched_on = [kind for kind, needle in needles if needle.lower() in monitor["_text"]]
            if matched_on:
                matches.append({**{k: v for k, v in monitor.items() if k != "_text"}, "matched_on": sorted(set(matched_on))})
        rank = {"code": 0, "text": 1, "task": 2}
        matches.sort(key=lambda m: (min(rank[kind] for kind in m["matched_on"]), m["name"]))
        return {"total": len(matches), "monitors": matches[:limit]}


def needles_for(finding: dict) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    haystack = " ".join([finding["key"], finding["error_text"], finding["title"]])
    found.extend(("code", code) for code in sorted(set(SP_CODE.findall(haystack))))
    phrase_source = finding["error_text"].splitlines()[0] if finding["error_text"] else finding["key"].split(":", 2)[-1]
    phrase = EXCEPTION_PREFIX.sub("", SP_CODE.sub("", phrase_source)).lstrip(" -:")
    phrase = re.split(r"[#=\d$]", phrase)[0].strip()
    if len(phrase) >= 20:
        found.append(("text", phrase[:45].rsplit(" ", 1)[0] if len(phrase) > 45 else phrase))
    parts = finding["key"].split(":")
    if finding["area"].endswith("-tqf") and len(parts) > 1 and len(parts[1]) >= 8:
        found.append(("task", parts[1]))
    return found
