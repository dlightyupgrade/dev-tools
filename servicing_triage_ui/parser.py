"""Turns the text that the servicing-agent `failure_triage` tool returns into structured findings.

The service only offers `text` and `slack` today. When it gains a `json` format this module becomes unnecessary.
"""

from __future__ import annotations

import hashlib
import re
from decimal import Decimal, InvalidOperation

HEADER = re.compile(r"^Failure triage, last (\d+) days?: (\d+) signatures?, (\d+) failures?", re.M)
BLOCK_START = re.compile(r"^\[(OPS ACTION|BUG|REVIEW) - ([^\]]*)\] (.+)$")
OUTPUT_HEAD = re.compile(r"^  (ops handoff|ticket draft|biz-ops review|dev ticket draft|no playbook yet)(?: \(([^)]*)\))?: (.*)$")
HELPFUL = re.compile(r"^  helpful info \[(\w+)\]: (.*)$")
META = re.compile(r"^(route_to|component|label|duplicate_search_jql|sensor): (.*)$")
SP_CODE = re.compile(r"\bSP\d{4,5}\b")
MONEY = re.compile(r"\$([\d,]+(?:\.\d{1,2})?)")
WHY = re.compile(r"^Why (?:dev|biz-ops): (.*)$", re.M)
NEXT = re.compile(r"^Next: (.*)$", re.M)
EXCEPTION_PREFIX = re.compile(r"^(?:[\w.$]+\.)?\w*(?:Exception|Error): ")
UNCHECKED = re.compile(r"\n+Could not check: (.*)\Z", re.S)
UNCHECKED_SPLIT = re.compile(r"; (?=[^;:]+(?:: [^;:]+)?: query failed)")

DISPOSITION = {"OPS ACTION": "ops", "BUG": "bug", "REVIEW": "review"}
OUTPUT_KIND = {
    "ops handoff": "ops_handoff",
    "ticket draft": "ticket_draft",
    "biz-ops review": "biz_ops",
    "dev ticket draft": "dev_ticket",
    "no playbook yet": "no_playbook",
}
ACTION_KINDS = ("ticket_draft", "ops_handoff", "dev_ticket", "biz_ops")


def finding_id(key: str) -> str:
    return hashlib.sha1(key.encode()).hexdigest()[:12]


def to_money(text: str) -> float | None:
    found = MONEY.search(text)
    if not found:
        return None
    try:
        return float(Decimal(found.group(1).replace(",", "")))
    except InvalidOperation:
        return None


def _strip(cell: str, prefix: str) -> str:
    return cell[len(prefix):] if cell.startswith(prefix) else cell


def parse_sample(line: str) -> tuple[str, list[str]] | None:
    """Returns (kind, cells) for one `- a | b | c` sample line, or None if it is not a sample."""
    if not line.startswith("- ") or " | " not in line:
        return None
    cells = [cell.strip() for cell in line[2:].split(" | ")]
    first = cells[0]
    if first.startswith("request ") and len(cells) >= 7:
        return "payment", [
            _strip(first, "request "), _strip(cells[1], "loan "), cells[2], _strip(cells[3], "effective "),
            cells[4], _strip(cells[5], "failed ").removesuffix(" UTC"), cells[6],
        ]
    if first.startswith("account ") and len(cells) >= 4:
        loans = re.match(r"(\d+) loan", cells[1])
        return "billing", [_strip(first, "account "), loans.group(1) if loans else cells[1], _strip(cells[2], "last bill due "), cells[3]]
    if len(cells) >= 7 and cells[3].startswith("latest task "):
        return "task", [
            cells[0], cells[1], cells[2], _strip(cells[3], "latest task "), _strip(cells[4], "retries "),
            _strip(cells[5], "last failed ").removesuffix(" UTC"), cells[6],
        ]
    return "other", cells


SAMPLE_COLUMNS = {
    "payment": ["Request", "Loan", "Amount", "Effective", "Provider / input set", "Failed (UTC)", "State"],
    "billing": ["Account", "Unbilled loans in this group", "Last bill due", "Shard"],
    "task": ["Task", "Status", "Tasks", "Latest task", "Retries", "Last failed (UTC)", "Schema"],
    "other": ["Detail"],
}


def _split_blocks(text: str) -> tuple[str, list[list[str]]]:
    head: list[str] = []
    blocks: list[list[str]] = []
    for line in text.split("\n"):
        if BLOCK_START.match(line):
            blocks.append([line])
        elif blocks:
            blocks[-1].append(line)
        else:
            head.append(line)
    return "\n".join(head), blocks


def _parse_outputs(lines: list[str]) -> tuple[list[dict], list[str]]:
    """Level-1 lines (two-space indent) either describe the finding or open an output whose body is indented four."""
    outputs: list[dict] = []
    level_one: list[str] = []
    current: dict | None = None
    for line in lines:
        head = OUTPUT_HEAD.match(line)
        if head:
            current = {"kind": OUTPUT_KIND[head.group(1)], "note": head.group(2) or "", "title": head.group(3).strip(), "body_lines": []}
            outputs.append(current)
        elif line.startswith("    ") and current is not None:
            current["body_lines"].append(line[4:])
        elif line.strip() == "" and current is not None:
            current["body_lines"].append("")
        elif line.startswith("  ") and not line.startswith("   "):
            current = None
            level_one.append(line)
    for output in outputs:
        body = "\n".join(output.pop("body_lines")).strip()
        meta: dict[str, str] = {}
        kept: list[str] = []
        for body_line in body.split("\n"):
            matched = META.match(body_line)
            if matched:
                meta[matched.group(1)] = matched.group(2).strip()
            else:
                kept.append(body_line)
        output["body"] = "\n".join(kept).strip()
        output["meta"] = meta
    return outputs, level_one


def _error_text(outputs: list[dict]) -> str:
    for output in outputs:
        found = re.search(r"^Error text:\n((?:.+\n?)+)", output["body"], re.M)
        if found:
            return found.group(1).strip()
    return ""


def _samples(outputs: list[dict], highlights: str) -> tuple[str, list[list[str]]]:
    for output in outputs:
        rows = [parsed for parsed in (parse_sample(line.strip()) for line in output["body"].split("\n")) if parsed]
        if rows:
            kind = rows[0][0]
            return kind, [cells for row_kind, cells in rows if row_kind == kind]
    pairs = re.findall(r"(\d{6,}) \(\$([\d,.]+)\)", highlights)
    if pairs:
        return "ids", [[request_id, f"${amount}"] for request_id, amount in pairs]
    return "none", []


SAMPLE_COLUMNS["ids"] = ["Request", "Amount"]
SAMPLE_COLUMNS["none"] = []


def _samples_note(kind: str, samples: list[list[str]], total: int) -> str:
    if kind != "billing" or not samples or not all(row[1].isdigit() for row in samples):
        return ""
    shown = sum(int(row[1]) for row in samples)
    rows = len(samples)
    return f"{rows} account{'s' if rows != 1 else ''} listed, {shown} unbilled loan{'s' if shown != 1 else ''} in total" + (
        "" if shown == total else f" (the service counts {total})")


def _code(*texts: str) -> str:
    for text in texts:
        found = SP_CODE.search(text)
        if found:
            return found.group(0)
    return ""


def _title(key: str, area: str, outputs: list[dict], error_text: str) -> str:
    for kind in ("ticket_draft", "ops_handoff"):
        for output in outputs:
            if output["kind"] == kind:
                return output["title"]
    parts = key.split(":", 2)
    if area.endswith("-tqf") and len(parts) == 3:
        return f"{parts[1]}: {_clip(EXCEPTION_PREFIX.sub('', parts[2].rsplit(':no_playbook', 1)[0]), 110)}"
    if area == "billing":
        return f"Unbilled open loans: {error_text.splitlines()[0] if error_text else parts[-1]}"
    return _clip(error_text.splitlines()[0] if error_text else key, 140)


def _clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _summary(outputs: list[dict]) -> str:
    primary = next((o for kind in ACTION_KINDS for o in outputs if o["kind"] == kind), None)
    for output in outputs:
        why = WHY.search(output["body"])
        if why:
            return why.group(1).strip()
    if primary:
        paragraph = next((p for p in primary["body"].split("\n\n") if p.strip()), "")
        return re.sub(r"^@biz-ops ", "", paragraph.strip().replace("\n", " "))
    for output in outputs:
        first_line = output["body"].split("\n", 1)[0].strip()
        if first_line:
            return first_line
    return ""


def _route(outputs: list[dict]) -> str:
    for output in outputs:
        route_to = output["meta"].get("route_to")
        if route_to:
            return route_to.lstrip("@")
    return "dev" if any(o["kind"] in ("ticket_draft", "dev_ticket") for o in outputs) else ""


def parse_finding(lines: list[str], window_days: int) -> dict:
    start = BLOCK_START.match(lines[0])
    assert start is not None
    key = start.group(3).strip()
    outputs, level_one = _parse_outputs(lines[1:])
    stat = level_one[0].strip() if level_one else ""
    counted = re.match(r"(\d+) ([^,]*)", stat)
    highlights = next((line.strip() for line in level_one if re.match(r"\s+(largest|oldest|latest):", line)), "")
    log = next((line.strip()[5:].strip() for line in level_one if line.strip().startswith("log:")), "")
    helpful = {}
    for line in level_one:
        matched = HELPFUL.match(line)
        if matched:
            text = matched.group(2).strip()
            helpful[matched.group(1)] = {"found": not text.startswith("none found"), "text": text}
    area = key.split(":", 1)[0]
    error_text = _error_text(outputs)
    sample_kind, samples = _samples(outputs, highlights)
    primary = next((o for kind in ACTION_KINDS for o in outputs if o["kind"] == kind), None)
    next_step = ""
    for output in outputs:
        found = NEXT.search(output["body"])
        if found:
            next_step = found.group(1).strip()
            break
    return {
        "id": finding_id(key),
        "key": key,
        "disposition": DISPOSITION[start.group(1)],
        "label": start.group(2).strip(),
        "area": area,
        "title": _title(key, area, outputs, error_text),
        "code": _code(key, error_text, " ".join(o["title"] for o in outputs)),
        "count": int(counted.group(1)) if counted else 0,
        "unit": counted.group(2).strip() if counted else "",
        "dollars": to_money(stat),
        "window_days": window_days,
        "stat": stat,
        "highlights": highlights,
        "log": log,
        "helpful": helpful,
        "error_text": error_text,
        "summary": _summary(outputs),
        "route": _route(outputs),
        "next_step": next_step,
        "sample_kind": sample_kind,
        "sample_columns": SAMPLE_COLUMNS[sample_kind],
        "samples": samples,
        "samples_note": _samples_note(sample_kind, samples, int(counted.group(1)) if counted else 0),
        "draft": {"kind": primary["kind"], "note": primary["note"], "title": primary["title"], "body": primary["body"], "meta": primary["meta"]} if primary else None,
    }


def summarize_unchecked(reason: str) -> str:
    denied = re.search(r"permission denied for schema (\w+)", reason)
    if denied:
        return f"permission denied for schema {denied.group(1)}"
    if "rail checker" in reason:
        return "rail checker rejected the query"
    return " ".join(reason.split())[:160]


def parse_unchecked(text: str) -> list[dict]:
    found = UNCHECKED.search(text)
    if not found:
        return []
    entries = []
    for entry in UNCHECKED_SPLIT.split(found.group(1).strip()):
        name, _, reason = entry.partition(": query failed")
        entries.append({"name": name.strip(), "reason": summarize_unchecked(reason.lstrip(" —-"))})
    return entries


def parse_report(text: str) -> dict:
    unchecked = parse_unchecked(text)
    body = UNCHECKED.sub("", text)
    head, blocks = _split_blocks(body)
    header = HEADER.search(head)
    window_days = int(header.group(1)) if header else 0
    findings = [parse_finding(block, window_days) for block in blocks]
    rank = {"bug": 0, "ops": 1, "review": 2}
    findings.sort(key=lambda f: (rank[f["disposition"]], -(f["dollars"] or 0), -f["count"]))
    return {
        "window_days": window_days,
        "signatures": int(header.group(2)) if header else len(findings),
        "failures": int(header.group(3)) if header else sum(f["count"] for f in findings),
        "findings": findings,
        "unchecked": unchecked,
    }
