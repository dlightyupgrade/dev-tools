import json
from pathlib import Path

import pytest

from servicing_triage_ui import headless

FIXTURE = Path(__file__).parent / "fixtures" / "triage_sample.json"
TEXT = json.loads(FIXTURE.read_text())["text"]


def fake_claude(tmp_path: Path, stdout: str) -> str:
    payload = tmp_path / "payload"
    payload.write_text(stdout)
    script = tmp_path / "claude"
    script.write_text(f"#!/bin/bash\ncat {payload}\n")
    script.chmod(0o755)
    return str(script)


def stream(tool_result_content, final=None, tool_name=headless.TRIAGE_TOOL) -> str:
    events = [
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "tu1", "name": tool_name, "input": {}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tu1", "content": tool_result_content}]}},
        {"type": "result", "total_cost_usd": 0.18, "duration_ms": 1200, "is_error": False, "result": "done", **(final or {})},
    ]
    return "\n".join(json.dumps(event) for event in events)


def test_triage_text_from_inline_json_blocks():
    content = [{"type": "text", "text": json.dumps({"text": TEXT, "status": "ok"})}]
    assert headless.triage_text(content) == TEXT


def test_triage_text_from_plain_string():
    assert headless.triage_text(TEXT) == TEXT


def test_triage_text_from_a_saved_file(tmp_path, monkeypatch):
    root = tmp_path / "projects"
    saved = root / "p" / "s" / "tool-results" / "out.txt"
    saved.parent.mkdir(parents=True)
    saved.write_text(json.dumps({"text": TEXT, "status": "ok"}))
    monkeypatch.setattr(headless, "TOOL_RESULTS_ROOT", root)
    message = f"Error: result (58,525 characters) exceeds maximum allowed tokens. Output has been saved to {saved}.\nFormat: JSON"
    assert headless.triage_text(message) == TEXT


def test_triage_text_refuses_files_outside_tool_results(tmp_path, monkeypatch):
    root = tmp_path / "projects"
    root.mkdir()
    secret = tmp_path / "secret.txt"
    secret.write_text("nope")
    monkeypatch.setattr(headless, "TOOL_RESULTS_ROOT", root)
    with pytest.raises(headless.HeadlessError):
        headless.triage_text(f"Error: result (1 characters) exceeds. Output has been saved to {secret}.")
    inside_but_wrong = root / "p" / "notes.txt"
    inside_but_wrong.parent.mkdir()
    inside_but_wrong.write_text("nope")
    with pytest.raises(headless.HeadlessError):
        headless.triage_text(f"Error: result (1 characters) exceeds. Output has been saved to {inside_but_wrong}.")


def test_run_triage_parses_the_tool_result_not_the_model_reply(tmp_path):
    claude = fake_claude(tmp_path, stream([{"type": "text", "text": json.dumps({"text": TEXT, "status": "ok"})}]))
    report = headless.run_triage(claude, 1, 30, 1.0)
    assert report["signatures"] == 6 and len(report["findings"]) == 6
    assert report["run"] == {"cost_usd": 0.18, "duration_ms": 1200}


def test_run_triage_fails_clearly_when_the_tool_was_not_called(tmp_path):
    claude = fake_claude(tmp_path, json.dumps({"type": "result", "is_error": True, "result": "Budget exceeded"}))
    with pytest.raises(headless.HeadlessError, match="Budget exceeded"):
        headless.run_triage(claude, 1, 30, 1.0)


def test_run_triage_ignores_results_of_other_tools(tmp_path):
    claude = fake_claude(tmp_path, stream([{"type": "text", "text": "x"}], tool_name="Bash"))
    with pytest.raises(headless.HeadlessError):
        headless.run_triage(claude, 1, 30, 1.0)


def test_run_investigation_reads_the_final_json(tmp_path):
    out = {"type": "result", "is_error": False, "result": "Likely a bug.", "session_id": "s", "total_cost_usd": 0.3, "duration_ms": 9000}
    assert headless.run_investigation(fake_claude(tmp_path, json.dumps(out)), "p", 30, 1.0) == {
        "result": "Likely a bug.", "session_id": "s", "cost_usd": 0.3, "duration_ms": 9000,
    }


def test_run_investigation_reports_errors(tmp_path):
    with pytest.raises(headless.HeadlessError, match="Budget"):
        headless.run_investigation(fake_claude(tmp_path, json.dumps({"is_error": True, "result": "Budget exceeded"})), "p", 30, 1.0)
    with pytest.raises(headless.HeadlessError, match="no JSON"):
        headless.run_investigation(fake_claude(tmp_path, "garbage"), "p", 30, 1.0)


def test_only_read_only_servicing_tools_are_allowed():
    assert all(tool.startswith(headless.PREFIX) for tool in headless.READ_ONLY_TOOLS)
    assert not any(word in tool for tool in headless.READ_ONLY_TOOLS for word in ("create", "update", "delete", "send", "write"))
