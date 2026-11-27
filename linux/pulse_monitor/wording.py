"""User-facing words shared by the window, tray and notifications."""

from __future__ import annotations

from . import fmt
from .alerts import AlertEvent
from .i18n import _
from .levels import Level, failing_containers, running_count
from .model import Snapshot


def health_label(score: int) -> str:
    if score >= 85:
        return _("Excellent")
    if score >= 65:
        return _("Good")
    if score >= 45:
        return _("Fair")
    return _("Needs Attention")


def activity_text(name: str) -> str:
    return {"idle": _("idle"), "normal": _("normal"), "busy": _("busy"), "high": _("high")}[name]


def temperature_word(level: Level) -> str:
    return (_("Normal"), _("Warm"), _("Hot"))[level]


def memory_word(level: Level) -> str:
    return (_("Normal"), _("High"), _("Critical"))[level]


REASONS = {
    "cpu_high": "High CPU", "mem_high": "High memory", "swap_high": "Heavy swap use",
    "disk_full": "Disk almost full", "overheating": "Overheating", "disk_io_heavy": "Heavy disk I/O",
    "container_down": "Container needs attention", "site_down": "A site is down",
    "reboot_required": "Restart required", "security_updates": "Security updates pending",
    "docker_unreachable": "Docker unreachable",
}


def reason_text(code: str) -> str:
    return _(REASONS[code]) if code in REASONS else code


def container_state_text(status: str) -> str:
    return {"healthy": _("Healthy"), "running": _("Running"), "starting": _("Starting"),
            "stopped": _("Stopped"), "failing": _("Failing")}[status]


def alert_text(e: AlertEvent, host: str) -> tuple[str, str]:
    v = fmt.percent(e.value)
    s = e.subject
    table = {
        ("offline", True): (_("{host} is unreachable"), _("No data from the Pulse agent for over a minute.")),
        ("offline", False): (_("{host} is back"), _("Live data is flowing again.")),
        ("hot", True): (_("{host} is running hot"), _("CPU at {v} °C.")),
        ("hot", False): (_("{host} cooled down"), _("CPU temperature is back to normal.")),
        ("memory", True): (_("{host} is low on memory"), _("Memory use at {v} %.")),
        ("memory", False): (_("{host} memory is back to normal"), ""),
        ("disk", True): (_("{host} disk is filling up"), _("Disk use at {v} %.")),
        ("disk", False): (_("{host} disk has room again"), ""),
        ("container", True): (_("Container {s} needs attention"), _("It stopped, crashed or turned unhealthy.")),
        ("container", False): (_("Container {s} recovered"), ""),
        ("probe", True): (_("{s} is down"), _("The site failed two checks in a row.")),
        ("probe", False): (_("{s} is back up"), ""),
        ("reboot", True): (_("{host} needs a restart"), _("Installed updates take effect after a reboot.")),
        ("reboot", False): (_("{host} restarted"), ""),
    }
    title, body = table[(e.kind, e.fired)]
    return title.format(host=host, v=v, s=s), body.format(host=host, v=v, s=s)


def status_summary(s: Snapshot) -> str:
    """Plain text for "Copy Status Summary"."""
    lines = [f"{s.host.name} · {_('health')} {s.health.score} ({health_label(s.health.score)})",
             f"CPU {fmt.percent(s.cpu.usage)}% · {fmt.percent(s.thermal.packageC)}°C · MEM {fmt.percent(s.mem.used_percent)}%"]
    if s.disks:
        d = s.disks[0]
        lines.append(f"{_('Disk')} {fmt.percent(d.used_percent)}% · {fmt.bytes_(d.free)} {_('free')}")
    failing = failing_containers(s)
    line = f"{_('Containers')}: {running_count(s)}/{len(s.containers)}"
    if failing:
        line += " · " + ", ".join(c.name for c in failing)
    lines.append(line)
    for p in s.probes:
        lines.append(f"{p.name}: {f'{p.ms} ms' if p.ok else (p.error or 'down')}")
    if s.health.reasons:
        lines.append(" · ".join(reason_text(r) for r in s.health.reasons))
    return "\n".join(lines)
