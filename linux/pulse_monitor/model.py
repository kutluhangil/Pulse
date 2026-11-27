"""Snapshot schema v1, mirrors agent/internal/model/snapshot.go (see docs/API.md)."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field, fields
from datetime import datetime, timezone

SUPPORTED_VERSION = 1
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def parse_time(raw: str | None) -> datetime:
    """Go writes RFC 3339 with up to nine fraction digits and the zero time as year 1."""
    if not raw:
        return EPOCH
    s = raw.replace("Z", "+00:00")
    s = re.sub(r"\.(\d{1,9})", lambda m: "." + m.group(1)[:6].ljust(6, "0"), s)
    try:
        t = datetime.fromisoformat(s)
    except ValueError:
        return EPOCH
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return EPOCH if t.year < 1970 else t


def _build(cls, data: dict | None):
    """Dataclass from a JSON object: unknown keys ignored, missing keys default."""
    data = data or {}
    kwargs = {}
    for f in fields(cls):
        if f.name in data:
            kwargs[f.name] = data[f.name]
    return cls(**kwargs)


@dataclass
class Host:
    name: str = ""
    cpuModel: str = ""
    cores: int = 0
    threads: int = 0
    memTotal: int = 0
    os: str = ""
    kernel: str = ""
    uptimeSec: int = 0
    agentVersion: str = ""


@dataclass
class Health:
    score: int = 0
    label: str = ""
    reasons: list[str] = field(default_factory=list)


@dataclass
class CPU:
    usage: float = 0.0
    perThread: list[float] = field(default_factory=list)
    load: list[float] = field(default_factory=list)
    freqMHz: float = 0.0
    ioWait: float = 0.0


@dataclass
class Thermal:
    packageC: float = 0.0
    coresC: list[float] = field(default_factory=list)
    critC: float = 0.0


@dataclass
class Fan:
    label: str = ""
    rpm: int = 0
    min: int = 0
    max: int = 0

    @property
    def speed_fraction(self) -> float:
        if self.max <= self.min:
            return 0.0
        return min(1.0, max(0.0, (self.rpm - self.min) / (self.max - self.min)))


@dataclass
class Mem:
    total: int = 0
    used: int = 0
    available: int = 0
    cached: int = 0
    swapTotal: int = 0
    swapUsed: int = 0

    @property
    def used_percent(self) -> float:
        return self.used / self.total * 100 if self.total else 0.0


@dataclass
class Disk:
    mount: str = ""
    device: str = ""
    total: int = 0
    used: int = 0
    free: int = 0
    readBps: int = 0
    writeBps: int = 0

    @property
    def used_percent(self) -> float:
        """Same as df: blocks reserved for root are left out."""
        usable = self.used + self.free
        return self.used / usable * 100 if usable else 0.0


@dataclass
class Net:
    iface: str = ""
    speedMbps: int = 0
    rxBps: int = 0
    txBps: int = 0
    rxTotal: int = 0
    txTotal: int = 0


@dataclass
class Container:
    id: str = ""
    name: str = ""
    project: str = ""
    image: str = ""
    state: str = ""
    health: str = ""
    statusText: str = ""
    cpu: float = 0.0
    memBytes: int = 0
    memLimit: int = 0
    createdAt: str = ""
    exitCode: int = 0
    restartCount: int = 0


@dataclass
class DockerState:
    available: bool = False
    version: str = ""
    error: str | None = None


@dataclass
class Probe:
    name: str = ""
    url: str = ""
    ok: bool = False
    status: int = 0
    ms: int = 0
    error: str | None = None
    checkedAt: str = ""

    @property
    def checked_at(self) -> datetime:
        return parse_time(self.checkedAt)

    @property
    def checked(self) -> bool:
        return self.checked_at > EPOCH


@dataclass
class SystemInfo:
    aptUpdates: int = 0
    securityUpdates: int = 0
    rebootRequired: bool = False


@dataclass
class Snapshot:
    v: int
    ts: datetime
    host: Host
    health: Health
    cpu: CPU
    thermal: Thermal
    fan: Fan | None
    mem: Mem
    disks: list[Disk]
    net: Net
    containers: list[Container]
    docker: DockerState
    probes: list[Probe]
    system: SystemInfo

    @classmethod
    def from_dict(cls, d: dict) -> Snapshot:
        return cls(
            v=d.get("v", 0),
            ts=parse_time(d.get("ts")),
            host=_build(Host, d.get("host")),
            health=_build(Health, d.get("health")),
            cpu=_build(CPU, d.get("cpu")),
            thermal=_build(Thermal, d.get("thermal")),
            fan=_build(Fan, d["fan"]) if d.get("fan") else None,
            mem=_build(Mem, d.get("mem")),
            disks=[_build(Disk, x) for x in d.get("disks") or []],
            net=_build(Net, d.get("net")),
            containers=[_build(Container, x) for x in d.get("containers") or []],
            docker=_build(DockerState, d.get("docker")),
            probes=[_build(Probe, x) for x in d.get("probes") or []],
            system=_build(SystemInfo, d.get("system")),
        )


class UnsupportedVersion(Exception):
    def __init__(self, version: int):
        super().__init__(f"agent schema v{version}")
        self.version = version


def decode_snapshot(raw: str | bytes) -> Snapshot:
    d = json.loads(raw)
    if d.get("v") != SUPPORTED_VERSION:
        raise UnsupportedVersion(d.get("v", 0))
    return Snapshot.from_dict(d)


@dataclass
class HistoryPoint:
    t: int = 0
    cpu: float = 0.0
    mem: float = 0.0
    temp: float = 0.0
    rx: int = 0
    tx: int = 0
    dr: int = 0
    dw: int = 0

    @classmethod
    def of(cls, s: Snapshot) -> HistoryPoint:
        disk = s.disks[0] if s.disks else Disk()
        return cls(int(s.ts.timestamp()), s.cpu.usage, s.mem.used_percent, s.thermal.packageC,
                   s.net.rxBps, s.net.txBps, disk.readBps, disk.writeBps)


def decode_history(raw: str | bytes) -> list[HistoryPoint]:
    d = json.loads(raw)
    return [_build(HistoryPoint, p) for p in d.get("points") or []]
