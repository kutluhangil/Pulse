"""Animated tray characters drawn with cairo, port of PulseUI/MenuBarSprites.swift.

Drawing uses the Swift sprite's coordinates (20 x 18 points, y up) inside a
square icon; `phase` runs 0..1 over one loop.
"""

from __future__ import annotations

import math

import cairo

SPRITE_W, SPRITE_H = 20.0, 18.0
INK = (0.965, 0.961, 0.957)          # Adwaita light_1, for the dark top bar
HEALTH = {                            # Adwaita palette
    "good": (0.20, 0.82, 0.48),       # green_3
    "warn": (0.96, 0.76, 0.07),       # yellow_4
    "critical": (0.88, 0.11, 0.14),   # red_3
    "offline": (0.60, 0.60, 0.59),    # light_5
}
KINDS = ("server", "cat", "pulse", "none")


def render(kind: str, phase: float, health: str, size: int) -> cairo.ImageSurface:
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    if kind == "none":
        kind = "server"
    cr = cairo.Context(surface)
    scale = size / 24.0
    cr.scale(scale, scale)
    cr.translate((24 - SPRITE_W) / 2, (24 + SPRITE_H) / 2)
    cr.scale(1, -1)                    # y up, like AppKit
    color = HEALTH.get(health, HEALTH["offline"])
    {"server": _server, "cat": _cat, "pulse": _pulse}[kind](cr, phase, color)
    surface.flush()
    return surface


def argb_bytes(surface: cairo.ImageSurface) -> bytes:
    """Cairo's native premultiplied BGRA (little endian) -> straight ARGB in network order (SNI)."""
    w, h, stride = surface.get_width(), surface.get_height(), surface.get_stride()
    src = surface.get_data()
    out = bytearray(w * h * 4)
    o = 0
    for y in range(h):
        row = y * stride
        for x in range(w):
            b, g, r, a = src[row + 4 * x: row + 4 * x + 4]
            if a and a < 255:
                r, g, b = r * 255 // a, g * 255 // a, b * 255 // a
            out[o:o + 4] = bytes((a, r, g, b))
            o += 4
    return bytes(out)


def _rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _oval(cr, x, y, w, h):
    cr.save()
    cr.translate(x + w / 2, y + h / 2)
    cr.scale(w / 2, h / 2)
    cr.arc(0, 0, 1, 0, 2 * math.pi)
    cr.restore()


def _server(cr, phase, health):
    hop = max(0.0, math.sin(phase * 2 * math.pi))
    landing = max(0.0, -math.sin(phase * 2 * math.pi))
    w, h = 12 + landing * 1.6, 12 - landing * 1.8
    mid = SPRITE_W / 2
    x, y = mid - w / 2, 2 + hop * 4.2

    sw = 10 - hop * 4
    cr.set_source_rgba(*INK, 0.22)
    _oval(cr, mid - sw / 2, 0, sw, 1.6)
    cr.fill()

    cr.set_source_rgb(*INK)
    cr.set_line_width(1.2)
    _rounded(cr, x + 0.6, y + 0.6, w - 1.2, h - 1.2, 2.2)
    cr.stroke()
    cr.set_line_width(1.0)
    for i in range(3):
        sy = y + 2.4 + i * 3.2
        cr.set_source_rgb(*INK)
        cr.move_to(x + 2.4, sy)
        cr.line_to(x + w - 5, sy)
        cr.stroke()
        on = int(phase * 6 + i) % 3 != 0
        cr.set_source_rgba(*health, 1.0 if on else 0.25)
        _oval(cr, x + w - 3.8, sy - 1, 2, 2)
        cr.fill()


def _cat(cr, phase, _health):
    t = phase * 2 * math.pi
    bob = abs(math.sin(t)) * 1.2
    cr.set_source_rgb(*INK)
    bx, by, bw, bh = 4, 6 + bob, 10, 5.5
    _rounded(cr, bx, by, bw, bh, 2.75)
    cr.fill()
    hx, hy, hw, hh = bx + bw - 2, by + 2.5, 6, 5.5
    _oval(cr, hx, hy, hw, hh)
    cr.fill()
    for dx in (0.6, 3.4):
        cr.move_to(hx + dx, hy + hh - 1.2)
        cr.line_to(hx + dx + 1.1, hy + hh + 1.8)
        cr.line_to(hx + dx + 2.2, hy + hh - 1.2)
        cr.close_path()
        cr.fill()
    cr.set_source_rgb(0.14, 0.14, 0.14)
    _oval(cr, hx + hw - 2.4, hy + hh / 2 + 0.2, 1.1, 1.1)
    cr.fill()

    cr.set_source_rgb(*INK)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_width(1.4)
    cr.move_to(bx + 0.5, by + bh / 2 + 1)
    cr.curve_to(bx - 2, by + bh / 2, bx - 3.5, by + bh, bx - 3.2, by + bh + 2.5 + math.sin(t * 2) * 1.2)
    cr.stroke()
    cr.set_line_width(1.3)
    for lx, offset in ((bx + 2, 0), (bx + 3.5, math.pi), (bx + bw - 2.5, math.pi), (bx + bw - 1, 0)):
        swing = math.sin(t + offset) * 2.2
        cr.move_to(lx, by + 0.8)
        cr.line_to(lx + swing, 1 + max(0.0, math.cos(t + offset)) * 1.2)
        cr.stroke()


BEAT = ((0, 0), (0.30, 0), (0.36, 0.25), (0.42, -0.35), (0.50, 0.95), (0.57, -0.55), (0.63, 0.12), (0.70, 0), (1, 0))


def _pulse(cr, phase, health):
    mid, amp, shift = SPRITE_H / 2, SPRITE_H * 0.42, phase * SPRITE_W
    cr.rectangle(0, 0, SPRITE_W, SPRITE_H)
    cr.clip()
    first = True
    for copy in (0, 1):
        for bx, by in BEAT:
            px, py = (bx + copy) * SPRITE_W - shift, mid + by * amp
            if first:
                cr.move_to(px, py)
                first = False
            else:
                cr.line_to(px, py)
    cr.set_source_rgb(*health)
    cr.set_line_width(1.5)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.stroke()
