"""Turns the text that the servicing-agent `daily_stats` tool returns into sections of rows."""

from __future__ import annotations

import re

from .parser import MONEY, parse_unchecked, to_money, UNCHECKED

TITLE = re.compile(r"^Servicing stats for (.+?)(?: \(UTC\))?, change against the day before", re.M)
ROW = re.compile(r"^  ([^:]+): (.*)$")
COUNT = re.compile(r"^([\d,]+)")
CHANGE = re.compile(r"\(([^()]*(?:day before|yesterday)[^()]*)\)")
PERCENT = re.compile(r"([+-]\d+)%")
BREAKDOWN = re.compile(r"\[([^\]]*)\]")
FOLLOW_UP = re.compile(r"-> (.*)$")


def _breakdown(text: str) -> list[dict]:
    parts = []
    for item in text.split(","):
        name, _, count = item.strip().rpartition(" ")
        if name and count.isdigit():
            parts.append({"name": name, "count": int(count)})
    return parts


def parse_row(label: str, value: str) -> dict:
    counted = COUNT.match(value)
    change = CHANGE.search(value)
    percent = PERCENT.search(change.group(1)) if change else None
    breakdown = BREAKDOWN.search(value)
    follow_up = FOLLOW_UP.search(value)
    return {
        "label": label.strip(),
        "count": int(counted.group(1).replace(",", "")) if counted else None,
        "dollars": to_money(value) if MONEY.search(value) else None,
        "change_text": change.group(1) if change else "",
        "change_percent": int(percent.group(1)) if percent else (0 if change and change.group(1).startswith("same") else None),
        "breakdown": _breakdown(breakdown.group(1)) if breakdown else [],
        "follow_up": follow_up.group(1).strip() if follow_up else "",
        "failure": "failed" in label.lower(),
        "raw": value,
    }


def parse_stats(text: str) -> dict:
    unchecked = parse_unchecked(text)
    body = UNCHECKED.sub("", text)
    title = TITLE.search(body)
    sections: list[dict] = []
    notes: list[str] = []
    for line in body.split("\n")[1:]:
        if not line.strip():
            continue
        row = ROW.match(line)
        if row and sections:
            sections[-1]["rows"].append(parse_row(row.group(1), row.group(2)))
        elif not line.startswith(" ") and ":" not in line and not line.endswith("."):
            sections.append({"name": line.strip(), "rows": []})
        else:
            notes.append(line.strip())
    return {"day": title.group(1) if title else "", "sections": sections, "notes": notes, "unchecked": unchecked}
