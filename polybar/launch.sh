#!/bin/sh
pkill -x polybar
while pgrep -x polybar >/dev/null; do sleep 1; done
polybar main >/tmp/polybar-main.log 2>&1 &
