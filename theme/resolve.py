#!/usr/bin/env python3
"""Derive semantic theme values from a live source.

pywal -> reads the current X resource database
gtk   -> reads the active GTK theme through gi

Prints KEY=VALUE lines consumed by theme.sh. Nothing here is a stored
snapshot; both sources are queried at render time.
"""
import subprocess
import sys


def xrdb():
    out = subprocess.run(["xrdb", "-query"], capture_output=True, text=True).stdout
    res = {}
    for line in out.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            res[k.strip().lstrip("*.")] = v.strip()
    return res


# ANSI fallback: GNOME's Adwaita terminal palette, used where a source has no
# ramp of its own. Order is black, red, green, yellow, blue, magenta, cyan,
# white, then the same eight bright.
ADWAITA_ANSI = [
    "#241f31", "#c01c28", "#2ec27e", "#f5c211",
    "#1e78e4", "#9841bb", "#0ab9dc", "#c0bfbc",
    "#5e5c64", "#ed333b", "#57e389", "#f8e45c",
    "#51a1ff", "#c061cb", "#4fd2fd", "#f6f5f4",
]


def blend(a, b, t):
    """Mix hex colour a toward b by fraction t.

    Used to derive a recessed surface where the palette has no second dark
    tone. Blending toward the foreground rather than toward white keeps the
    result in the palette's family and works in either direction: a dark
    background moves lighter, a light one moves darker.
    """
    a, b = a.lstrip("#"), b.lstrip("#")
    return "#%02X%02X%02X" % tuple(
        round(int(a[i:i + 2], 16)
              + (int(b[i:i + 2], 16) - int(a[i:i + 2], 16)) * t)
        for i in (0, 2, 4))


def from_pywal():
    r = xrdb()
    bg = r.get("background", "#090909")
    fg = r.get("foreground", "#f6e992")
    accent = r.get("color4", "#d0ab32")
    muted = r.get("color8", "#aca366")
    urgent = r.get("color1", "#8d7628")
    ansi = {f"color{i}": r.get(f"color{i}", ADWAITA_ANSI[i]) for i in range(16)}
    return {
        **ansi,
        "bar_bg": bg, "fg": fg, "accent": accent, "accent_fg": bg,
        "muted": muted, "urgent": urgent, "glyph": accent, "border": muted,
        "dunst_bg": bg, "dunst_bg_low": bg, "dunst_fg_low": muted,
        "dunst_frame_low": muted,
        "rofi_bg": bg, "rofi_bg_alt": blend(bg, fg, 0.10), "rofi_border": muted,
        "term_bg": bg, "term_fg": fg,
        "font": "Noto Sans Mono 11",
        "frame_width": "2", "corner_radius": "8",
        "padding": "12", "hpadding": "14",
    }


def from_gtk():
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    st = Gtk.Settings.get_default()
    st.set_property("gtk-application-prefer-dark-theme", True)
    ctx = Gtk.Window().get_style_context()

    def c(name, fallback):
        ok, col = ctx.lookup_color(name)
        if not ok:
            return fallback
        return "#%02X%02X%02X" % (
            int(col.red * 255), int(col.green * 255), int(col.blue * 255))

    return {
        **{f"color{i}": v for i, v in enumerate(ADWAITA_ANSI)},
        "bar_bg": c("theme_base_color", "#2D2D2D"),
        "fg": c("theme_fg_color", "#EEEEEC"),
        "accent": c("theme_selected_bg_color", "#15539E"),
        "accent_fg": c("theme_selected_fg_color", "#FFFFFF"),
        "muted": c("insensitive_fg_color", "#919190"),
        "urgent": c("error_color", "#CC0000"),
        "glyph": "#3584e4",
        "border": c("borders", "#1B1B1B"),
        "dunst_bg": c("theme_bg_color", "#353535"),
        "dunst_bg_low": c("theme_base_color", "#2D2D2D"),
        "dunst_fg_low": c("insensitive_fg_color", "#919190"),
        "dunst_frame_low": c("borders", "#1B1B1B"),
        "rofi_bg": c("theme_bg_color", "#353535"),
        "rofi_bg_alt": c("theme_base_color", "#2D2D2D"),
        "rofi_border": c("borders", "#1B1B1B"),
        "term_bg": c("theme_base_color", "#2D2D2D"),
        "term_fg": c("theme_fg_color", "#EEEEEC"),
        "font": st.get_property("gtk-font-name") or "Adwaita Sans 11",
        "frame_width": "1", "corner_radius": "12",
        "padding": "16", "hpadding": "18",
    }


SOURCES = {"pywal": from_pywal, "gtk": from_gtk}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in SOURCES:
        sys.exit("usage: resolve.py %s" % "|".join(SOURCES))
    for k, v in SOURCES[sys.argv[1]]().items():
        print(f"{k}={v}")
