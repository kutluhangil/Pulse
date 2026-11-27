"""Number formatting, matching the macOS app (decimal units, whole-KB rates)."""

from __future__ import annotations

import re

from . import i18n
from .i18n import _


def number(v: float, digits: int = 0, lang: str | None = None) -> str:
    text = f"{v:,.{digits}f}"
    if (lang or i18n.language()) == "tr":
        text = text.replace(",", "\0").replace(".", ",").replace("\0", ".")
    return text


def bytes_(b: int, lang: str | None = None) -> str:
    """554 GB, 1.4 TB (decimal, like the macOS Finder and Mole)."""
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    v, i = float(b), 0
    while v >= 1000 and i < len(units) - 1:
        v /= 1000
        i += 1
    return f"{number(v, 1 if i >= 3 and v < 100 else 0, lang)} {units[i]}"


def rate(bps: int, lang: str | None = None) -> str:
    kb = bps / 1000
    if kb < 1000:
        return f"{number(kb, 0, lang)} KB/s"
    mb = kb / 1000
    return f"{number(mb, 1 if mb < 100 else 0, lang)} MB/s"


def percent(p: float, lang: str | None = None) -> str:
    return number(p, 0, lang)


def ram_size(b: int) -> str:
    return f"{round(b / 1_073_741_824)} GB"


def uptime(secs: int) -> str:
    d, h, m = secs // 86_400, secs % 86_400 // 3_600, secs % 3_600 // 60
    if d:
        return _("up {d}d {h}h").format(d=d, h=h)
    if h:
        return _("up {h}h {m}m").format(h=h, m=m)
    return _("up {m}m").format(m=m)


def short_cpu(model: str) -> str:
    """"Intel Core i7-3615QM" -> "i7-3615QM"."""
    parts = model.split()
    if parts and "-" in parts[-1]:
        return parts[-1]
    return " ".join(parts[-2:])


def short_os(os_name: str) -> str:
    """"Ubuntu 24.04.5 LTS" -> "Ubuntu 24.04"."""
    words = os_name.replace(" LTS", "").split()
    return " ".join(re.sub(r"^(\d+\.\d+)\.\d+$", r"\1", w) for w in words)
