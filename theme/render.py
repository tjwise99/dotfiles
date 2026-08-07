#!/usr/bin/env python3
"""Render theme templates for a given source.

Substitution is a plain @key@ replacement, so glyph characters in the
templates are copied byte-for-byte. The polybar output is verified to
carry the expected glyph count and the render aborts if it does not --
a lost glyph renders as nothing and produces no error anywhere else.
"""
import pathlib
import re
import subprocess
import sys

THEME = pathlib.Path.home() / ".config/theme"
EXPECTED_GLYPHS = 22

TARGETS = [
    ("polybar.ini.tmpl", pathlib.Path.home() / ".config/polybar/config.ini"),
    ("dunstrc.tmpl", pathlib.Path.home() / ".config/dunst/dunstrc"),
    ("xresources.tmpl", THEME / "xresources"),
    ("rofi.rasi.tmpl", pathlib.Path.home() / ".config/rofi/config.rasi"),
    ("alacritty.toml.tmpl",
     pathlib.Path.home() / ".config/alacritty/alacritty.toml"),
]


def glyphs(text):
    return sum(1 for c in text
               if 0xE000 <= ord(c) <= 0xF8FF or 0xF0000 <= ord(c) <= 0xFFFFD)


def main(source):
    out = subprocess.run([sys.executable, str(THEME / "resolve.py"), source],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr.strip() or "resolve failed")
    values = dict(l.split("=", 1) for l in out.stdout.splitlines() if "=" in l)

    for tmpl_name, dest in TARGETS:
        tmpl = (THEME / tmpl_name).read_text()
        rendered = tmpl
        for k, v in values.items():
            rendered = rendered.replace(f"@{k}@", v)

        left = re.findall(r"@\w+@", rendered)
        if left:
            sys.exit(f"{tmpl_name}: unresolved placeholders {sorted(set(left))}")

        if dest.name == "config.ini":
            got = glyphs(rendered)
            if got != EXPECTED_GLYPHS:
                sys.exit(f"{tmpl_name}: glyph count {got}, expected "
                         f"{EXPECTED_GLYPHS} -- refusing to write")

        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(rendered)
        print(f"  {dest}")

    print(f"source={source} glyphs=ok values={len(values)}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: render.py pywal|gtk")
    main(sys.argv[1])
