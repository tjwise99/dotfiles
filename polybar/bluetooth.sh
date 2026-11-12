#!/bin/sh
# Bluetooth state for polybar's bluetooth module: the off glyph, the on glyph,
# or the connected glyph and the connected devices' names.
#
# The glyphs arrive as arguments from polybar.ini.tmpl so they stay where the
# theme colours them and render.py counts them.
#
# bluetoothctl waits indefinitely for bluetoothd when the daemon is down, so
# every call is bounded; a hung call would freeze the module's output.
off=$1 on=$2 connected=$3

if ! timeout 2 bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
    printf '%s\n' "$off"
    exit 0
fi

names=$(timeout 2 bluetoothctl devices Connected 2>/dev/null | awk '
    $1 == "Device" { sub(/^Device [^ ]+ /, ""); out = out (n++ ? ", " : "") $0 }
    END { print out }')

if [ -n "$names" ]; then
    printf '%s %s\n' "$connected" "$names"
else
    printf '%s\n' "$on"
fi
