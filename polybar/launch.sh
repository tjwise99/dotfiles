#!/bin/sh
pkill -x polybar
while pgrep -x polybar >/dev/null; do sleep 1; done

# polybar exits outright if the pulseaudio module cannot reach the daemon, and
# i3 runs this in the same second pulseaudio.service finishes starting.
n=0
while [ "$n" -lt 30 ] && ! pactl info >/dev/null 2>&1; do
    sleep 0.5
    n=$((n + 1))
done

polybar main >/tmp/polybar-main.log 2>&1 &
