"""Launch at login through the XDG autostart directory."""

from __future__ import annotations

import os
from pathlib import Path

from . import APP_ID

ENTRY = f"""[Desktop Entry]
Type=Application
Name=Pulse
Comment=Live status of your home server
Exec=pulse-monitor --background
Icon={APP_ID}
X-GNOME-Autostart-enabled=true
NoDisplay=true
"""


def _path() -> Path:
    root = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(root) / "autostart" / f"{APP_ID}.desktop"


def enabled() -> bool:
    return _path().exists()


def set_enabled(on: bool) -> None:
    path = _path()
    if on:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(ENTRY, encoding="utf-8")
    else:
        path.unlink(missing_ok=True)
