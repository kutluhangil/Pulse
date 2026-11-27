"""Preferences: General, Server, Tray and Alerts pages (Adw.PreferencesDialog)."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable

from gi.repository import Adw, GLib, Gtk

from .. import autostart
from ..client import AgentClient, base_url, describe
from ..config import Preferences, load_token
from ..i18n import _

LANGUAGES = [("system", "Follow system"), ("en", "English"), ("tr", "Türkçe")]
ANIMATIONS = [("server", "Hopping server"), ("cat", "Running cat"), ("pulse", "Heartbeat"), ("none", "Still icon")]
PAUSES = [(0, "Off"), (1, "1 hour"), (8, "8 hours"), (24, "24 hours")]


def _combo(title: str, subtitle: str, options: list[tuple], current, on_change: Callable) -> Adw.ComboRow:
    labels = Gtk.StringList()
    for _value, label in options:
        labels.append(_(label) if label not in ("English", "Türkçe") else label)
    row = Adw.ComboRow(title=title, subtitle=subtitle, model=labels)
    values = [v for v, _l in options]
    row.set_selected(values.index(current) if current in values else 0)
    row.connect("notify::selected", lambda r, _p: on_change(values[r.get_selected()]))
    return row


def _switch(title: str, subtitle: str, active: bool, on_change: Callable[[bool], None]) -> Adw.SwitchRow:
    row = Adw.SwitchRow(title=title, subtitle=subtitle, active=active)
    row.connect("notify::active", lambda r, _p: on_change(r.get_active()))
    return row


def _spin(title: str, subtitle: str, value: float, lo: float, hi: float, on_change: Callable[[float], None]) -> Adw.SpinRow:
    row = Adw.SpinRow.new_with_range(lo, hi, 1)
    row.set_title(title)
    row.set_subtitle(subtitle)
    row.set_value(value)
    row.connect("notify::value", lambda r, _p: on_change(r.get_value()))
    return row


class PreferencesDialog(Adw.PreferencesDialog):
    def __init__(self, prefs: Preferences, on_saved: Callable[[], None], on_server: Callable[[str, str], None],
                 check_updates: Callable[[], None], update_status: Callable[[], str], restart: Callable[[], None]):
        super().__init__(search_enabled=False)
        self.prefs = prefs
        self.on_saved = on_saved
        self.on_server = on_server
        self.restart = restart
        self._language_at_open = prefs.language
        self.pages = [self._general(check_updates, update_status), self._server(), self._tray(), self._alerts()]
        for page in self.pages:
            self.add(page)

    def _set(self, name: str, value) -> None:
        setattr(self.prefs, name, value)
        self.prefs.save()
        self.on_saved()

    # General ---------------------------------------------------------------

    def _general(self, check_updates, update_status) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage(title=_("General"), icon_name="preferences-system-symbolic")
        group = Adw.PreferencesGroup(title=_("Behaviour"))
        group.add(_switch(_("Launch at login"), _("Pulse starts in the background when you log in"),
                          autostart.enabled(), autostart.set_enabled))
        group.add(_switch(_("Keep running in the background"), _("Closing the window leaves Pulse in the tray"),
                          self.prefs.run_in_background, lambda v: self._set("run_in_background", v)))
        self.restart_button = Gtk.Button(label=_("Restart"), valign=Gtk.Align.CENTER, visible=False)
        self.restart_button.add_css_class("suggested-action")
        self.restart_button.connect("clicked", lambda _b: self.restart())
        language = _combo(_("Language"), _("Restart Pulse after changing"), LANGUAGES, self.prefs.language,
                          self._language_changed)
        language.add_suffix(self.restart_button)
        group.add(language)
        page.add(group)

        group = Adw.PreferencesGroup(title=_("Updates"))
        group.add(_switch(_("Check for updates automatically"), _("Looks for a new release on GitHub once a day"),
                          self.prefs.auto_check_updates, lambda v: self._set("auto_check_updates", v)))
        self.update_row = Adw.ActionRow(title=_("Pulse version"), subtitle=update_status())
        button = Gtk.Button(label=_("Check Now"), valign=Gtk.Align.CENTER)
        button.connect("clicked", lambda _b: check_updates())
        self.update_row.add_suffix(button)
        group.add(self.update_row)
        page.add(group)
        self._update_status = update_status
        return page

    def refresh_update_status(self) -> None:
        self.update_row.set_subtitle(self._update_status())

    def _language_changed(self, value: str) -> None:
        self._set("language", value)
        self.restart_button.set_visible(value != self._language_at_open)

    # Server ----------------------------------------------------------------

    def _server(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage(title=_("Server"), icon_name="network-server-symbolic")
        group = Adw.PreferencesGroup(title=_("Agent"), description=_(
            "The address tailscale serve gives the agent, and the token from deploy/.env on your computer."))
        self.address = Adw.EntryRow(title=_("Address"), text=self.prefs.address, show_apply_button=False)
        self.address.set_input_purpose(Gtk.InputPurpose.URL)
        self.token = Adw.PasswordEntryRow(title=_("Token"), text=load_token())
        group.add(self.address)
        group.add(self.token)
        self.test_row = Adw.ActionRow(title=_("Connection"), subtitle=_("Not tested"))
        test = Gtk.Button(label=_("Test"), valign=Gtk.Align.CENTER)
        test.connect("clicked", lambda _b: self._test())
        save = Gtk.Button(label=_("Save"), valign=Gtk.Align.CENTER)
        save.add_css_class("suggested-action")
        save.connect("clicked", lambda _b: self._save_server())
        self.test_row.add_suffix(test)
        self.test_row.add_suffix(save)
        group.add(self.test_row)
        page.add(group)

        group = Adw.PreferencesGroup(title=_("Shortcuts"), description=_("Leave empty to use the agent's host name"))
        for title, attr, hint in ((_("SSH target"), "ssh_target", "user@host"),
                                  ("Portainer", "portainer_url", "https://host:9443"),
                                  ("Cockpit", "cockpit_url", "https://host:9090")):
            row = Adw.EntryRow(title=f"{title} ({hint})", text=getattr(self.prefs, attr))
            row.connect("changed", lambda r, a=attr: self._set(a, r.get_text().strip()))
            group.add(row)
        page.add(group)
        return page

    def _test(self) -> None:
        address, token = self.address.get_text().strip(), self.token.get_text().strip()
        if not base_url(address) or not token:
            self.test_row.set_subtitle(_("Enter an address and a token"))
            return
        self.test_row.set_subtitle(_("Testing…"))

        def work():
            client = AgentClient(address, token)
            try:
                start = time.monotonic()
                snap = client.snapshot()
                text = _("Connected to {host} in {ms} ms").format(host=snap.host.name,
                                                                  ms=int((time.monotonic() - start) * 1000))
            except Exception as e:
                text = describe(e)
            GLib.idle_add(lambda: (self.test_row.set_subtitle(GLib.markup_escape_text(text)), False)[1])
        threading.Thread(target=work, daemon=True).start()

    def _save_server(self) -> None:
        address, token = self.address.get_text().strip(), self.token.get_text().strip()
        if not base_url(address) or not token:
            self.test_row.set_subtitle(_("Enter an address and a token"))
            return
        self.on_server(address, token)
        self.test_row.set_subtitle(_("Saved"))

    # Tray ------------------------------------------------------------------

    def _tray(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage(title=_("Tray"), icon_name="view-grid-symbolic")
        group = Adw.PreferencesGroup(title=_("Tray icon"), description=_(
            "Shown by KDE Plasma and by Ubuntu's AppIndicator extension. Elsewhere Pulse runs as a normal window."))
        group.add(_switch(_("Show tray icon"), "", self.prefs.tray_icon, lambda v: self._set("tray_icon", v)))
        group.add(_combo(_("Animated icon"), _("LEDs and heartbeat take the health colour"), ANIMATIONS,
                         self.prefs.tray_animation, lambda v: self._set("tray_animation", v)))
        group.add(_switch(_("Speed follows CPU load"), _("The busier the server, the faster it runs"),
                          self.prefs.animation_follows_load, lambda v: self._set("animation_follows_load", v)))
        group.add(_switch(_("Show temperature and CPU"), _("Text next to the icon, where the tray supports it"),
                          self.prefs.tray_label, lambda v: self._set("tray_label", v)))
        page.add(group)
        return page

    # Alerts ----------------------------------------------------------------

    def _alerts(self) -> Adw.PreferencesPage:
        a = self.prefs.alerts
        page = Adw.PreferencesPage(title=_("Alerts"), icon_name="preferences-system-notifications-symbolic")

        def alert(name):
            return lambda v: self._set_alert(name, v)

        group = Adw.PreferencesGroup(title=_("Notifications"))
        group.add(_switch(_("Alerts"), _("Desktop notifications when something needs attention"), a.enabled,
                          alert("enabled")))
        paused = max(0.0, self.prefs.notifications_paused_until - time.time()) / 3600
        current = next((h for h in (1, 8, 24) if paused and h >= paused - 0.01), 0)
        group.add(_combo(_("Pause notifications"), _("The window keeps updating"), PAUSES, current,
                         lambda h: self._set("notifications_paused_until", time.time() + h * 3600 if h else 0.0)))
        page.add(group)

        group = Adw.PreferencesGroup(title=_("Thresholds"))
        group.add(_spin(_("Temperature"), _("°C, held for 30 seconds"), a.hotC, 60, 100, alert("hotC")))
        group.add(_spin(_("Memory"), _("% used, held for a minute"), a.memoryPct, 50, 99, alert("memoryPct")))
        group.add(_spin(_("Disk"), _("% used"), a.diskPct, 50, 99, alert("diskPct")))
        page.add(group)

        group = Adw.PreferencesGroup(title=_("Watch"))
        group.add(_switch(_("Containers"), _("Stopped, crashed or unhealthy"), a.containers, alert("containers")))
        group.add(_switch(_("Sites"), _("Two failed checks in a row"), a.probes, alert("probes")))
        group.add(_switch(_("Server offline"), _("No data for over a minute"), a.offline, alert("offline")))
        group.add(_switch(_("Restart required"), _("After updates that need a reboot"), a.reboot, alert("reboot")))
        page.add(group)
        return page

    def _set_alert(self, name: str, value) -> None:
        setattr(self.prefs.alerts, name, value)
        self.prefs.save()
        self.on_saved()
