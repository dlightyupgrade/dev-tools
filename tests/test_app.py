import http.client
import json
import socket
import threading
import time
from pathlib import Path

import pytest

from servicing_triage_ui.app import App, import_report, serve
from servicing_triage_ui.headless import STATS_TOOL, TRIAGE_TOOL
from servicing_triage_ui.security import Guard
from servicing_triage_ui.store import Store
from servicing_triage_ui.sumo_index import SumoIndex

FIXTURE = Path(__file__).parent / "fixtures" / "triage_sample.json"
TEXT = json.loads(FIXTURE.read_text())["text"]
STATS_TEXT = (Path(__file__).parent / "fixtures" / "stats_sample.txt").read_text()
SESSION = "0f8fad5b-d9cb-469f-a165-70867728950e"
TOKEN = "test-token"


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@pytest.fixture
def running(tmp_path, monkeypatch):
    monkeypatch.setenv("TRIAGE_UI_DRY_RUN", "1")
    stream = tmp_path / "stream.jsonl"
    stream.write_text("\n".join(json.dumps(e) for e in [
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t", "name": TRIAGE_TOOL, "input": {}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t", "content": [{"type": "text", "text": json.dumps({"text": TEXT})}]}]}},
        {"type": "result", "total_cost_usd": 0.05, "duration_ms": 10, "is_error": False, "result": "done"},
    ]))
    final = tmp_path / "final.json"
    final.write_text(json.dumps({"type": "result", "is_error": False, "result": "Looks like ops.", "session_id": SESSION, "total_cost_usd": 0.2, "duration_ms": 5000}))
    claude = tmp_path / "claude"
    stats_stream = tmp_path / "stats.jsonl"
    stats_stream.write_text("\n".join(json.dumps(e) for e in [
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "s", "name": STATS_TOOL, "input": {}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "s", "content": [{"type": "text", "text": json.dumps({"text": STATS_TEXT})}]}]}},
        {"type": "result", "total_cost_usd": 0.03, "duration_ms": 10, "is_error": False, "result": "done"},
    ]))
    claude.write_text(
        '#!/bin/bash\ncase "$*" in *"Call the daily_stats tool"*) cat ' + str(stats_stream) + '; exit 0;; esac\n'
        'for a in "$@"; do\n [ "$a" = "stream-json" ] && cat ' + str(stream) + ' && exit 0\n [ "$a" = "json" ] && cat ' + str(final) + ' && exit 0\ndone\n'
    )
    claude.chmod(0o755)
    port = free_port()
    store = Store(tmp_path / "home")
    app = App(store, Guard(port, token=TOKEN), SumoIndex(None), tmp_path)
    app.claude = str(claude)
    server = serve(app, port)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield app, port
    server.shutdown()
    server.server_close()


def call(port, method, path, body=None, headers=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    send = {"Content-Type": "application/json", "X-Triage-Token": TOKEN} if method == "POST" else {}
    send.update(headers or {})
    connection.request(method, path, json.dumps(body) if body is not None else None, send)
    response = connection.getresponse()
    raw = response.read()
    connection.close()
    try:
        return response.status, json.loads(raw)
    except ValueError:
        return response.status, raw.decode()


def wait_for_jobs(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        state = call(port, "GET", "/api/state")[1]
        if not any(job["status"] == "running" for job in state["jobs"]):
            return state
        time.sleep(0.1)
    raise AssertionError("jobs did not finish")


def first_finding_id(app):
    import_report(app.store, FIXTURE)
    return app.store.latest_report()["findings"][0]["id"]


def test_index_embeds_the_token_and_sets_security_headers(running):
    _, port = running
    status, page = call(port, "GET", "/")
    assert status == 200 and TOKEN in page and "__TOKEN__" not in page
    connection = http.client.HTTPConnection("127.0.0.1", port)
    connection.request("GET", "/")
    headers = {k.lower(): v for k, v in connection.getresponse().getheaders()}
    assert headers["x-frame-options"] == "DENY"
    assert "default-src 'self'" in headers["content-security-policy"]
    assert "access-control-allow-origin" not in headers


def test_foreign_host_header_is_refused_even_for_gets(running):
    _, port = running
    assert call(port, "GET", "/api/state", headers={"Host": "evil.example"})[0] == 403
    assert call(port, "GET", "/", headers={"Host": f"evil.example:{port}"})[0] == 403


def test_static_allowlist_and_unknown_paths(running):
    _, port = running
    assert call(port, "GET", "/static/app.js")[0] == 200
    assert call(port, "GET", "/static/../app.py")[0] == 404
    assert call(port, "GET", "/static/index.html")[0] == 404
    assert call(port, "GET", "/nope")[0] == 404


@pytest.mark.parametrize("headers", [
    {"X-Triage-Token": "wrong"},
    {"Content-Type": "text/plain"},
    {"Origin": "https://evil.example"},
])
def test_post_guards_reject_bad_token_content_type_and_origin(running, headers):
    app, port = running
    finding_id = first_finding_id(app)
    status, body = call(port, "POST", "/api/launch", {"finding_id": finding_id}, headers)
    assert status == 403, body


def test_post_without_any_token_is_rejected(running):
    _, port = running
    connection = http.client.HTTPConnection("127.0.0.1", port)
    connection.request("POST", "/api/launch", "{}", {"Content-Type": "application/json"})
    assert connection.getresponse().status == 403


def test_state_after_import_has_findings_and_capabilities(running):
    app, port = running
    first_finding_id(app)
    state = call(port, "GET", "/api/state")[1]
    assert len(state["report"]["findings"]) == 6
    assert state["report"]["source"] == "import:triage_sample.json"
    assert state["capabilities"]["dry_run"] is True and state["capabilities"]["headless"] is True
    assert state["report"]["findings"][0]["sumo"] is None


def test_launch_builds_the_prompt_server_side(running):
    app, port = running
    finding_id = first_finding_id(app)
    status, result = call(port, "POST", "/api/launch", {"finding_id": finding_id, "prompt": "ignored; rm -rf ~"})
    assert status == 200 and result["dry_run"] is True
    script = Path(result["script"]).read_text()
    assert "ignored" not in script and "rm -rf" not in script
    assert "Triage one servicing failure" in script
    assert call(port, "POST", "/api/launch", {"finding_id": "nope"})[0] == 404
    assert call(port, "POST", "/api/launch", {"finding_id": finding_id, "resume": True})[0] == 400


def test_known_issue_roundtrip_and_validation(running):
    app, port = running
    finding_id = first_finding_id(app)
    status, known = call(port, "POST", "/api/known", {"finding_id": finding_id, "state": "ticketed", "note": "retry bug", "ticket": "SI-123"})
    assert status == 200 and known[finding_id]["ticket"] == "SI-123"
    assert call(port, "GET", "/api/state")[1]["known"][finding_id]["note"] == "retry bug"
    assert call(port, "POST", "/api/known", {"finding_id": finding_id, "state": "bogus"})[0] == 400
    assert call(port, "POST", "/api/known", {"finding_id": finding_id, "state": "known", "ticket": "not a key"})[0] == 400
    assert call(port, "POST", "/api/known", {"finding_id": finding_id, "state": "known", "ticket": "SI-1\nX"})[0] == 400
    assert call(port, "POST", "/api/known", {"finding_id": finding_id, "state": "known", "note": "x" * 301})[0] == 400
    assert call(port, "POST", "/api/known", {"finding_id": "nope", "state": "known"})[0] == 404
    status, known = call(port, "POST", "/api/known", {"finding_id": finding_id, "state": "open"})
    assert finding_id not in known


def test_refresh_job_replaces_the_report_and_is_audited(running):
    app, port = running
    status, job = call(port, "POST", "/api/refresh", {"window_days": 1})
    assert status == 200 and job["status"] == "running"
    state = wait_for_jobs(port)
    assert state["jobs"][0]["status"] == "done"
    assert state["report"]["source"] == "headless" and len(state["report"]["findings"]) == 6
    audit = (app.store.home / "audit.jsonl").read_text()
    assert "refresh_started" in audit and "refresh_finished" in audit
    assert call(port, "POST", "/api/refresh", {"window_days": 0})[0] == 400
    assert call(port, "POST", "/api/refresh", {"window_days": "7"})[0] == 400


def test_investigation_saves_the_result_and_allows_resume(running):
    app, port = running
    finding_id = first_finding_id(app)
    assert call(port, "POST", "/api/investigate", {"finding_id": finding_id})[0] == 200
    state = wait_for_jobs(port)
    saved = state["investigations"][finding_id]
    assert saved["result"] == "Looks like ops." and saved["session_id"] == SESSION
    status, result = call(port, "POST", "/api/launch", {"finding_id": finding_id, "resume": True})
    assert status == 200 and Path(result["script"]).read_text().rstrip().endswith(f"--resume {SESSION}")
    assert call(port, "POST", "/api/investigate", {"finding_id": "nope"})[0] == 404


def test_duplicate_runs_are_refused(running):
    app, port = running
    release = threading.Event()
    original = app.store.save_report

    def slow(report, source):
        release.wait(5)
        return original(report, source)

    app.store.save_report = slow
    assert call(port, "POST", "/api/refresh", {"window_days": 1})[0] == 200
    status, body = call(port, "POST", "/api/refresh", {"window_days": 1})
    release.set()
    assert status == 400 and "already running" in body["error"]
    wait_for_jobs(port)


def test_oversized_and_malformed_bodies_are_rejected(running):
    _, port = running
    assert call(port, "POST", "/api/known", {"finding_id": "x", "note": "y" * 20000})[0] == 413
    connection = http.client.HTTPConnection("127.0.0.1", port)
    connection.request("POST", "/api/known", "[1,2]", {"Content-Type": "application/json", "X-Triage-Token": TOKEN})
    assert connection.getresponse().status == 400


def test_stats_refresh_saves_parsed_stats(running):
    app, port = running
    assert call(port, "GET", "/api/state")[1]["stats"] is None
    assert call(port, "POST", "/api/stats", {"day": "yesterday"})[0] == 200
    state = wait_for_jobs(port)
    assert state["jobs"][0]["status"] == "done"
    assert state["stats"]["day"] == "Thu 2026-10-15" and len(state["stats"]["sections"]) == 3
    assert call(port, "POST", "/api/stats", {"day": "last week"})[0] == 400


def test_pin_roundtrip_and_unknown_finding(running):
    app, port = running
    finding_id = first_finding_id(app)
    assert call(port, "POST", "/api/pin", {"finding_id": finding_id, "pinned": True})[1] == [finding_id]
    assert call(port, "GET", "/api/state")[1]["pins"] == [finding_id]
    assert call(port, "POST", "/api/pin", {"finding_id": finding_id, "pinned": False})[1] == []
    assert call(port, "POST", "/api/pin", {"finding_id": "nope", "pinned": True})[0] == 404


def test_finished_investigation_needs_attention_until_seen(running):
    app, port = running
    finding_id = first_finding_id(app)
    call(port, "POST", "/api/investigate", {"finding_id": finding_id})
    state = wait_for_jobs(port)
    assert state["attention"][finding_id]["kind"] == "result"
    assert call(port, "POST", "/api/seen", {"finding_id": finding_id})[0] == 200
    assert finding_id not in call(port, "GET", "/api/state")[1]["attention"]


def test_failed_investigation_is_flagged(running):
    app, port = running
    finding_id = first_finding_id(app)
    app.claude = "/bin/false"
    call(port, "POST", "/api/investigate", {"finding_id": finding_id})
    state = wait_for_jobs(port)
    assert state["attention"][finding_id]["kind"] == "failed"
