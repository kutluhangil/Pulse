"""Renders the window from the test fixture into PNGs (README and site).

    xvfb-run dbus-run-session -- python3 tests/screenshots.py OUT_DIR

No agent or network: the monitor is fed the fixture snapshot and a made-up
ten minutes of history, then each page is painted with GSK into a texture.
"""

import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pulse_monitor.ui  # noqa: E402,F401  (pins GTK 4 / Adwaita 1)
from gi.repository import Adw, GLib, Graphene, Gtk  # noqa: E402

from pulse_monitor import i18n  # noqa: E402
from pulse_monitor.model import HistoryPoint, decode_snapshot  # noqa: E402
from pulse_monitor.monitor import LIVE  # noqa: E402
from pulse_monitor.ui.app import PulseApp  # noqa: E402

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "shots")
FIXTURE = Path(__file__).with_name("fixtures") / "snapshot.json"


def fake_history(s):
    points = []
    for i in range(120):
        w = math.sin(i / 9) * 0.5 + math.sin(i / 3.7) * 0.3
        points.append(HistoryPoint(i, max(1, 9 + 7 * w + (14 if 70 < i < 78 else 0)), 7.6 + 0.3 * w,
                                   52 + 3 * w + (6 if 70 < i < 80 else 0),
                                   int(max(0, 2400 + 1800 * w + (60000 if i % 37 < 3 else 0))),
                                   int(max(0, 900 + 600 * w)), 0, 0))
    return points


class ShotApp(PulseApp):
    """PulseApp that hands control to the script instead of showing its window."""
    on_ready = None

    def do_activate(self):
        self.hold()
        self.on_ready()


def snapshot_of(widget, path):
    w, h = widget.get_width(), widget.get_height()
    paintable = Gtk.WidgetPaintable.new(widget)
    snap = Gtk.Snapshot()
    paintable.snapshot(snap, w, h)
    node = snap.to_node()
    renderer = widget.get_native().get_renderer()
    texture = renderer.render_texture(node, Graphene.Rect().init(0, 0, w, h))
    texture.save_to_png(str(path))
    print("wrote", path, w, h)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    shots = []
    for lang in ("en", "tr"):
        for scheme in ("dark", "light"):
            shots.append((lang, scheme))
    state = {"i": 0}

    i18n.set_language("en")
    app = ShotApp()
    app.prefs.tray_icon = False
    app.prefs.address = "macmini-server.taild883a6.ts.net:9123"
    s = decode_snapshot(FIXTURE.read_bytes())
    s.probes = s.probes or []

    def feed():
        m = app.monitor
        m.snapshot = s
        m.connection = LIVE
        m.last_update = time.monotonic() + 3600
        m.latency_ms = 14
        m.history.clear()
        m.history.extend(fake_history(s))
        m._changed()

    def step():
        lang, scheme = shots[state["i"]]
        i18n.set_language(lang)
        Adw.StyleManager.get_default().set_color_scheme(
            Adw.ColorScheme.FORCE_DARK if scheme == "dark" else Adw.ColorScheme.FORCE_LIGHT)
        if app.window:
            app.window.destroy()
            app.window = None
        app.show_window()
        app.monitor.configure = lambda *a: None
        feed()
        GLib.timeout_add(900, lambda: shoot(lang, scheme))
        return False

    def shoot(lang, scheme):
        win = app.window
        suffix = f"{scheme}" + ("" if lang == "en" else "-tr")
        for page in ("overview", "containers", "sites"):
            win.stack.set_visible_child_name(page)
            while GLib.MainContext.default().iteration(False):
                pass
            snapshot_of(win, OUT / f"linux-{page}-{suffix}.png")
        win.stack.set_visible_child_name("overview")
        if lang == "en":
            app.show_preferences()
            GLib.timeout_add(700, lambda: prefs_shot(suffix))
        else:
            advance()
        return False

    def prefs_shot(suffix):
        for page, name in zip(app.preferences.pages, ("general", "server", "tray", "alerts")):
            app.preferences.set_visible_page(page)
            while GLib.MainContext.default().iteration(False):
                pass
            snapshot_of(app.window, OUT / f"linux-prefs-{name}-{suffix}.png")
        app.preferences.close()
        advance()
        return False

    def advance():
        state["i"] += 1
        if state["i"] >= len(shots):
            app.quit()
        else:
            GLib.timeout_add(200, step)

    app.on_ready = lambda: GLib.timeout_add(300, step)
    app.run([])


if __name__ == "__main__":
    main()
