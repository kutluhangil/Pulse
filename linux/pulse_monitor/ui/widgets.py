"""Small drawing widgets: score ring, sparkline, status dot, resource row."""

from __future__ import annotations

import math

from gi.repository import Gtk, Pango

from ..levels import Level

# Adwaita palette (libadwaita named colours), readable in light and dark styles.
COLORS = {
    "blue": (0.21, 0.52, 0.89),     # blue_3
    "green": (0.18, 0.76, 0.49),    # green_4
    "yellow": (0.90, 0.65, 0.04),   # yellow_5
    "orange": (1.0, 0.47, 0.0),     # orange_3
    "red": (0.88, 0.11, 0.14),      # red_3
    "purple": (0.57, 0.25, 0.67),   # purple_3
    "gray": (0.60, 0.60, 0.59),
}
LEVEL_COLOR = {Level.GOOD: "green", Level.WARN: "yellow", Level.CRITICAL: "red"}


class ScoreRing(Gtk.DrawingArea):
    """Health score in a ring that fills to the score, coloured by level."""

    def __init__(self, size: int = 96):
        super().__init__(content_width=size, content_height=size, valign=Gtk.Align.CENTER)
        self.score: int | None = None
        self.color = "gray"
        self.set_draw_func(self._draw)

    def update(self, score: int | None, color: str) -> None:
        if (score, color) != (self.score, self.color):
            self.score, self.color = score, color
            self.queue_draw()

    def _draw(self, _area, cr, w, h):
        fg = self.get_color()
        r = min(w, h) / 2 - 5
        cx, cy = w / 2, h / 2
        cr.set_line_width(7)
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.10)
        cr.arc(cx, cy, r, 0, 2 * math.pi)
        cr.stroke()
        if self.score is not None:
            cr.set_line_cap(1)   # round
            cr.set_source_rgb(*COLORS[self.color])
            start = -math.pi / 2
            cr.arc(cx, cy, r, start, start + 2 * math.pi * max(0.02, min(1, self.score / 100)))
            cr.stroke()
        text = "–" if self.score is None else str(self.score)
        layout = self.create_pango_layout(text)
        layout.set_font_description(Pango.FontDescription.from_string("Sans Bold 26"))
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_font_features_new("tnum=1"))
        layout.set_attributes(attrs)
        tw, th = layout.get_pixel_size()
        cr.set_source_rgba(fg.red, fg.green, fg.blue, fg.alpha)
        cr.move_to(cx - tw / 2, cy - th / 2)
        from gi.repository import PangoCairo
        PangoCairo.show_layout(cr, layout)


class Sparkline(Gtk.DrawingArea):
    """Filled line of recent values. `ceiling` fixes the top (100 for percent);
    None scales to the largest value seen (rates)."""

    def __init__(self, color: str = "blue", ceiling: float | None = 100.0, height: int = 34):
        super().__init__(content_height=height, hexpand=True)
        self.series: list[list[float]] = [[]]
        self.colors = [color]
        self.ceiling = ceiling
        self.set_draw_func(self._draw)

    def update(self, *series: list[float], colors: list[str] | None = None) -> None:
        self.series = [list(s) for s in series]
        if colors:
            self.colors = colors
        self.queue_draw()

    def _draw(self, _area, cr, w, h):
        top = self.ceiling or max([max(s) for s in self.series if s] + [1.0])
        top = max(top, 1e-9)
        fg = self.get_color()
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.08)
        cr.rectangle(0, h - 1, w, 1)
        cr.fill()
        for values, name in zip(self.series, self.colors * len(self.series)):
            if len(values) < 2:
                continue
            color = COLORS[name]
            step = w / (len(values) - 1)
            cr.move_to(0, h)
            for i, v in enumerate(values):
                cr.line_to(i * step, h - 2 - (h - 4) * min(1.0, max(0.0, v / top)))
            cr.line_to(w, h)
            cr.close_path()
            cr.set_source_rgba(*color, 0.16)
            cr.fill_preserve()
            cr.new_path()
            for i, v in enumerate(values):
                y = h - 2 - (h - 4) * min(1.0, max(0.0, v / top))
                (cr.move_to if i == 0 else cr.line_to)(i * step, y)
            cr.set_source_rgb(*color)
            cr.set_line_width(1.6)
            cr.stroke()


class Dot(Gtk.DrawingArea):
    def __init__(self, color: str = "gray", size: int = 10):
        super().__init__(content_width=size, content_height=size, valign=Gtk.Align.CENTER)
        self.color = color
        self.set_draw_func(self._draw)

    def set_color(self, color: str) -> None:
        if color != self.color:
            self.color = color
            self.queue_draw()

    def _draw(self, _area, cr, w, h):
        cr.set_source_rgb(*COLORS[self.color])
        cr.arc(w / 2, h / 2, min(w, h) / 2, 0, 2 * math.pi)
        cr.fill()


def numeric(label: Gtk.Label) -> Gtk.Label:
    label.add_css_class("numeric")
    return label


class ResourceRow(Gtk.ListBoxRow):
    """Icon, title and detail on the left, a big value on the right, a graph or
    bar underneath: the GNOME System Monitor "Resources" look in a boxed list."""

    def __init__(self, icon: str, title: str, graph: Gtk.Widget | None = None):
        super().__init__(activatable=False, selectable=False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                      margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        top = Gtk.Box(spacing=12)
        image = Gtk.Image.new_from_icon_name(icon)
        image.add_css_class("dim-label")
        top.append(image)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True, valign=Gtk.Align.CENTER)
        self.title = Gtk.Label(label=title, xalign=0)
        self.title.add_css_class("heading")
        self.detail = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.detail.add_css_class("caption")
        self.detail.add_css_class("dim-label")
        texts.append(self.title)
        texts.append(self.detail)
        top.append(texts)
        self.value = numeric(Gtk.Label(xalign=1))
        self.value.add_css_class("title-3")
        top.append(self.value)
        box.append(top)
        self.graph = graph
        if graph:
            box.append(graph)
        self.set_child(box)

    def show(self, value: str, detail: str, level: Level | None = None) -> None:
        self.value.set_label(value)
        self.detail.set_label(detail)
        for css in ("success", "warning", "error"):
            self.value.remove_css_class(css)
        if level is not None and level != Level.GOOD:
            self.value.add_css_class(level.css)


def level_bar(fraction: float, bar: Gtk.LevelBar | None = None) -> Gtk.LevelBar:
    bar = bar or Gtk.LevelBar(min_value=0, max_value=1, hexpand=True)
    bar.set_value(max(0.0, min(1.0, fraction)))
    return bar
