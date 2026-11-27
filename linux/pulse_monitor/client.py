"""HTTP client for the Pulse agent (docs/API.md). Blocking; the monitor runs it in a thread."""

from __future__ import annotations

import socket
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Iterator

from . import __version__
from .i18n import _
from .model import HistoryPoint, Snapshot, UnsupportedVersion, decode_history, decode_snapshot
from .sse import SSEParser


def base_url(address: str) -> str | None:
    """Accepts "macmini-server.tailnet.ts.net:9123" or a full http(s) URL."""
    raw = address.strip().rstrip("/")
    if not raw:
        return None
    if "://" not in raw:
        raw = "https://" + raw
    u = urllib.parse.urlsplit(raw)
    if u.scheme not in ("http", "https") or not u.hostname:
        return None
    return urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, "", ""))


class Unauthorized(Exception):
    pass


class HTTPStatus(Exception):
    def __init__(self, code: int):
        super().__init__(f"HTTP {code}")
        self.code = code


class StreamEnded(Exception):
    pass


def describe(error: BaseException) -> str:
    """Short reason for the UI."""
    if isinstance(error, Unauthorized):
        return _("Token rejected")
    if isinstance(error, UnsupportedVersion):
        return _("Agent schema v{v} is not supported, update Pulse").format(v=error.version)
    if isinstance(error, HTTPStatus):
        return _("Server answered HTTP {code}").format(code=error.code)
    if isinstance(error, StreamEnded):
        return _("Connection closed")
    if isinstance(error, urllib.error.URLError):
        error = error.reason if isinstance(error.reason, BaseException) else error
    if isinstance(error, socket.gaierror):
        return _("Server not found (is Tailscale on?)")
    if isinstance(error, ConnectionRefusedError):
        return _("Agent is not running")
    if isinstance(error, (TimeoutError, socket.timeout)):
        return _("Timed out")
    if isinstance(error, ssl.SSLError):
        return _("TLS error")
    if isinstance(error, OSError):
        return _("Network unavailable")
    return str(error)


class AgentClient:
    def __init__(self, address: str, token: str):
        self.base = base_url(address)
        self.token = token
        self._stream_response = None

    def _request(self, path: str, query: dict | None = None, auth: bool = True) -> urllib.request.Request:
        if not self.base:
            raise ValueError(_("Invalid server address"))
        url = f"{self.base}/{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {"User-Agent": "Pulse-Linux/" + __version__}
        if auth:
            headers["Authorization"] = "Bearer " + self.token
        return urllib.request.Request(url, headers=headers)

    @staticmethod
    def _open(req, timeout: float):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise Unauthorized() from e
            raise HTTPStatus(e.code) from e

    def snapshot(self) -> Snapshot:
        with self._open(self._request("v1/snapshot"), 10) as r:
            return decode_snapshot(r.read())

    def history(self, range_: str = "10m") -> list[HistoryPoint]:
        with self._open(self._request("v1/history", {"range": range_}), 10) as r:
            return decode_history(r.read())

    def logs(self, container_id: str, tail: int = 200) -> str:
        with self._open(self._request(f"v1/containers/{container_id}/logs", {"tail": tail}), 15) as r:
            return r.read().decode("utf-8", "replace")

    def latency(self) -> float:
        """Round trip of the unauthenticated /health endpoint, in milliseconds."""
        start = time.monotonic()
        with self._open(self._request("health", auth=False), 5) as r:
            r.read()
        return (time.monotonic() - start) * 1000

    def stream(self) -> Iterator[Snapshot]:
        """Live snapshots until the connection drops; `close()` from another thread stops it."""
        req = self._request("v1/stream")
        req.add_header("Accept", "text/event-stream")
        resp = self._open(req, 30)
        self._stream_response = resp
        parser = SSEParser()
        try:
            for raw in resp:
                event = parser.feed(raw.decode("utf-8", "replace").rstrip("\r\n"))
                if event and event.name == "snapshot":
                    yield decode_snapshot(event.data)
        finally:
            self._stream_response = None
            resp.close()
        raise StreamEnded()

    def close(self) -> None:
        resp = self._stream_response
        if resp is not None:
            try:
                resp.fp.raw._sock.shutdown(socket.SHUT_RDWR)   # wakes the blocked read
            except (AttributeError, OSError):
                pass
            try:
                resp.close()
            except OSError:
                pass
