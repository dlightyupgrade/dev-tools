"""The local HTTP server: static UI, a JSON API, and background jobs for refresh and headless investigation."""

from __future__ import annotations

import json
import mimetypes
import os
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import headless, launcher
from .parser import parse_report
from .security import Guard
from .store import Store
from .sumo_index import SumoIndex, needles_for

STATIC = Path(__file__).parent / "static"
STATIC_FILES = {"app.js", "style.css"}
MAX_BODY = 16_384
CSP = "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"


class App:
    def __init__(self, store: Store, guard: Guard, sumo: SumoIndex, cwd: Path) -> None:
        self.store = store
        self.guard = guard
        self.sumo = sumo
        self.cwd = cwd
        self.claude = headless.find_claude()
        self.timeout = int(os.environ.get("TRIAGE_UI_TIMEOUT_SECONDS", "900"))
        self.budget = float(os.environ.get("TRIAGE_UI_MAX_BUDGET_USD", "1.0"))
        self.jobs: dict[str, dict] = {}
        self.lock = threading.Lock()
        self.pool = ThreadPoolExecutor(max_workers=2)

    def finding(self, finding_id: str) -> dict | None:
        report = self.store.latest_report()
        return next((f for f in (report or {}).get("findings", []) if f["id"] == finding_id), None)

    def state(self) -> dict:
        report = self.store.latest_report()
        if report:
            for finding in report["findings"]:
                finding["sumo"] = self.sumo.find(needles_for(finding)) if self.sumo.available else None
        with self.lock:
            jobs = sorted(self.jobs.values(), key=lambda job: job["started"], reverse=True)[:20]
        return {
            "report": report,
            "known": self.store.known(),
            "investigations": self.store.investigations(),
            "jobs": jobs,
            "sumo": {"available": self.sumo.available, "count": len(self.sumo.monitors), **self.sumo.info},
            "capabilities": {
                "headless": self.claude is not None,
                "launch": os.environ.get("TRIAGE_UI_DRY_RUN") == "1" or sys.platform == "darwin",
                "dry_run": os.environ.get("TRIAGE_UI_DRY_RUN") == "1",
                "budget_usd": self.budget,
            },
        }

    def _start(self, kind: str, label: str, finding_id: str, work) -> dict:
        job = {"id": uuid.uuid4().hex[:10], "kind": kind, "label": label, "finding_id": finding_id, "status": "running", "started": time.time(), "message": ""}
        with self.lock:
            if any(j["status"] == "running" and j["kind"] == kind and j["finding_id"] == finding_id for j in self.jobs.values()):
                raise ValueError(f"a {kind} is already running" + (" for this finding" if finding_id else ""))
            if sum(1 for j in self.jobs.values() if j["status"] == "running") >= 2:
                raise ValueError("two runs are already in progress")
            self.jobs[job["id"]] = job

        def run() -> None:
            try:
                work(job)
                job["status"] = "done"
            except Exception as error:  # noqa: BLE001 - surfaced to the UI as the job message
                job["status"] = "error"
                job["message"] = str(error)[:400]
                self.store.audit(kind + "_failed", job=job["id"], finding=finding_id, error=job["message"])
            job["finished"] = time.time()

        self.pool.submit(run)
        return job

    def refresh(self, window_days: int) -> dict:
        if not self.claude:
            raise ValueError("claude CLI not found")
        if not 1 <= window_days <= 90:
            raise ValueError("window_days must be 1 to 90")

        def work(job: dict) -> None:
            self.store.audit("refresh_started", job=job["id"], window_days=window_days)
            report = headless.run_triage(self.claude, window_days, self.timeout, self.budget)
            self.store.save_report(report, "headless")
            job["message"] = f"{report['signatures']} signatures, {report['failures']} failures"
            self.store.audit("refresh_finished", job=job["id"], cost_usd=report["run"]["cost_usd"], signatures=report["signatures"])

        return self._start("refresh", f"Refresh, last {window_days} {'day' if window_days == 1 else 'days'}", "", work)

    def investigate(self, finding_id: str) -> dict:
        finding = self.finding(finding_id)
        if finding is None:
            raise LookupError("unknown finding")
        if not self.claude:
            raise ValueError("claude CLI not found")
        prompt = launcher.build_prompt(finding)

        def work(job: dict) -> None:
            self.store.audit("investigate_started", job=job["id"], finding=finding_id, key=finding["key"])
            outcome = headless.run_investigation(self.claude, prompt, self.timeout, self.budget)
            self.store.save_investigation(finding_id, {**outcome, "at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "key": finding["key"]})
            self.store.audit("investigate_finished", job=job["id"], finding=finding_id, session=outcome["session_id"], cost_usd=outcome["cost_usd"])

        return self._start("investigate", f"Investigate {finding['code'] or finding['title'][:40]}", finding_id, work)

    def launch(self, finding_id: str, resume: bool) -> dict:
        finding = self.finding(finding_id)
        if finding is None:
            raise LookupError("unknown finding")
        if not self.claude:
            raise ValueError("claude CLI not found")
        session = None
        prompt = None
        if resume:
            session = (self.store.investigations().get(finding_id) or {}).get("session_id")
            if not session:
                raise ValueError("no investigation session to resume for this finding")
        else:
            prompt = launcher.build_prompt(finding)
        result = launcher.launch(self.store.home, self.cwd, self.claude, prompt=prompt, resume=session)
        self.store.audit("launch", finding=finding_id, key=finding["key"], resume=bool(session), dry_run=result["dry_run"])
        return result


def make_handler(app: App):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ServicingTriageUI"

        def log_message(self, fmt, *args) -> None:  # noqa: A003 - quiet by default
            pass

        def _send(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", CSP)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status: int, value) -> None:
            self._send(status, json.dumps(value).encode(), "application/json")

        def _host_ok(self) -> bool:
            if app.guard.host_ok(self.headers.get("Host")):
                return True
            self._json(403, {"error": "host not allowed"})
            return False

        def do_GET(self) -> None:  # noqa: N802
            if not self._host_ok():
                return
            path = self.path.split("?", 1)[0]
            if path == "/":
                page = (STATIC / "index.html").read_text().replace("__TOKEN__", app.guard.token)
                self._send(200, page.encode(), "text/html; charset=utf-8")
            elif path.startswith("/static/") and path[8:] in STATIC_FILES:
                file = STATIC / path[8:]
                self._send(200, file.read_bytes(), mimetypes.guess_type(file.name)[0] or "application/octet-stream")
            elif path == "/api/state":
                self._json(200, app.state())
            else:
                self._json(404, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            if not self._host_ok():
                return
            refused = app.guard.post_ok(self.headers.get("Content-Type"), self.headers.get("Origin"), self.headers.get("X-Triage-Token"))
            if refused:
                self._json(403, {"error": refused})
                return
            try:
                length = int(self.headers.get("Content-Length") or 0)
                if length > MAX_BODY:
                    self._json(413, {"error": "body too large"})
                    return
                body = json.loads(self.rfile.read(length) or b"{}")
                if not isinstance(body, dict):
                    raise ValueError("body must be an object")
                self._json(200, self._route(self.path.split("?", 1)[0], body))
            except LookupError as error:
                self._json(404, {"error": str(error)})
            except (ValueError, RuntimeError) as error:
                self._json(400, {"error": str(error)})

        def _route(self, path: str, body: dict):
            finding_id = str(body.get("finding_id", ""))
            if path == "/api/refresh":
                window = body.get("window_days", 2)
                if not isinstance(window, int):
                    raise ValueError("window_days must be an integer")
                return app.refresh(window)
            if path == "/api/investigate":
                return app.investigate(finding_id)
            if path == "/api/launch":
                return app.launch(finding_id, bool(body.get("resume")))
            if path == "/api/known":
                if app.finding(finding_id) is None:
                    raise LookupError("unknown finding")
                app.store.audit("known", finding=finding_id, state=body.get("state"))
                return app.store.set_known(finding_id, str(body.get("state", "")), str(body.get("note", "")).strip(), str(body.get("ticket", "")).strip())
            raise LookupError("not found")

    return Handler


def serve(app: App, port: int) -> ThreadingHTTPServer:
    return ThreadingHTTPServer(("127.0.0.1", port), make_handler(app))


def import_report(store: Store, source: Path) -> dict:
    raw = source.read_text()
    try:
        parsed = json.loads(raw)
        text = parsed["text"] if isinstance(parsed, dict) else raw
    except ValueError:
        text = raw
    report = parse_report(text)
    return store.save_report(report, f"import:{source.name}")
