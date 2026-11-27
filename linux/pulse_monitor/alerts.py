"""Snapshots in, fire/resolve events out: hold times, one alert per episode and a
cooldown after recovery. Port of PulseCore/Alerts.swift; pure logic, no GTK."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields
from datetime import datetime

from .levels import container_status
from .model import Snapshot


@dataclass
class AlertSettings:
    enabled: bool = True
    hotC: float = 85.0
    hotHold: float = 30
    memoryPct: float = 90.0
    memoryHold: float = 60
    diskPct: float = 85.0
    offlineHold: float = 60
    containers: bool = True
    probes: bool = True
    reboot: bool = True
    offline: bool = True
    cooldown: float = 600

    @classmethod
    def from_dict(cls, d: dict | None) -> AlertSettings:
        names = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in (d or {}).items() if k in names})

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class AlertEvent:
    key: str
    kind: str        # offline, hot, memory, disk, container, probe, reboot
    fired: bool      # False when resolved
    subject: str = ""
    value: float = 0.0


@dataclass
class AlertEngine:
    settings: AlertSettings = field(default_factory=AlertSettings)
    _pending: dict[str, datetime] = field(default_factory=dict)
    _active: dict[str, str] = field(default_factory=dict)
    _resolved: dict[str, datetime] = field(default_factory=dict)
    _probe_failures: dict[str, tuple[int, datetime]] = field(default_factory=dict)

    @property
    def active_keys(self) -> set[str]:
        return set(self._active)

    def evaluate(self, s: Snapshot | None, connected: bool, now: datetime) -> list[AlertEvent]:
        if not self.settings.enabled:
            return []
        cfg = self.settings
        events: list[AlertEvent] = []

        def check(key, kind, on, hold=0.0, subject="", value=0.0):
            e = self._step(key, kind, on, hold, subject, value, now)
            if e:
                events.append(e)

        check("offline", "offline", cfg.offline and (not connected or s is None), cfg.offlineHold)
        if not connected or s is None:
            return events

        check("hot", "hot", s.thermal.packageC >= cfg.hotC, cfg.hotHold, value=s.thermal.packageC)
        check("memory", "memory", s.mem.used_percent >= cfg.memoryPct, cfg.memoryHold, value=s.mem.used_percent)
        if s.disks:
            check("disk", "disk", s.disks[0].used_percent >= cfg.diskPct, value=s.disks[0].used_percent)
        if cfg.reboot:
            check("reboot", "reboot", s.system.rebootRequired)

        if cfg.containers:
            seen = set()
            for c in s.containers:
                key = "container:" + c.name
                seen.add(key)
                check(key, "container", container_status(c) == "failing", subject=c.name)
            for key in [k for k in self._active if k.startswith("container:") and k not in seen]:
                check(key, "container", False, subject=key.removeprefix("container:"))

        if cfg.probes:
            for p in s.probes:
                if not p.checked:
                    continue
                count, last = self._probe_failures.get(p.name, (0, None))
                if p.checked_at != last:
                    count = 0 if p.ok else count + 1
                    self._probe_failures[p.name] = (count, p.checked_at)
                check("probe:" + p.name, "probe", count >= 2, subject=p.name)   # two failed checks in a row
        return events

    def _step(self, key, kind, on, hold, subject, value, now) -> AlertEvent | None:
        if on:
            if key in self._active:
                return None
            since = self._pending.setdefault(key, now)
            if (now - since).total_seconds() < hold:
                return None
            resolved = self._resolved.get(key)
            if resolved and (now - resolved).total_seconds() < self.settings.cooldown:
                return None
            self._active[key] = kind
            return AlertEvent(key, kind, True, subject, value)
        self._pending.pop(key, None)
        if self._active.pop(key, None) is None:
            return None
        self._resolved[key] = now
        return AlertEvent(key, kind, False, subject, value)
