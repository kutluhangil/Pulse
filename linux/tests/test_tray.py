import gi

gi.require_version("GLib", "2.0")
from gi.repository import GLib  # noqa: E402

from pulse_monitor.tray import sprites  # noqa: E402
from pulse_monitor.tray.sni import MenuItem, TrayIcon, separator  # noqa: E402


def test_sprites_render_every_kind():
    for kind in sprites.KINDS:
        for phase in (0.0, 0.25, 0.5, 0.75):
            surface = sprites.render(kind, phase, "good", 22)
            data = sprites.argb_bytes(surface)
            assert len(data) == 22 * 22 * 4
            assert any(data[i] for i in range(0, len(data), 4)), f"{kind} drew nothing"


def test_argb_is_network_order():
    import cairo
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    cr = cairo.Context(surface)
    cr.set_source_rgba(1, 0, 0, 1)
    cr.paint()
    assert sprites.argb_bytes(surface) == bytes((255, 255, 0, 0))


def test_menu_layout_variant():
    tray = TrayIcon("Pulse", lambda: None)
    clicked = []
    tray._emit = lambda *a: None
    tray.set_menu([MenuItem("Open", lambda: clicked.append(1), "view-grid-symbolic"), separator(),
                   MenuItem("Logs", children=[MenuItem("a"), MenuItem("b")]), separator()])
    layout = GLib.Variant("(u(ia{sv}av))", (tray._revision, tray._layout(0, tray._menu, -1)))
    revision, (root, props, children) = layout.unpack()
    assert root == 0 and len(children) == 4
    ids = [c[0] for c in children]
    assert len(set(ids)) == 4, "separators need their own ids"
    logs = children[2]
    assert logs[1]["children-display"] == "submenu" and len(logs[2]) == 2
    assert children[1][1]["type"] == "separator"
