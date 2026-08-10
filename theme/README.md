# Desktop theming

One source of truth for colours across polybar, dunst, rofi and i3 window
borders. `theme.sh <source>` resolves values from a live source, renders every
consumer from a template, and reloads them.

```
theme.sh gtk      # colours read from the active GTK theme
theme.sh pywal    # colours read from the X resource database
```

## Layout

| Source — edit these | |
|---|---|
| `resolve.py` | derives semantic values from a source |
| `render.py` | substitutes `@key@` placeholders, verifies output |
| `theme.sh` | resolve → render → reload |
| `polybar.ini.tmpl` | bar config; **holds the icon glyphs** |
| `dunstrc.tmpl` | notification styling |
| `xresources.tmpl` | `i3wm.*` resources for window borders |
| `rofi.rasi.tmpl` | launcher config **and** theme, one file |
| `alacritty.toml.tmpl` | terminal; **holds the fixed ANSI 16** |

| Generated — never hand-edit | rendered from |
|---|---|
| `~/.config/polybar/config.ini` | `polybar.ini.tmpl` |
| `~/.config/dunst/dunstrc` | `dunstrc.tmpl` |
| `~/.config/theme/xresources` | `xresources.tmpl` |
| `~/.config/rofi/config.rasi` | `rofi.rasi.tmpl` |
| `~/.config/alacritty/alacritty.toml` | `alacritty.toml.tmpl` |

Each generated file carries a header saying so. Edits to them are lost on the
next `theme.sh` run.

`~/.local/bin/theme.sh` is a symlink here, for PATH only.

## Adding a colour

Add the key to both `from_pywal()` and `from_gtk()` in `resolve.py`, then use
`@key@` in a template. `render.py` aborts if any placeholder is left
unsubstituted, so a key missing from one source fails loudly rather than
rendering a literal `@key@` into the bar.

## The shell can override the terminal

`~/.cache/wal/sequences` is OSC-4 escape codes that reprogram the palette of a
*running* terminal. `zshrc` used to `cat` it at every interactive start, which
overrode whatever the terminal had loaded from its own config a few milliseconds
earlier — so every shell came up in pywal gold no matter which source was
rendered. Nothing in the terminal's config or logs shows this; the config is
correct and the window is the wrong colour anyway.

That line was **not** vestigial. st compiles its colours in at build time, so it
could not follow a `wal` run without a recompile; the sequences were the only
thing making st track a wallpaper change. Removing them is right now that the
terminal is themed from this directory, but it costs that behaviour: **a new
wallpaper no longer reaches terminals on its own — run `theme.sh pywal` after
`wal -i`.** In exchange, that command re-colours *already-open* windows, which
the sequences never did (they only applied to newly-started shells).

Diagnostic tell: if `sh -c` renders correctly and the same terminal running an
interactive shell does not, suspect the shell, not the terminal.

## Derived colours

A pywal palette is image-derived and may contain no second dark surface — on a
monochrome wallpaper `color0` comes back byte-identical to `background`, and
every other entry is a saturated tint. A recessed element given such a value
disappears into the window rather than looking flat: the rofi input bar and the
unselected mode-switcher tabs both went invisible this way.

So `rofi_bg_alt` is **derived**, via `blend(bg, fg, 0.10)`, not read. Blending
toward the foreground rather than toward white keeps the result in the palette's
family and cannot invert: a dark background moves lighter, a light one moves
darker. The gtk source has a real second surface (`theme_base_color`) and reads
it directly.

## The terminal

The ANSI 16 come from the source, like every other colour: `pywal` reads
`color0`–`color15` straight out of `xrdb`. A GTK theme exposes no ANSI ramp, so
`from_gtk()` returns `ADWAITA_ANSI` — GNOME's terminal palette — and `from_pywal()`
uses the same list per-index for any entry `xrdb` is missing.

**Know the trade.** A pywal palette is image-derived and often near-monochrome:
on the current wallpaper `color1`–`color6` are all golds, so red, green and blue
are mutually indistinguishable. Semantic colour is genuinely lost — a failing
test and a passing one print the same shade. That is a legitimate thing to want
for the aesthetic, but if syntax highlighting or diff colours start looking
broken, this is why, and the fix is to hardcode `ADWAITA_ANSI` in the template
rather than to go hunting in the terminal.

Rewriting the generated file re-colours **already-open windows**, so `theme.sh`
needs no reload step for the terminal — but only because the template writes
`[general] live_config_reload = true` explicitly. The man page documents `true`
as the default; that default was **not** in effect here, and a rewrite left open
windows on their old palette until the key was set. Verified by A/B screenshot,
not by reading the default. Do not delete it as redundant.

A window still has to be **restarted once** to pick up a change to this key
itself, since the running process was launched under the old config.

`Xft.dpi: 96` lives in `~/.Xresources`, *not* in `xresources.tmpl`. Unset, winit
reads the panel's real EDID size (~142 DPI on a 14" 1080p) and scales alacritty
to 1.5x while everything else stays at 96. It belongs there because i3 merges
`~/.Xresources` at login, whereas the theme templates are rendered only when
`theme.sh` is run by hand — a static display fact in a hand-run template would
silently regress on the next reboot.

## Adding a source

Write a `from_x()` returning the same keys and register it in `SOURCES`.
Neither existing source stores hex: `pywal` queries `xrdb`, `gtk` queries the
live GTK theme through `gi`. A source that snapshots colours will silently go
stale.

## The glyph hazard

`polybar.ini.tmpl` contains 22 private-use-area characters — the Nerd Font
icons. They live in two ranges: `U+E000`–`U+F8FF` and `U+F0000`+ (Material
Design). **Some editors and tooling strip them silently.** A stripped glyph
renders as nothing, produces no error in any log, and looks identical to a
working bar minus one icon.

`render.py` refuses to write `config.ini` unless the rendered output contains
exactly `EXPECTED_GLYPHS` (22). If you intentionally add or remove an icon,
update that constant. To check a file by hand:

```sh
python3 -c "
s=open('FILE').read()
print(sum(1 for c in s if 0xE000<=ord(c)<=0xF8FF)+sum(1 for c in s if 0xF0000<=ord(c)<=0xFFFFD))"
```

Glyph names can be resolved from the font with `fontTools`; the Material Design
block interleaves `_alert` and `_lock` variants, so consecutive codepoints are
**not** consecutive signal levels. Verify names rather than assuming ordering.

## Constraints worth knowing

- Polybar does **not** expand `${section.key}` inside a `%{F...}` tag — its tag
  parser consumes the variable's closing brace. It does not error; it renders
  the literal text into the bar. This is why colours are substituted at render
  time instead of referenced from an included file.
- i3 runs `exec_always` on **restart only**, not on `reload`. `theme.sh` reloads
  i3 (for `set_from_resource`) and restarts polybar and dunst itself.
- Window border colours come from `set_from_resource` in `~/.config/i3/config`
  reading the generated `xresources`, which `theme.sh` merges with `xrdb`.
- Rofi reads its config at launch, so `theme.sh` does not reload it. There is no
  rofi daemon to restart.
- **Rofi merges the generated theme over its own built-in default.** An element
  state given only a `text-color` keeps the *default* theme's light row
  background — the `*` block's `background-color: transparent` does not win,
  because a state selector is more specific. So every `element <row>.<state>`
  rule sets `background-color` explicitly, including the states drun uses for
  already-running apps (`.active`). Setting only the ones you can see in a
  screenshot leaves the rest to surface later, on a row you happened not to have.
- Rofi draws its own rounded corners but needs a compositor for the area outside
  them; with none running those corners render black. `picom` is started from
  `~/.config/i3/config` for this.

## Session daemons

Launched from `~/.config/i3/config` via `exec_always`, each with its own
`pkill` guard so a restart replaces rather than stacks:

| | |
|---|---|
| `~/.config/i3/picom-launch.sh` | the compositor |
| `~/.config/polybar/launch.sh` | the bar |
| `~/.config/i3/network-notify.sh` | `ip monitor` → `notify-send` |
| `~/.config/i3/battery-notify.sh` | `batsignal`, 20%/10%, no danger command |
