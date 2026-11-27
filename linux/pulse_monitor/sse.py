"""Minimal Server-Sent Events parser (event, data, retry; comments ignored)."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Event:
    name: str
    data: str


@dataclass
class SSEParser:
    retry: int | None = None
    _name: str = ""
    _data: list[str] = field(default_factory=list)

    def feed(self, line: str) -> Event | None:
        """One line without its newline; returns an event when a blank line ends it."""
        if line == "":
            if not self._data:
                self._name = ""
                return None
            event = Event(self._name or "message", "\n".join(self._data))
            self._name, self._data = "", []
            return event
        if line.startswith(":"):
            return None
        key, _, value = line.partition(":")
        value = value[1:] if value.startswith(" ") else value
        if key == "event":
            self._name = value
        elif key == "data":
            self._data.append(value)
        elif key == "retry" and value.isdigit():
            self.retry = int(value)
        return None
