"""Looks for a newer Pulse release on GitHub (public API, no token)."""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from dataclasses import dataclass

from . import __version__

LATEST_URL = "https://api.github.com/repos/kutluhangil/Pulse/releases/latest"


def parse_version(raw: str) -> tuple[int, ...] | None:
    """"v0.1.0" -> (0, 1, 0); "1.3.0-beta" -> (1, 3, 0); anything else -> None."""
    m = re.match(r"^[vV]?(\d+(?:\.\d+)*)(?:[-+ ].*)?$", raw.strip())
    if not m:
        return None
    return tuple(int(x) for x in m.group(1).split("."))


def newer(a: tuple[int, ...], b: tuple[int, ...]) -> bool:
    """True when a is a later version than b (missing parts count as 0)."""
    n = max(len(a), len(b))
    return a + (0,) * (n - len(a)) > b + (0,) * (n - len(b))


@dataclass(frozen=True)
class Release:
    version: str
    tag: str
    page_url: str
    download_url: str | None   # the Linux package, when the release has one


def parse_release(raw: str | bytes) -> Release:
    d = json.loads(raw)
    tag = d.get("tag_name", "")
    v = parse_version(tag)
    if v is None or not d.get("html_url"):
        raise ValueError("malformed release")
    deb = next((a["browser_download_url"] for a in d.get("assets", []) if a.get("name", "").endswith(".deb")), None)
    return Release(".".join(map(str, v)), tag, d["html_url"], deb)


class NoRelease(Exception):
    pass


def latest(timeout: float = 15) -> Release:
    req = urllib.request.Request(LATEST_URL, headers={
        "Accept": "application/vnd.github+json", "User-Agent": "Pulse-Linux/" + __version__})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return parse_release(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise NoRelease() from e
        raise


def is_newer(release: Release, current: str = __version__) -> bool:
    cur = parse_version(current)
    rel = parse_version(release.version)
    return bool(cur and rel and newer(rel, cur))
