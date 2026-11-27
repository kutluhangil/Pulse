"""Traffic-light levels and container status, same thresholds as the macOS app
(app/Packages/PulseKit/Sources/PulseCore/Levels.swift) and the agent's health score."""

from __future__ import annotations

import re
from enum import IntEnum

from .model import Container, Snapshot


class Level(IntEnum):
    GOOD = 0
    WARN = 1
    CRITICAL = 2

    @property
    def css(self) -> str:
        return ("success", "warning", "error")[self]


def cpu_level(pct: float) -> Level:
    return Level.GOOD if pct < 50 else Level.WARN if pct < 85 else Level.CRITICAL


def temp_level(c: float) -> Level:
    return Level.GOOD if c < 65 else Level.WARN if c < 85 else Level.CRITICAL


def mem_level(pct: float) -> Level:
    return Level.GOOD if pct < 70 else Level.WARN if pct < 88 else Level.CRITICAL


def disk_level(pct: float) -> Level:
    return Level.GOOD if pct < 80 else Level.WARN if pct < 93 else Level.CRITICAL


def health_level(score: int) -> Level:
    return Level.GOOD if score >= 85 else Level.WARN if score >= 65 else Level.CRITICAL


def activity(pct: float) -> str:
    return "idle" if pct < 10 else "normal" if pct < 50 else "busy" if pct < 85 else "high"


def container_status(c: Container) -> str:
    """healthy, running, starting, stopped or failing."""
    if c.state in ("restarting", "dead"):
        return "failing"
    if c.state == "exited":
        return "stopped" if c.exitCode == 0 else "failing"
    if c.state in ("created", "paused"):
        return "stopped"
    return {"unhealthy": "failing", "starting": "starting", "healthy": "healthy"}.get(c.health, "running")


def container_level(c: Container) -> Level:
    return {"healthy": Level.GOOD, "running": Level.GOOD, "starting": Level.WARN,
            "stopped": Level.WARN, "failing": Level.CRITICAL}[container_status(c)]


def sorted_containers(s: Snapshot) -> list[Container]:
    """Containers that need attention first, then by CPU, then by name."""
    return sorted(s.containers, key=lambda c: (-container_level(c), -c.cpu, c.name))


def running_count(s: Snapshot) -> int:
    return sum(1 for c in s.containers if c.state == "running")


def failing_containers(s: Snapshot) -> list[Container]:
    return [c for c in s.containers if container_status(c) == "failing"]


def down_probes(s: Snapshot):
    return [p for p in s.probes if p.checked and not p.ok]


def attention_count(s: Snapshot) -> int:
    disk_crit = bool(s.disks) and disk_level(s.disks[0].used_percent) == Level.CRITICAL
    return (len(failing_containers(s)) + len(down_probes(s)) + int(s.system.rebootRequired)
            + int(temp_level(s.thermal.packageC) == Level.CRITICAL) + int(disk_crit))


def display_name(c: Container) -> str:
    """"perde-test-jellyfin-1" in project "perde-test" -> "jellyfin"."""
    name = c.name
    if c.project and name.startswith(c.project + "-"):
        name = name[len(c.project) + 1:]
    name = re.sub(r"(?<=.)-\d+$", "", name)
    return name or c.name
