"""Container log viewer (last lines from the agent, refreshed on demand)."""

from __future__ import annotations

import threading

from gi.repository import Adw, GLib, Gtk

from ..client import AgentClient, describe
from ..i18n import _
from ..levels import display_name
from ..model import Container


class LogsDialog(Adw.Dialog):
    def __init__(self, client: AgentClient, container: Container):
        super().__init__(title=display_name(container), content_width=760, content_height=520)
        self.client = client
        self.container = container
        header = Adw.HeaderBar()
        reload = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text=_("Reload"))
        reload.connect("clicked", lambda _b: self.load())
        header.pack_start(reload)
        self.view = Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                                 top_margin=12, bottom_margin=12, left_margin=12, right_margin=12)
        self.scroller = Gtk.ScrolledWindow(child=self.view, vexpand=True)
        toolbar = Adw.ToolbarView(content=self.scroller)
        toolbar.add_top_bar(header)
        self.set_child(toolbar)
        self.load()

    def load(self) -> None:
        self.view.get_buffer().set_text(_("Loading…"))

        def work():
            try:
                text = self.client.logs(self.container.id, 300) or _("No log lines")
            except Exception as e:
                text = describe(e)
            GLib.idle_add(self._show, text)
        threading.Thread(target=work, daemon=True).start()

    def _show(self, text: str) -> bool:
        buf = self.view.get_buffer()
        buf.set_text(text)
        adj = self.scroller.get_vadjustment()
        GLib.idle_add(lambda: (adj.set_value(adj.get_upper()), False)[1])
        return GLib.SOURCE_REMOVE
