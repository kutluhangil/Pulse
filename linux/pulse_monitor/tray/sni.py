"""Tray icon over D-Bus: org.kde.StatusNotifierItem plus com.canonical.dbusmenu.

GTK 4 has no tray API and libayatana-appindicator needs GTK 3, so Pulse speaks
the two protocols itself. Shown by KDE Plasma, by Ubuntu's AppIndicator
extension (on by default) and by GNOME with the AppIndicator extension.
"""

from __future__ import annotations

import os
from collections.abc import Callable
from dataclasses import dataclass, field

from gi.repository import Gio, GLib

ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"
WATCHER = "org.kde.StatusNotifierWatcher"

ITEM_XML = """
<node><interface name="org.kde.StatusNotifierItem">
  <property name="Category" type="s" access="read"/>
  <property name="Id" type="s" access="read"/>
  <property name="Title" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="WindowId" type="i" access="read"/>
  <property name="IconName" type="s" access="read"/>
  <property name="IconPixmap" type="a(iiay)" access="read"/>
  <property name="OverlayIconName" type="s" access="read"/>
  <property name="AttentionIconName" type="s" access="read"/>
  <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
  <property name="ItemIsMenu" type="b" access="read"/>
  <property name="Menu" type="o" access="read"/>
  <property name="XAyatanaLabel" type="s" access="read"/>
  <property name="XAyatanaLabelGuide" type="s" access="read"/>
  <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
  <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
  <signal name="NewIcon"/>
  <signal name="NewTitle"/>
  <signal name="NewToolTip"/>
  <signal name="NewStatus"><arg type="s"/></signal>
  <signal name="XAyatanaNewLabel"><arg type="s"/><arg type="s"/></signal>
</interface></node>"""

MENU_XML = """
<node><interface name="com.canonical.dbusmenu">
  <property name="Version" type="u" access="read"/>
  <property name="TextDirection" type="s" access="read"/>
  <property name="Status" type="s" access="read"/>
  <property name="IconThemePath" type="as" access="read"/>
  <method name="GetLayout">
    <arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
    <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/>
  </method>
  <method name="GetGroupProperties">
    <arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/>
  </method>
  <method name="GetProperty">
    <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/>
  </method>
  <method name="Event">
    <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/>
  </method>
  <method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
  <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
  <method name="AboutToShowGroup">
    <arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/>
  </method>
  <signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})"/><arg type="a(ias)"/></signal>
  <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  <signal name="ItemActivationRequested"><arg type="i"/><arg type="u"/></signal>
</interface></node>"""


@dataclass
class MenuItem:
    label: str = ""
    action: Callable[[], None] | None = None
    icon: str = ""
    enabled: bool = True
    separator: bool = False
    children: list[MenuItem] = field(default_factory=list)


def separator() -> MenuItem:
    return MenuItem(separator=True)


class TrayIcon:
    """One status item; `available` turns True once a tray host accepted it."""

    def __init__(self, title: str, on_activate: Callable[[], None]):
        self.title = title
        self.on_activate = on_activate
        self.available = False
        self.on_available: Callable[[bool], None] | None = None
        self._pixmaps: list[tuple[int, int, bytes]] = []
        self._tooltip = ("", "")
        self._label = ""
        self._menu: list[MenuItem] = []
        self._ids: dict[int, MenuItem] = {}
        self._revision = 1
        self._bus: Gio.DBusConnection | None = None
        self._regs: list[int] = []
        self._name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
        self._owner_id = 0
        self._watch_id = 0

    # Lifecycle -------------------------------------------------------------

    def start(self) -> None:
        self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        item = Gio.DBusNodeInfo.new_for_xml(ITEM_XML).interfaces[0]
        menu = Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0]
        self._regs.append(self._bus.register_object(ITEM_PATH, item, self._item_call, self._item_get, None))
        self._regs.append(self._bus.register_object(MENU_PATH, menu, self._menu_call, self._menu_get, None))
        self._owner_id = Gio.bus_own_name_on_connection(self._bus, self._name, Gio.BusNameOwnerFlags.NONE, None, None)
        self._watch_id = Gio.bus_watch_name_on_connection(
            self._bus, WATCHER, Gio.BusNameWatcherFlags.NONE, self._watcher_appeared, self._watcher_vanished)

    def stop(self) -> None:
        if not self._bus:
            return
        for reg in self._regs:
            self._bus.unregister_object(reg)
        self._regs.clear()
        if self._watch_id:
            Gio.bus_unwatch_name(self._watch_id)
        if self._owner_id:
            Gio.bus_unown_name(self._owner_id)
        self._bus = None
        self._set_available(False)

    def _watcher_appeared(self, bus, _name, _owner):
        bus.call(WATCHER, "/StatusNotifierWatcher", WATCHER, "RegisterStatusNotifierItem",
                 GLib.Variant("(s)", (self._name,)), None, Gio.DBusCallFlags.NONE, 3000, None,
                 lambda b, res: self._registered(b, res))

    def _registered(self, bus, result):
        try:
            bus.call_finish(result)
            self._set_available(True)
        except GLib.Error:
            self._set_available(False)

    def _watcher_vanished(self, _bus, _name):
        self._set_available(False)

    def _set_available(self, value: bool) -> None:
        if value != self.available:
            self.available = value
            if self.on_available:
                self.on_available(value)

    # Updates ---------------------------------------------------------------

    def set_icon(self, pixmaps: list[tuple[int, int, bytes]]) -> None:
        self._pixmaps = pixmaps
        self._emit(ITEM_PATH, "org.kde.StatusNotifierItem", "NewIcon", None)

    def set_tooltip(self, title: str, body: str) -> None:
        if (title, body) != self._tooltip:
            self._tooltip = (title, body)
            self._emit(ITEM_PATH, "org.kde.StatusNotifierItem", "NewToolTip", None)

    def set_label(self, text: str) -> None:
        if text != self._label:
            self._label = text
            self._emit(ITEM_PATH, "org.kde.StatusNotifierItem", "XAyatanaNewLabel", GLib.Variant("(ss)", (text, "")))

    def set_menu(self, items: list[MenuItem]) -> None:
        self._menu = items
        self._ids = {}
        self._assign(items, [1])
        self._revision += 1
        self._emit(MENU_PATH, "com.canonical.dbusmenu", "LayoutUpdated", GLib.Variant("(ui)", (self._revision, 0)))

    def _assign(self, items, counter):
        for it in items:
            it._id = counter[0]
            self._ids[counter[0]] = it
            counter[0] += 1
            self._assign(it.children, counter)

    def _emit(self, path, iface, signal, params):
        if self._bus:
            self._bus.emit_signal(None, path, iface, signal, params)

    # org.kde.StatusNotifierItem ----------------------------------------------

    def _item_get(self, _bus, _sender, _path, _iface, prop):
        return {
            "Category": GLib.Variant("s", "SystemServices"),
            "Id": GLib.Variant("s", "pulse"),
            "Title": GLib.Variant("s", self.title),
            "Status": GLib.Variant("s", "Active"),
            "WindowId": GLib.Variant("i", 0),
            "IconName": GLib.Variant("s", "" if self._pixmaps else "io.github.kutluhangil.Pulse"),
            "IconPixmap": GLib.Variant("a(iiay)", self._pixmaps),
            "OverlayIconName": GLib.Variant("s", ""),
            "AttentionIconName": GLib.Variant("s", ""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], *self._tooltip)),
            "ItemIsMenu": GLib.Variant("b", False),
            "Menu": GLib.Variant("o", MENU_PATH),
            "XAyatanaLabel": GLib.Variant("s", self._label),
            "XAyatanaLabelGuide": GLib.Variant("s", ""),
        }.get(prop)

    def _item_call(self, _bus, _sender, _path, _iface, method, _params, invocation):
        if method in ("Activate", "SecondaryActivate"):
            GLib.idle_add(lambda: (self.on_activate(), False)[1])
        invocation.return_value(None)

    # com.canonical.dbusmenu --------------------------------------------------

    def _menu_get(self, _bus, _sender, _path, _iface, prop):
        return {
            "Version": GLib.Variant("u", 3),
            "TextDirection": GLib.Variant("s", "ltr"),
            "Status": GLib.Variant("s", "normal"),
            "IconThemePath": GLib.Variant("as", []),
        }.get(prop)

    @staticmethod
    def _props(it: MenuItem) -> dict:
        if it.separator:
            return {"type": GLib.Variant("s", "separator")}
        props = {"label": GLib.Variant("s", it.label.replace("_", "__")), "enabled": GLib.Variant("b", it.enabled)}
        if it.icon:
            props["icon-name"] = GLib.Variant("s", it.icon)
        if it.children:
            props["children-display"] = GLib.Variant("s", "submenu")
        return props

    def _layout(self, it_id: int, items: list[MenuItem], depth: int):
        children = []
        if depth != 0:
            for it in items:
                children.append(GLib.Variant("(ia{sv}av)", self._layout_tuple(it, depth - 1)))
        props = {"children-display": GLib.Variant("s", "submenu")} if it_id == 0 else {}
        return (it_id, props, children)

    def _layout_tuple(self, it: MenuItem, depth: int):
        children = [GLib.Variant("(ia{sv}av)", self._layout_tuple(c, depth - 1)) for c in it.children] if depth else []
        return (it._id, self._props(it), children)

    def _menu_call(self, _bus, _sender, _path, _iface, method, params, invocation):
        if method == "GetLayout":
            parent, depth, _names = params.unpack()
            items = self._menu if parent == 0 else self._ids.get(parent, MenuItem()).children
            invocation.return_value(GLib.Variant("(u(ia{sv}av))", (self._revision, self._layout(parent, items, depth))))
        elif method == "GetGroupProperties":
            ids, _names = params.unpack()
            rows = [(i, self._props(self._ids[i])) for i in (ids or self._ids) if i in self._ids]
            invocation.return_value(GLib.Variant("(a(ia{sv}))", (rows,)))
        elif method == "GetProperty":
            it_id, name = params.unpack()
            value = self._props(self._ids[it_id]).get(name) if it_id in self._ids else None
            invocation.return_value(GLib.Variant("(v)", (value or GLib.Variant("s", ""),)))
        elif method == "Event":
            it_id, event, _data, _ts = params.unpack()
            self._fire(it_id, event)
            invocation.return_value(None)
        elif method == "EventGroup":
            (events,) = params.unpack()
            for it_id, event, _data, _ts in events:
                self._fire(it_id, event)
            invocation.return_value(GLib.Variant("(ai)", ([],)))
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "AboutToShowGroup":
            invocation.return_value(GLib.Variant("(aiai)", ([], [])))
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def _fire(self, it_id: int, event: str) -> None:
        it = self._ids.get(it_id)
        if event == "clicked" and it and it.action and it.enabled:
            GLib.idle_add(lambda: (it.action(), False)[1])
