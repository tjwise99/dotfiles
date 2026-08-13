#!/bin/sh
# Render every themed config from ~/.config/theme and reload consumers.
set -e
case "$1" in
pywal|gtk) ;;
*) echo "usage: theme.sh pywal|gtk"; exit 1 ;;
esac

# gtk reads the theme through PyGObject, which is a distro package bound to the
# system interpreter — `python3` is uv's here (asdf/uv-python.sh) and does not
# carry it, so this source failed with ModuleNotFoundError while pywal worked.
# Chosen by what can import gi rather than by a path, which differs per host.
# render.py runs resolve.py with sys.executable, so the choice reaches both.
py=python3
if [ "$1" = gtk ]; then
    py=
    for candidate in python3 /usr/bin/python3 /run/current-system/sw/bin/python3; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -c 'import gi' 2>/dev/null; then
            py=$candidate
            break
        fi
    done
    [ -n "$py" ] || {
        echo "theme: no python3 with PyGObject; gtk source unavailable" >&2
        exit 1
    }
fi

"$py" "$HOME/.config/theme/render.py" "$1"

# Remembered so session.sh re-applies this choice at the next login instead of
# resetting to a default. Written after render.py succeeds, so a failed render
# does not change which source the session comes back as.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/theme"
mkdir -p "$STATE"
printf '%s\n' "$1" > "$STATE/source"

xrdb -merge "$HOME/.config/theme/xresources"
i3-msg reload >/dev/null 2>&1 || true
"$HOME/.config/polybar/launch.sh"
pkill -x dunst || true
sleep 1
setsid dunst >/dev/null 2>&1 </dev/null &
echo "theme: $1"
