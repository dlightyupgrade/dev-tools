"""Runs Claude Code headless (`claude -p`) with a read-only tool allowlist.

A headless run cannot ask for permission, so the allowlist is the boundary: only the servicing-agent read tools.
Refresh takes the tool's own output from the stream rather than from the model's reply, so the text is never retyped.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

from .parser import parse_report

PREFIX = "mcp__plugin_servicing-plugin_servicing-agent__"
TRIAGE_TOOL = PREFIX + "failure_triage"
STATS_TOOL = PREFIX + "daily_stats"
READ_ONLY_TOOLS = [PREFIX + name for name in ("search_runbooks", "query_redshift", "search_logs", "investigate", "daily_stats", "failure_triage")]
SAVED = re.compile(r"saved to (\S+\.txt)")
TOOL_RESULTS_ROOT = Path.home() / ".claude" / "projects"


class HeadlessError(RuntimeError):
    pass


def find_claude() -> str | None:
    return shutil.which("claude") or next((str(p) for p in (Path.home() / ".local/bin/claude", Path("/opt/homebrew/bin/claude")) if p.exists()), None)


def _blocks_text(content) -> str:
    if isinstance(content, str):
        return content
    return "\n".join(block.get("text", "") for block in content if isinstance(block, dict))


def _saved_file_text(path_text: str) -> str:
    path = Path(path_text).resolve()
    if TOOL_RESULTS_ROOT.resolve() not in path.parents or "tool-results" not in path.parts:
        raise HeadlessError("tool result file is outside Claude Code's tool-results directory")
    return path.read_text()


def triage_text(content) -> str:
    """The `text` field of the failure_triage result, whether it arrived inline or was saved to a file."""
    raw = _blocks_text(content)
    saved = SAVED.search(raw)
    if raw.startswith("Error: result") and saved:
        raw = _saved_file_text(saved.group(1))
    try:
        parsed = json.loads(raw)
    except ValueError:
        return raw
    return parsed["text"] if isinstance(parsed, dict) and "text" in parsed else raw


def _events(stdout: str) -> list[dict]:
    events = []
    for line in stdout.splitlines():
        try:
            events.append(json.loads(line))
        except ValueError:
            continue
    return events


def run_tool_text(claude_bin: str, tool: str, prompt: str, timeout: int, budget_usd: float) -> tuple[str, dict]:
    """Runs one MCP tool headless and returns the tool's own output text plus the final event."""
    completed = subprocess.run(
        [claude_bin, "-p", prompt, "--output-format", "stream-json", "--verbose", "--allowedTools", tool,
         "--max-budget-usd", str(budget_usd), "--no-session-persistence"],
        capture_output=True, text=True, timeout=timeout, check=False,
    )
    events = _events(completed.stdout)
    tool_use_id = None
    text = None
    for event in events:
        message = event.get("message") or {}
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if event.get("type") == "assistant" and block.get("type") == "tool_use" and block.get("name") == tool:
                tool_use_id = block.get("id")
            elif event.get("type") == "user" and block.get("type") == "tool_result" and tool_use_id and block.get("tool_use_id") == tool_use_id:
                text = triage_text(block.get("content"))
    final = next((e for e in reversed(events) if e.get("type") == "result"), {})
    if text is None:
        raise HeadlessError(final.get("result") or "%s was not called (exit %s)" % (tool.rsplit("__", 1)[-1], completed.returncode))
    return text, final


def run_triage(claude_bin: str, window_days: int, timeout: int, budget_usd: float) -> dict:
    prompt = f"Call the failure_triage tool once with window_days {window_days} and output_format text. Then reply with only the word done."
    text, final = run_tool_text(claude_bin, TRIAGE_TOOL, prompt, timeout, budget_usd)
    report = parse_report(text)
    report["run"] = {"cost_usd": final.get("total_cost_usd"), "duration_ms": final.get("duration_ms")}
    return report


def run_stats(claude_bin: str, day: str, timeout: int, budget_usd: float) -> dict:
    prompt = f"Call the daily_stats tool once with day {day} and output_format text. Then reply with only the word done."
    text, final = run_tool_text(claude_bin, STATS_TOOL, prompt, timeout, budget_usd)
    return {"text": text, "run": {"cost_usd": final.get("total_cost_usd"), "duration_ms": final.get("duration_ms")}}


def run_investigation(claude_bin: str, prompt: str, timeout: int, budget_usd: float) -> dict:
    full_prompt = prompt + "\n\nReply in under 250 words: likely cause, the evidence you found, bug or ops, and the next step."
    completed = subprocess.run(
        [claude_bin, "-p", full_prompt, "--output-format", "json", "--allowedTools", *READ_ONLY_TOOLS, "--max-budget-usd", str(budget_usd)],
        capture_output=True, text=True, timeout=timeout, check=False,
    )
    try:
        parsed = json.loads(completed.stdout)
    except ValueError as error:
        raise HeadlessError("claude returned no JSON (exit %s)" % completed.returncode) from error
    final = parsed[-1] if isinstance(parsed, list) else parsed
    if final.get("is_error"):
        raise HeadlessError(str(final.get("result"))[:300])
    return {
        "result": final.get("result", ""),
        "session_id": final.get("session_id", ""),
        "cost_usd": final.get("total_cost_usd"),
        "duration_ms": final.get("duration_ms"),
    }
