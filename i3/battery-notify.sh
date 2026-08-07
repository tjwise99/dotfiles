#!/bin/sh
# Low-battery desktop notifications. No tray icon, no danger-level command.

pkill -x batsignal 2>/dev/null

exec batsignal -w 20 -c 10 -p -m 10 -a battery
