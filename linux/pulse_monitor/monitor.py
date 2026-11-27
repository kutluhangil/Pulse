"""Live connection to the agent: a worker thread streams snapshots, everything
the UI sees changes on the GLib main loop. Reconnects with backoff, marks data
stale after 12 s and feeds the alert engine (port of PulseUI/Monitor.swift)."""

from __future__ import annotations

import threading
import time
from collections import deque
from collections.abc import Callable
from datetime import datetime, timezone

from gi.repository import GLib

from .alerts import AlertEngine, AlertEvent, AlertSettings
from .client import AgentClient, Unauthorized, describe
from .i18n import _
from .model import HistoryPoint, Snapshot

NOT_CONFIGURED, CONNECTING, LIVE, OFFLINE, UNAUTHORIZED = "not_configured", "connecting", "live", "offline", "unauthorized"


class Monitor:
    STALE_AFTER = 12.0
    HISTORY = 600   # ten minutes at one point a second

    def __init__(self, alert_settings: AlertSettings | None = None):
        self.snapshot: Snapshot | None = None
        self.connection = NOT_CONFIGURED
        self.reason = ""
        self.history: deque[HistoryPoint] = deque(maxlen=self.HISTORY)
        self.latency_ms: float | None = None
        self.last_update: float | None = None
        self.client: AgentClient | None = None
        self.engine = AlertEngine(alert_settings or AlertSettings())
        self.on_alerts: Callable[[list[AlertEvent]], None] | None = None
        self._listeners: list[Callable[[], None]] = []
        self._generation = 0
        self._tick_source = 0
        self._ticks = 0
        self._address = ""
        self._token = ""

    # Public ---------------------------------------------------------------

    def subscribe(self, fn: Callable[[], None]) -> None:
        self._listeners.append(fn)

    def configure(self, address: str, token: str) -> None:
        self._address, self._token = address, token
        self.snapshot = None
        self.history.clear()
        self.latency_ms = None
        self.reconnect()

    def start(self) -> None:
        if not self._tick_source:
            self._tick_source = GLib.timeout_add_seconds(5, self._tick)

    def reconnect(self) -> None:
        self._generation += 1
        gen = self._generation
        if self.client:
            self.client.close()
        client = AgentClient(self._address, self._token)   # one per connection, so close() is unambiguous
        self.client = client
        if not client.base or not client.token:
            self._set(NOT_CONFIGURED, "")
            return
        threading.Thread(target=self._run, args=(gen, client), daemon=True, name="pulse-stream").start()

    @property
    def is_live(self) -> bool:
        return self.connection == LIVE and not self.is_stale

    @property
    def is_stale(self) -> bool:
        return self.last_update is None or time.monotonic() - self.last_update > self.STALE_AFTER

    def set_alert_settings(self, settings: AlertSettings) -> None:
        self.engine.settings = settings

    # Worker thread ---------------------------------------------------------

    def _run(self, gen: int, client: AgentClient) -> None:
        backoff = 1.0
        while gen == self._generation:
            if self.connection != LIVE:
                self._post(gen, self._set, CONNECTING, "")
            try:
                try:
                    points = client.history()
                    self._post(gen, self._seed, points)
                except Unauthorized:
                    raise
                except Exception:
                    pass   # history is a nicety; the stream still works
                for snap in client.stream():
                    if gen != self._generation:
                        return
                    backoff = 1.0
                    self._post(gen, self._receive, snap)
            except Unauthorized:
                self._post(gen, self._set, UNAUTHORIZED, _("Token rejected"))
                backoff = 30.0
            except Exception as e:   # network, TLS, schema: show it and retry
                if gen != self._generation:
                    return
                self._post(gen, self._set, OFFLINE, describe(e))
            self._post(gen, self._evaluate)
            deadline = time.monotonic() + backoff
            while time.monotonic() < deadline:
                if gen != self._generation:
                    return
                time.sleep(0.25)
            backoff = min(backoff * 2, 30.0)

    def _post(self, gen: int, fn, *args) -> None:
        def run():
            if gen == self._generation:
                fn(*args)
            return GLib.SOURCE_REMOVE
        GLib.idle_add(run)

    # Main loop -------------------------------------------------------------

    def _seed(self, points: list[HistoryPoint]) -> None:
        if not self.history and points:
            self.history.extend(points[-self.HISTORY:])
            self._changed()

    def _receive(self, snap: Snapshot) -> None:
        self.snapshot = snap
        self.last_update = time.monotonic()
        self.connection, self.reason = LIVE, ""
        self.history.append(HistoryPoint.of(snap))
        self._evaluate()
        self._changed()

    def _set(self, connection: str, reason: str) -> None:
        if (self.connection, self.reason) != (connection, reason):
            self.connection, self.reason = connection, reason
            self._changed()

    def _tick(self) -> bool:
        if self.connection == LIVE and self.is_stale:
            self._set(OFFLINE, _("No data for a while"))
            self.reconnect()
        self._evaluate()
        self._ticks += 1
        if self._ticks % 2 == 0 and self.connection == LIVE and self.client:
            client, gen = self.client, self._generation
            threading.Thread(target=self._measure, args=(gen, client), daemon=True).start()
        return GLib.SOURCE_CONTINUE

    def _measure(self, gen: int, client: AgentClient) -> None:
        try:
            ms = client.latency()
        except Exception:
            return
        self._post(gen, self._set_latency, ms)

    def _set_latency(self, ms: float) -> None:
        self.latency_ms = ms
        self._changed()

    def _evaluate(self) -> None:
        events = self.engine.evaluate(self.snapshot, self.is_live, datetime.now(timezone.utc))
        if events and self.on_alerts:
            self.on_alerts(events)

    def _changed(self) -> None:
        for fn in list(self._listeners):
            fn()
