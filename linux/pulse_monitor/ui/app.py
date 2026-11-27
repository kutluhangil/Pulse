"""Adw.Application: window, tray icon, notifications and the update check."""

from __future__ import annotations

import sys
import threading
from pathlib import Path
import time

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from .. import APP_ID, __version__, fmt, updates
from ..config import Preferences, load_token, save_token
from ..i18n import _
from ..levels import container_level, display_name, health_level, sorted_containers
from ..monitor import Monitor
from ..tray import sprites
from ..tray.sni import MenuItem, TrayIcon, separator
from ..wording import alert_text, health_label, status_summary
from .logs import LogsDialog
from .preferences import PreferencesDialog
from .window import PulseWindow

CSS = """
.pulse-chip { padding: 2px 10px; border-radius: 99px; background: alpha(currentColor, 0.08); }
levelbar block.pulse-good { background-color: @success_bg_color; }
levelbar block.pulse-warn { background-color: @warning_bg_color; }
levelbar block.pulse-critical { background-color: @error_bg_color; }
"""
DAY = 24 * 3600
TRAY_FPS = 10


class PulseApp(Adw.Application):
    def __init__(self, background: bool = False):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.prefs = Preferences.load()
        self.monitor = Monitor(self.prefs.alerts)
        self.start_hidden = background
        self.window: PulseWindow | None = None
        self.preferences: PreferencesDialog | None = None
        self.tray: TrayIcon | None = None
        self.new_release: updates.Release | None = None
        self.update_state = ""
        self._phase = 0.0
        self._anim_source = 0
        self._menu_sig = None
        self._held = False

    # Start-up --------------------------------------------------------------

    def do_startup(self):
        Adw.Application.do_startup(self)
        provider = Gtk.CssProvider()
        provider.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        Gtk.IconTheme.get_for_display(Gdk.Display.get_default()).add_search_path(
            str(Path(__file__).resolve().parents[1] / "icons"))
        for name, handler, accels in (
            ("preferences", lambda *_: self.show_preferences(), ["<Control>comma"]),
            ("reconnect", lambda *_: self.monitor.reconnect(), ["<Control>r"]),
            ("copy-summary", lambda *_: self.copy_summary(), ["<Control><Shift>c"]),
            ("ssh", lambda *_: self.open_url(self.prefs.resolved_ssh()), []),
            ("portainer", lambda *_: self.open_url(self.prefs.resolved_portainer()), []),
            ("cockpit", lambda *_: self.open_url(self.prefs.resolved_cockpit()), []),
            ("check-updates", lambda *_: self.check_updates(user=True), []),
            ("download-update", lambda *_: self.download_update(), []),
            ("about", lambda *_: self.show_about(), []),
            ("show", lambda *_: self.show_window(), []),
            ("quit", lambda *_: self.quit_app(), ["<Control>q"]),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)
            if accels:
                self.set_accels_for_action("app." + name, accels)
        url = Gio.SimpleAction.new("open-url", GLib.VariantType.new("s"))
        url.connect("activate", lambda _a, v: self.open_url(v.get_string()))
        self.add_action(url)

        self.monitor.on_alerts = self.on_alerts
        self.monitor.subscribe(self.on_monitor)
        self.monitor.configure(self.prefs.address, load_token())
        self.monitor.start()
        self.apply_tray()
        GLib.timeout_add_seconds(3600, self._daily_check)
        GLib.timeout_add_seconds(20, lambda: (self._daily_check(), False)[1])

    def do_activate(self):
        if self.start_hidden and self.tray_shown:
            self.start_hidden = False
            self._hold(True)
            return
        self.start_hidden = False
        self.show_window()

    # Window ----------------------------------------------------------------

    def show_window(self):
        if self.window is None:
            self.window = PulseWindow(self, self.monitor, self.open_url, self.show_logs, self.show_preferences)
            self.window.connect("close-request", self._on_close)
            self._sync_update_banner()
        self.window.present()

    def _on_close(self, window):
        if self.prefs.run_in_background and self.tray_shown:
            window.set_visible(False)
            self._hold(True)
            return True
        self._hold(False)
        return False

    def _hold(self, on: bool):
        """Keep running with no window while the tray icon is there."""
        if on and not self._held:
            self.hold()
        elif not on and self._held:
            Gio.Application.release(self)
        self._held = on

    def quit_app(self):
        if self.tray:
            self.tray.stop()
        self.quit()

    def show_preferences(self):
        self.show_window()
        self.preferences = PreferencesDialog(self.prefs, self.on_prefs_saved, self.on_server_saved,
                                             lambda: self.check_updates(user=True), self.update_status, self.restart)
        self.preferences.present(self.window)

    def show_logs(self, container):
        if self.monitor.client:
            LogsDialog(self.monitor.client, container).present(self.window)

    def show_about(self):
        self.show_window()
        about = Adw.AboutDialog(
            application_name="Pulse", application_icon=APP_ID, version=__version__, developer_name="Kutluhan Gül",
            website="https://pulse.kutluhangil.dev", issue_url="https://github.com/kutluhangil/Pulse/issues",
            license_type=Gtk.License.GPL_3_0, copyright="© 2026 Kutluhan Gül",
            comments=_("Live monitor for your home server. Free software under GPL-3.0."))
        about.add_credit_section(_("Health score"), ["Mole by tw93 https://github.com/tw93/Mole"])
        about.present(self.window)

    def restart(self):
        argv = [sys.executable, "-m", "pulse_monitor"]
        if self.tray:
            self.tray.stop()
        GLib.spawn_async(argv, flags=GLib.SpawnFlags.SEARCH_PATH)
        self.quit()

    def open_url(self, url: str | None):
        if url:
            Gtk.UriLauncher.new(url).launch(self.window, None, None, None)

    def copy_summary(self):
        s = self.monitor.snapshot
        if s and Gdk.Display.get_default():
            Gdk.Display.get_default().get_clipboard().set(status_summary(s))
            if self.window:
                self.window.toast(_("Status copied"))

    # Preferences -----------------------------------------------------------

    def on_prefs_saved(self):
        self.monitor.set_alert_settings(self.prefs.alerts)
        self.apply_tray()

    def on_server_saved(self, address: str, token: str):
        self.prefs.address = address
        self.prefs.save()
        save_token(token)
        self.monitor.configure(address, token)

    # Monitor ---------------------------------------------------------------

    @property
    def notifications_paused(self) -> bool:
        return self.prefs.notifications_paused_until > time.time()

    def on_alerts(self, events):
        if self.notifications_paused:
            return
        host = self.monitor.snapshot.host.name if self.monitor.snapshot else (self.prefs.host or "Server")
        for e in events:
            title, body = alert_text(e, host)
            n = Gio.Notification.new(title)
            if body:
                n.set_body(body)
            n.set_priority(Gio.NotificationPriority.HIGH if e.fired and e.kind != "reboot" else Gio.NotificationPriority.NORMAL)
            n.set_default_action("app.show")
            self.send_notification(e.key, n)

    def on_monitor(self):
        self._update_tray()

    # Tray ------------------------------------------------------------------

    @property
    def tray_shown(self) -> bool:
        return bool(self.tray and self.tray.available)

    def apply_tray(self):
        if self.prefs.tray_icon and self.tray is None:
            self.tray = TrayIcon("Pulse", self.toggle_window)
            self.tray.on_available = self._tray_available
            try:
                self.tray.start()
            except GLib.Error:
                self.tray = None
        elif not self.prefs.tray_icon and self.tray is not None:
            self.tray.stop()
            self.tray = None
        self._menu_sig = None
        self._update_tray()

    def _tray_available(self, available: bool):
        if not available and self.start_hidden is False and (self.window is None or not self.window.get_visible()):
            self._hold(False)   # no tray to come back from: a closed window means quit
            if self.window is None:
                self.show_window()

    def toggle_window(self):
        if self.window and self.window.get_visible() and self.window.is_active():
            self.window.set_visible(False)
        else:
            self.show_window()

    def _health_key(self) -> str:
        m = self.monitor
        if not m.snapshot or not m.is_live:
            return "offline"
        return ("good", "warn", "critical")[health_level(m.snapshot.health.score)]

    def _update_tray(self):
        if not self.tray:
            return
        m, s = self.monitor, self.monitor.snapshot
        animate = self.prefs.tray_animation != "none" and m.is_live and not _reduced_motion()
        if animate and not self._anim_source:
            self._anim_source = GLib.timeout_add(1000 // TRAY_FPS, self._advance)
        elif not animate and self._anim_source:
            GLib.source_remove(self._anim_source)
            self._anim_source = 0
        if not animate:
            self._draw_icon()
        if s and m.is_live:
            self.tray.set_label(f"{fmt.percent(s.thermal.packageC)}° {fmt.percent(s.cpu.usage)}%" if self.prefs.tray_label else "")
            self.tray.set_tooltip(s.host.name, f"{s.health.score} · {health_label(s.health.score)}")
        else:
            self.tray.set_label("")
            self.tray.set_tooltip("Pulse", m.reason or _("No live data"))
        self._update_menu()

    def _advance(self):
        cpu = self.monitor.snapshot.cpu.usage if (self.monitor.snapshot and self.prefs.animation_follows_load) else 0
        loop = 1.4 - 1.05 * min(max(cpu, 0), 100) / 100
        self._phase = (self._phase + 1 / TRAY_FPS / loop) % 1
        self._draw_icon()
        return GLib.SOURCE_CONTINUE

    def _draw_icon(self):
        kind, health = self.prefs.tray_animation, self._health_key()
        pixmaps = []
        for size in (22, 44):
            surface = sprites.render(kind, self._phase, health, size)
            pixmaps.append((size, size, sprites.argb_bytes(surface)))
        self.tray.set_icon(pixmaps)

    def _update_menu(self):
        m, s = self.monitor, self.monitor.snapshot
        status = (f"{s.host.name} · {s.health.score} {health_label(s.health.score)}" if s and m.is_live
                  else (m.reason or _("Connecting…")))
        containers = tuple((c.name, container_level(c)) for c in sorted_containers(s)) if s else ()
        probes = tuple((p.name, p.ok) for p in s.probes) if s else ()
        sig = (status, containers, probes, self.notifications_paused, self.new_release and self.new_release.tag)
        if sig == self._menu_sig:
            return
        self._menu_sig = sig
        items = []
        if self.new_release:
            items += [MenuItem(_("Update to Pulse {v}…").format(v=self.new_release.version), self.download_update,
                               "software-update-available-symbolic"), separator()]
        items += [MenuItem(status, enabled=False), separator(),
                  MenuItem(_("Open Pulse"), self.show_window, "view-grid-symbolic"),
                  MenuItem(_("Preferences"), self.show_preferences, "preferences-system-symbolic"), separator()]
        for label, url, icon in ((_("SSH into Server"), self.prefs.resolved_ssh(), "utilities-terminal-symbolic"),
                                 ("Portainer", self.prefs.resolved_portainer(), "package-x-generic-symbolic"),
                                 ("Cockpit", self.prefs.resolved_cockpit(), "computer-symbolic")):
            if url:
                items.append(MenuItem(label, lambda u=url: self.open_url(u), icon))
        if s and s.containers:
            marks = {0: "●", 1: "◐", 2: "✕"}
            items.append(MenuItem(_("Container Logs"), icon="text-x-generic-symbolic", children=[
                MenuItem(f"{marks[container_level(c)]}  {display_name(c)}", lambda c=c: self.show_logs(c))
                for c in sorted_containers(s)]))
        if s and s.probes:
            items.append(MenuItem(_("Open Site"), icon="web-browser-symbolic", children=[
                MenuItem(f"{'●' if p.ok else '✕'}  {p.name} · {f'{p.ms} ms' if p.ok else (p.error or 'down')}",
                         lambda u=p.url: self.open_url(u)) for p in s.probes]))
        items += [separator(),
                  MenuItem(_("Copy Status Summary"), self.copy_summary, "edit-copy-symbolic", enabled=bool(s)),
                  MenuItem(_("Reconnect"), self.monitor.reconnect, "view-refresh-symbolic"),
                  MenuItem(_("Pause Notifications"), icon="notifications-disabled-symbolic", children=self._pause_items()),
                  separator(),
                  MenuItem(_("Check for Updates…"), lambda: self.check_updates(user=True)),
                  MenuItem(_("About Pulse"), self.show_about),
                  MenuItem(_("Quit"), self.quit_app, "application-exit-symbolic")]
        self.tray.set_menu(items)

    def _pause_items(self):
        def pause(hours):
            def run():
                self.prefs.notifications_paused_until = time.time() + hours * 3600 if hours else 0.0
                self.prefs.save()
                self._update_menu()
            return run
        items = [MenuItem(_("For 1 Hour"), pause(1)), MenuItem(_("For 8 Hours"), pause(8)),
                 MenuItem(_("For 24 Hours"), pause(24))]
        if self.notifications_paused:
            items += [separator(), MenuItem(_("Resume Now"), pause(0))]
        return items

    # Updates ---------------------------------------------------------------

    def _daily_check(self):
        if self.prefs.auto_check_updates and time.time() - self.prefs.last_update_check >= DAY:
            self.check_updates(user=False)
        return GLib.SOURCE_CONTINUE

    def update_status(self) -> str:
        return self.update_state or _("Pulse {v}").format(v=__version__)

    def check_updates(self, user: bool):
        self.update_state = _("Checking GitHub…")
        if self.preferences:
            self.preferences.refresh_update_status()

        def work():
            try:
                release, error = updates.latest(), None
            except updates.NoRelease:
                release, error = None, None
            except Exception:
                release, error = None, _("Could not reach GitHub")
            GLib.idle_add(self._checked, release, error, user)
        threading.Thread(target=work, daemon=True).start()

    def _checked(self, release, error, user):
        if error is None:
            self.prefs.last_update_check = time.time()
        newer = release if release and updates.is_newer(release) else None
        self.new_release = newer
        if error:
            self.update_state = error
        elif newer:
            self.update_state = _("Pulse {v} is available").format(v=newer.version)
        else:
            self.update_state = _("Pulse {v} is up to date").format(v=__version__)
        if newer and (user or self.prefs.notified_update != newer.tag):
            self.prefs.notified_update = newer.tag
            n = Gio.Notification.new(_("Pulse {v} is available").format(v=newer.version))
            n.set_body(_("Click to download it from GitHub."))
            n.set_default_action_and_target("app.open-url", GLib.Variant("s", newer.download_url or newer.page_url))
            self.send_notification("update", n)
        self.prefs.save()
        if user and self.window and not newer:
            self.window.toast(self.update_state)
        if self.preferences:
            self.preferences.refresh_update_status()
        self._sync_update_banner()
        self._menu_sig = None
        if self.tray:
            self._update_menu()
        return GLib.SOURCE_REMOVE

    def _sync_update_banner(self):
        if self.window:
            r = self.new_release
            self.window.update_banner.set_title(_("Pulse {v} is available").format(v=r.version) if r else "")
            self.window.update_banner.set_revealed(r is not None)

    def download_update(self):
        if self.new_release:
            self.open_url(self.new_release.download_url or self.new_release.page_url)


def _reduced_motion() -> bool:
    settings = Gtk.Settings.get_default()
    return bool(settings and not settings.get_property("gtk-enable-animations"))


def configure_from_cli(address: str) -> int:
    """`pulse-monitor --configure ADDRESS < token`: token on stdin, never in argv."""
    token = sys.stdin.read().strip()
    prefs = Preferences.load()
    prefs.address = address
    prefs.save()
    if token:
        where = save_token(token)
        print(f"Pulse configured for {address} (token in {where})")
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv if argv is None else argv)
    if "--version" in argv:
        print(__version__)
        return 0
    if "--configure" in argv:
        i = argv.index("--configure")
        if i + 1 >= len(argv):
            print("usage: pulse-monitor --configure <address> < token", file=sys.stderr)
            return 64
        return configure_from_cli(argv[i + 1])
    background = "--background" in argv
    from ..i18n import set_language
    set_language(Preferences.load().language)
    app = PulseApp(background=background)
    return app.run([argv[0]])

