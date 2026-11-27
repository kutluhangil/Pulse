"""Main window: Overview, Containers and Sites pages in an Adw.ViewStack."""

from __future__ import annotations

from collections.abc import Callable
from itertools import groupby

from gi.repository import Adw, Gio, GLib, Gtk, Pango

from .. import fmt
from ..i18n import _
from ..levels import (activity, container_level, container_status, cpu_level, disk_level, display_name,
                      health_level, mem_level, running_count, sorted_containers, temp_level)
from ..model import Snapshot
from ..monitor import CONNECTING, NOT_CONFIGURED, UNAUTHORIZED, Monitor
from ..wording import (activity_text, container_state_text, health_label, memory_word, reason_text,
                       temperature_word)
from .widgets import LEVEL_COLOR, Dot, ResourceRow, ScoreRing, Sparkline, level_bar, numeric


def _group(title: str = "", description: str = "") -> tuple[Gtk.Box, Gtk.ListBox]:
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    if title:
        heading = Gtk.Label(label=title, xalign=0, margin_start=6)
        heading.add_css_class("heading")
        box.append(heading)
    if description:
        sub = Gtk.Label(label=description, xalign=0, margin_start=6, wrap=True)
        sub.add_css_class("dim-label")
        sub.add_css_class("caption")
        box.append(sub)
    lst = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    lst.add_css_class("boxed-list")
    box.append(lst)
    return box, lst


def _image(image: str) -> str:
    """Locally built images show up as a bare digest; keep it short."""
    return image[:19] if image.startswith("sha256:") else image


def _page(child: Gtk.Widget) -> Gtk.ScrolledWindow:
    clamp = Adw.Clamp(maximum_size=620, tightening_threshold=480, child=child,
                      margin_top=18, margin_bottom=24, margin_start=12, margin_end=12)
    return Gtk.ScrolledWindow(child=clamp, hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)


class PulseWindow(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application, monitor: Monitor, open_url: Callable[[str], None],
                 show_logs: Callable, open_preferences: Callable[[], None]):
        super().__init__(application=app, title="Pulse", default_width=480, default_height=860)
        self.set_size_request(360, 480)
        self.monitor = monitor
        self.open_url = open_url
        self.show_logs = show_logs
        self.open_preferences = open_preferences
        self._container_sig = None
        self._probe_sig = None

        self.stack = Adw.ViewStack(vexpand=True)
        self.stack.add_titled_with_icon(self._overview(), "overview", _("Overview"), "pulse-overview-symbolic")
        self.stack.add_titled_with_icon(self._containers(), "containers", _("Containers"), "package-x-generic-symbolic")
        self.stack.add_titled_with_icon(self._sites(), "sites", _("Sites"), "network-workgroup-symbolic")

        header = Adw.HeaderBar()
        switcher = Adw.ViewSwitcher(stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)
        menu_button = Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=self._menu(),
                                     tooltip_text=_("Main Menu"), primary=True)
        header.pack_end(menu_button)
        refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text=_("Reconnect"),
                             action_name="app.reconnect")
        header.pack_start(refresh)
        bottom = Adw.ViewSwitcherBar(stack=self.stack)

        self.offline_banner = Adw.Banner(button_label=_("Reconnect"), action_name="app.reconnect")
        self.update_banner = Adw.Banner(button_label=_("Download"), action_name="app.download-update")

        self.empty = Adw.StatusPage(icon_name="network-server-symbolic", vexpand=True)
        empty_button = Gtk.Button(label=_("Open Preferences"), halign=Gtk.Align.CENTER, action_name="app.preferences")
        empty_button.add_css_class("pill")
        empty_button.add_css_class("suggested-action")
        self.empty.set_child(empty_button)
        self.empty_button = empty_button

        self.content = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.content.add_named(self.stack, "data")
        self.content.add_named(self.empty, "empty")

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.append(self.update_banner)
        body.append(self.offline_banner)
        body.append(self.content)

        self.toasts = Adw.ToastOverlay(child=body)
        view = Adw.ToolbarView(content=self.toasts)
        view.add_top_bar(header)
        view.add_bottom_bar(bottom)
        self.set_content(view)

        bp = Adw.Breakpoint.new(Adw.BreakpointCondition.parse("max-width: 540sp"))
        bp.add_setter(header, "title-widget", Adw.WindowTitle(title="Pulse"))
        bp.add_setter(bottom, "reveal", True)
        self.add_breakpoint(bp)

        monitor.subscribe(self.refresh)
        self.refresh()

    # Menu ------------------------------------------------------------------

    @staticmethod
    def _menu() -> Gio.Menu:
        menu = Gio.Menu()
        first = Gio.Menu()
        first.append(_("Copy Status Summary"), "app.copy-summary")
        first.append(_("Reconnect"), "app.reconnect")
        menu.append_section(None, first)
        tools = Gio.Menu()
        tools.append(_("SSH into Server"), "app.ssh")
        tools.append("Portainer", "app.portainer")
        tools.append("Cockpit", "app.cockpit")
        menu.append_section(None, tools)
        last = Gio.Menu()
        last.append(_("Preferences"), "app.preferences")
        last.append(_("Check for Updates…"), "app.check-updates")
        last.append(_("About Pulse"), "app.about")
        last.append(_("Quit"), "app.quit")
        menu.append_section(None, last)
        return menu

    # Overview --------------------------------------------------------------

    def _overview(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)

        hero = Gtk.Box(spacing=18, margin_top=6)
        self.ring = ScoreRing()
        hero.append(self.ring)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER, hexpand=True)
        self.host_label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.host_label.add_css_class("title-2")
        self.health_label = Gtk.Label(xalign=0)
        self.health_label.add_css_class("heading")
        self.reasons_label = Gtk.Label(xalign=0, wrap=True)
        self.reasons_label.add_css_class("dim-label")
        self.chips = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=8,
                                 column_spacing=6, row_spacing=6, margin_top=6)
        for widget in (self.host_label, self.health_label, self.reasons_label, self.chips):
            info.append(widget)
        hero.append(info)
        page.append(hero)

        group, lst = _group(_("Resources"))
        self.cpu_graph = Sparkline("blue")
        self.cpu_row = ResourceRow("pulse-cpu-symbolic", _("Processor"), self.cpu_graph)
        self.temp_graph = Sparkline("orange", ceiling=None)
        self.temp_row = ResourceRow("pulse-temperature-symbolic", _("Temperature"), self.temp_graph)
        self.mem_graph = Sparkline("purple")
        self.mem_row = ResourceRow("pulse-memory-symbolic", _("Memory"), self.mem_graph)
        self.disk_bar = level_bar(0)
        for name in ("low", "high", "full"):
            self.disk_bar.remove_offset_value(name)
        self.disk_bar.add_offset_value("pulse-good", 0.80)
        self.disk_bar.add_offset_value("pulse-warn", 0.93)
        self.disk_bar.add_offset_value("pulse-critical", 1.0)
        self.disk_row = ResourceRow("drive-harddisk-symbolic", _("Storage"), self.disk_bar)
        self.net_graph = Sparkline("green", ceiling=None)
        self.net_row = ResourceRow("network-transmit-receive-symbolic", _("Network"), self.net_graph)
        self.fan_bar = level_bar(0)
        self.fan_row = ResourceRow("weather-windy-symbolic", _("Fan"), self.fan_bar)
        for row in (self.cpu_row, self.temp_row, self.mem_row, self.disk_row, self.net_row, self.fan_row):
            lst.append(row)
        page.append(group)

        group, lst = _group(_("System"))
        self.updates_row = Adw.ActionRow(title=_("Software updates"))
        self.updates_row.add_prefix(Gtk.Image.new_from_icon_name("software-update-available-symbolic"))
        self.reboot_row = Adw.ActionRow(title=_("Restart required"),
                                        subtitle=_("Installed updates take effect after a reboot."))
        self.reboot_row.add_prefix(Gtk.Image.new_from_icon_name("system-reboot-symbolic"))
        self.docker_row = Adw.ActionRow(title="Docker")
        self.docker_row.add_prefix(Gtk.Image.new_from_icon_name("package-x-generic-symbolic"))
        self.agent_row = Adw.ActionRow(title=_("Pulse agent"))
        self.agent_row.add_prefix(Gtk.Image.new_from_icon_name("network-server-symbolic"))
        self.latency_label = numeric(Gtk.Label())
        self.latency_label.add_css_class("dim-label")
        self.agent_row.add_suffix(self.latency_label)
        for row in (self.updates_row, self.reboot_row, self.docker_row, self.agent_row):
            lst.append(row)
        page.append(group)
        return _page(page)

    def _chip(self, text: str) -> Gtk.Widget:
        label = Gtk.Label(label=text)
        label.add_css_class("pulse-chip")
        label.add_css_class("caption")
        return label

    # Containers ------------------------------------------------------------

    def _containers(self) -> Gtk.Widget:
        self.containers_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self.containers_summary = Gtk.Label(xalign=0, margin_start=6)
        self.containers_summary.add_css_class("dim-label")
        wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        wrap.append(self.containers_summary)
        wrap.append(self.containers_box)
        self.containers_empty = Adw.StatusPage(icon_name="package-x-generic-symbolic", title=_("No containers"),
                                               vexpand=True)
        stack = Gtk.Stack()
        stack.add_named(_page(wrap), "list")
        stack.add_named(self.containers_empty, "empty")
        self.containers_stack = stack
        return stack

    def _fill_containers(self, s: Snapshot) -> None:
        sig = tuple((c.id, c.state, c.health, c.statusText) for c in s.containers)
        if sig == self._container_sig:
            for row, c in self._container_rows:
                row.usage.set_label(f"{fmt.number(c.cpu, 1)} % · {fmt.bytes_(c.memBytes)}")
            return
        self._container_sig = sig
        child = self.containers_box.get_first_child()
        while child:
            self.containers_box.remove(child)
            child = self.containers_box.get_first_child()
        self._container_rows = []
        ordered = sorted(sorted_containers(s), key=lambda c: c.project or "~")
        for project, items in groupby(ordered, key=lambda c: c.project):
            group, lst = _group(project or _("Standalone"))
            lst.connect("row-activated", lambda _l, row: self.show_logs(row.container))
            for c in sorted(items, key=lambda c: (-container_level(c), -c.cpu, c.name)):
                row = Adw.ActionRow(title=GLib.markup_escape_text(display_name(c)), activatable=True,
                                    subtitle=GLib.markup_escape_text(f"{_image(c.image)} · {c.statusText}"),
                                    subtitle_lines=1, tooltip_text=_("Show logs"))
                row.container = c
                status = container_status(c)
                row.add_prefix(Dot(LEVEL_COLOR[container_level(c)]))
                state = Gtk.Label(label=container_state_text(status))
                state.add_css_class("caption")
                state.add_css_class(container_level(c).css if status != "running" else "dim-label")
                row.usage = numeric(Gtk.Label(label=f"{fmt.number(c.cpu, 1)} % · {fmt.bytes_(c.memBytes)}"))
                row.usage.add_css_class("dim-label")
                row.usage.add_css_class("caption")
                right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
                right.append(state)
                right.append(row.usage)
                state.set_xalign(1)
                row.usage.set_xalign(1)
                row.add_suffix(right)
                row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
                lst.append(row)
                self._container_rows.append((row, c))
            self.containers_box.append(group)

    # Sites -----------------------------------------------------------------

    def _sites(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        group, self.sites_list = _group(_("Sites"), _("Checked by the agent every minute"))
        self.sites_list.connect("row-activated", lambda _l, row: self.open_url(row.url))
        box.append(group)
        self.sites_empty = Adw.StatusPage(icon_name="network-workgroup-symbolic", title=_("No sites"),
                                          description=_("Add sites with PULSE_PROBES on the server"), vexpand=True)
        stack = Gtk.Stack()
        stack.add_named(_page(box), "list")
        stack.add_named(self.sites_empty, "empty")
        self.sites_stack = stack
        return stack

    def _fill_sites(self, s: Snapshot) -> None:
        sig = tuple((p.name, p.ok, p.ms, p.error) for p in s.probes)
        if sig == self._probe_sig:
            return
        self._probe_sig = sig
        self.sites_list.remove_all()
        for p in s.probes:
            row = Adw.ActionRow(title=GLib.markup_escape_text(p.name), subtitle=GLib.markup_escape_text(p.url),
                                activatable=True, tooltip_text=_("Open in browser"))
            row.url = p.url
            row.add_prefix(Dot("green" if p.ok else ("red" if p.checked else "gray")))
            value = numeric(Gtk.Label(label=f"{p.ms} ms" if p.ok else (p.error or _("down"))))
            value.add_css_class("dim-label" if p.ok else "error")
            row.add_suffix(value)
            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
            self.sites_list.append(row)

    # Refresh ---------------------------------------------------------------

    def refresh(self) -> None:
        m = self.monitor
        s = m.snapshot
        self.offline_banner.set_revealed(bool(s) and not m.is_live and m.connection != CONNECTING)
        self.offline_banner.set_title(m.reason or _("No live data"))
        if s is None:
            self.content.set_visible_child_name("empty")
            if m.connection == NOT_CONFIGURED:
                self.empty.set_title(_("Connect to your server"))
                self.empty.set_description(_("Enter the agent address and token in Preferences."))
                self.empty_button.set_visible(True)
            elif m.connection == UNAUTHORIZED:
                self.empty.set_title(_("Token rejected"))
                self.empty.set_description(_("Copy the token again with deploy/deploy.sh --copy-token."))
                self.empty_button.set_visible(True)
            elif m.connection == CONNECTING:
                self.empty.set_title(_("Connecting…"))
                self.empty.set_description(GLib.markup_escape_text(m.client.base or "") if m.client else "")
                self.empty_button.set_visible(False)
            else:
                self.empty.set_title(_("Server unreachable"))
                self.empty.set_description(GLib.markup_escape_text(m.reason))
                self.empty_button.set_visible(False)
            return
        self.content.set_visible_child_name("data")
        self._fill_overview(s)
        self.containers_stack.set_visible_child_name("list" if s.containers else "empty")
        self.containers_summary.set_label(_("{running} of {total} running").format(
            running=running_count(s), total=len(s.containers)))
        self._fill_containers(s)
        self.sites_stack.set_visible_child_name("list" if s.probes else "empty")
        self._fill_sites(s)

    def _fill_overview(self, s: Snapshot) -> None:
        m = self.monitor
        live = m.is_live
        level = health_level(s.health.score)
        self.ring.update(s.health.score, LEVEL_COLOR[level] if live else "gray")
        self.host_label.set_label(s.host.name)
        self.health_label.set_label(health_label(s.health.score))
        for css in ("success", "warning", "error"):
            self.health_label.remove_css_class(css)
        self.health_label.add_css_class(level.css)
        reasons = " · ".join(reason_text(r) for r in s.health.reasons)
        self.reasons_label.set_label(reasons)
        self.reasons_label.set_visible(bool(reasons))
        self.chips.remove_all()
        for text in (fmt.short_os(s.host.os), fmt.short_cpu(s.host.cpuModel), fmt.ram_size(s.host.memTotal),
                     fmt.uptime(s.host.uptimeSec)):
            self.chips.append(self._chip(text))

        hist = list(m.history)[-120:]
        cpu = s.cpu.usage
        load = " ".join(f"{x:.2f}" for x in s.cpu.load[:3])
        self.cpu_row.show(f"{fmt.percent(cpu)} %", _("{state} · {threads} threads · load {load}").format(
            state=activity_text(activity(cpu)), threads=s.host.threads, load=load), cpu_level(cpu))
        self.cpu_graph.update([p.cpu for p in hist])

        t = s.thermal.packageC
        cores = " ".join(f"{c:.0f}" for c in s.thermal.coresC)
        self.temp_row.show(f"{fmt.percent(t)} °C", f"{temperature_word(temp_level(t))} · {_('cores')} {cores}",
                           temp_level(t))
        self.temp_graph.update([p.temp for p in hist])

        mem = s.mem.used_percent
        swap = f" · swap {fmt.bytes_(s.mem.swapUsed)}" if s.mem.swapUsed else ""
        self.mem_row.show(f"{fmt.percent(mem)} %", _("{word} · {used} of {total}").format(
            word=memory_word(mem_level(mem)), used=fmt.bytes_(s.mem.used), total=fmt.bytes_(s.mem.total)) + swap,
            mem_level(mem))
        self.mem_graph.update([p.mem for p in hist])

        if s.disks:
            d = s.disks[0]
            self.disk_row.show(f"{fmt.percent(d.used_percent)} %", _("{free} free · read {r} · write {w}").format(
                free=fmt.bytes_(d.free), r=fmt.rate(d.readBps), w=fmt.rate(d.writeBps)), disk_level(d.used_percent))
            level_bar(d.used_percent / 100, self.disk_bar)
        self.disk_row.set_visible(bool(s.disks))

        n = s.net
        speed = f" · {n.speedMbps // 1000} Gb/s" if n.speedMbps >= 1000 else (f" · {n.speedMbps} Mb/s" if n.speedMbps else "")
        self.net_row.show(f"↓ {fmt.rate(n.rxBps)}", f"{n.iface}{speed} · ↑ {fmt.rate(n.txBps)}")
        self.net_graph.update([p.rx for p in hist], [p.tx for p in hist], colors=["green", "blue"])

        if s.fan:
            f = s.fan
            mode = _("Idle") if f.rpm <= f.min else _("Auto")
            self.fan_row.show(f"{fmt.number(f.rpm, 0)} rpm", f"{f.label} · {mode} · {fmt.percent(f.speed_fraction * 100)} %")
            level_bar(f.speed_fraction, self.fan_bar)
        self.fan_row.set_visible(s.fan is not None)

        u = s.system
        if u.aptUpdates:
            self.updates_row.set_subtitle(_("{n} packages, {sec} security").format(n=u.aptUpdates, sec=u.securityUpdates))
        else:
            self.updates_row.set_subtitle(_("Up to date"))
        self.reboot_row.set_visible(u.rebootRequired)
        dk = s.docker
        self.docker_row.set_subtitle(
            _("Engine {v} · {running} running").format(v=dk.version, running=running_count(s)) if dk.available
            else GLib.markup_escape_text(dk.error or _("Docker unreachable")))
        self.agent_row.set_subtitle(_("Version {v} · {kernel}").format(v=s.host.agentVersion, kernel=s.host.kernel))
        self.latency_label.set_label(f"{m.latency_ms:.0f} ms" if m.latency_ms is not None and live else "")

    def toast(self, text: str) -> None:
        self.toasts.add_toast(Adw.Toast(title=text, timeout=3))

