"""Request guards for a server that can open terminals and spend model budget.

The claude-observer launcher it was adapted from answers any GET from any origin. This one is bound to loopback, rejects
foreign Host headers (DNS rebinding), requires JSON plus a per-process token on every POST, and checks Origin when sent.
"""

from __future__ import annotations

import hmac
import secrets
from urllib.parse import urlsplit


class Guard:
    def __init__(self, port: int, token: str | None = None) -> None:
        self.port = port
        self.token = token or secrets.token_urlsafe(32)
        self.hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        self.origins = {f"http://{host}" for host in self.hosts}

    def host_ok(self, host: str | None) -> bool:
        return host is not None and host.lower() in self.hosts

    def origin_ok(self, origin: str | None) -> bool:
        if origin is None:
            return True
        parts = urlsplit(origin)
        return f"{parts.scheme}://{parts.netloc}".lower() in self.origins

    def token_ok(self, supplied: str | None) -> bool:
        return supplied is not None and hmac.compare_digest(supplied.encode(), self.token.encode())

    def post_ok(self, content_type: str | None, origin: str | None, supplied: str | None) -> str | None:
        """Returns None when the request may proceed, else the reason it was refused."""
        if (content_type or "").split(";")[0].strip().lower() != "application/json":
            return "content type must be application/json"
        if not self.origin_ok(origin):
            return "origin not allowed"
        if not self.token_ok(supplied):
            return "missing or wrong token"
        return None
