#!/bin/sh
# Render every themed config from ~/.config/theme and reload consumers.
set -e
case "$1" in
pywal|gtk) ;;
*) echo "usage: theme.sh pywal|gtk"; exit 1 ;;
esac

python3 "$HOME/.config/theme/render.py" "$1"

xrdb -merge "$HOME/.config/theme/xresources"
i3-msg reload >/dev/null 2>&1 || true
"$HOME/.config/polybar/launch.sh"
pkill -x dunst || true
sleep 1
setsid dunst >/dev/null 2>&1 </dev/null &
echo "theme: $1"
