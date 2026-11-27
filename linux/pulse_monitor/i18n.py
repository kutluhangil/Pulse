"""English source strings with a Turkish catalogue (tr.json next to this file).

The language follows LANGUAGE / LC_ALL / LC_MESSAGES / LANG unless Preferences
pins one; `set_language` is called once at start-up, before any window exists.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

_catalogue: dict[str, str] = {}
_lang = "en"


def system_language() -> str:
    for var in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(var, "")
        if value and value not in ("C", "C.UTF-8", "POSIX"):
            return "tr" if value.lower().startswith("tr") else "en"
    return "en"


def set_language(choice: str = "system") -> None:
    global _catalogue, _lang
    _lang = system_language() if choice == "system" else choice
    _catalogue = {}
    if _lang == "tr":
        _catalogue = json.loads((Path(__file__).with_name("tr.json")).read_text(encoding="utf-8"))


def language() -> str:
    return _lang


def _(text: str) -> str:
    return _catalogue.get(text, text)
