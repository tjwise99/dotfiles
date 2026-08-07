#!/bin/sh
# Compositor. Rofi draws its own rounded corners and needs an ARGB visual for
# the area outside them; without a compositor those corners render black.
pkill -x picom
while pgrep -x picom >/dev/null; do sleep 1; done
picom --config "$HOME/.config/picom.conf" >/tmp/picom.log 2>&1 &
