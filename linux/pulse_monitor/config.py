"""Preferences in $XDG_CONFIG_HOME/pulse/settings.json; the token in the desktop
keyring (libsecret) and, where no keyring runs, in a 0600 file next to it."""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path

from . import APP_ID
from .alerts import AlertSettings
from .client import base_url


def config_dir() -> Path:
    root = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(root) / "pulse"


@dataclass
class Preferences:
    address: str = ""
    ssh_target: str = ""
    portainer_url: str = ""
    cockpit_url: str = ""
    language: str = "system"          # system, en, tr
    run_in_background: bool = True
    tray_icon: bool = True
    tray_animation: str = "server"    # server, cat, pulse, none
    animation_follows_load: bool = True
    tray_label: bool = True           # temperature and CPU next to the icon (Ubuntu, KDE)
    auto_check_updates: bool = True
    last_update_check: float = 0.0
    notified_update: str = ""
    notifications_paused_until: float = 0.0
    alerts: AlertSettings = field(default_factory=AlertSettings)

    @classmethod
    def load(cls, path: Path | None = None) -> Preferences:
        path = path or config_dir() / "settings.json"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
        names = {f.name for f in fields(cls)} - {"alerts"}
        prefs = cls(**{k: v for k, v in data.items() if k in names})
        prefs.alerts = AlertSettings.from_dict(data.get("alerts"))
        prefs._path = path
        return prefs

    def save(self) -> None:
        path = getattr(self, "_path", config_dir() / "settings.json")
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")
        tmp.replace(path)

    @property
    def host(self) -> str | None:
        url = base_url(self.address)
        if not url:
            return None
        from urllib.parse import urlsplit
        return urlsplit(url).hostname

    def resolved_ssh(self) -> str | None:
        target = self.ssh_target or self.host or ""
        return f"ssh://{target}" if target else None

    def resolved_portainer(self) -> str | None:
        return self.portainer_url or (f"https://{self.host}:9443" if self.host else None)

    def resolved_cockpit(self) -> str | None:
        return self.cockpit_url or (f"https://{self.host}:9090" if self.host else None)


# Token ----------------------------------------------------------------------

_SCHEMA = None


def _secret():
    """libsecret, or None when it or a keyring daemon is missing."""
    global _SCHEMA
    try:
        import gi
        gi.require_version("Secret", "1")
        from gi.repository import Secret
    except (ImportError, ValueError):
        return None, None
    if _SCHEMA is None:
        _SCHEMA = Secret.Schema.new(APP_ID + ".Token", Secret.SchemaFlags.NONE,
                                    {"kind": Secret.SchemaAttributeType.STRING})
    return Secret, _SCHEMA


def _token_file() -> Path:
    return config_dir() / "token"


def load_token() -> str:
    path = _token_file()
    if path.exists():
        return path.read_text(encoding="utf-8").strip()
    secret, schema = _secret()
    if secret:
        try:
            return secret.password_lookup_sync(schema, {"kind": "agent"}, None) or ""
        except Exception:   # keyring locked or not running
            return ""
    return ""


def save_token(token: str) -> str:
    """Stores the token; returns "keyring" or "file" (where it went)."""
    secret, schema = _secret()
    if secret:
        try:
            if token:
                secret.password_store_sync(schema, {"kind": "agent"}, secret.COLLECTION_DEFAULT,
                                           "Pulse agent token", token, None)
            else:
                secret.password_clear_sync(schema, {"kind": "agent"}, None)
            _token_file().unlink(missing_ok=True)
            return "keyring"
        except Exception:
            pass
    path = _token_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(token)
    return "file"
