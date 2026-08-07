#!/bin/sh
# Emits desktop notifications for NetworkManager device state changes.
# Replaces nm-applet's notifications without claiming a tray icon.

pkill -f "nmcli monitor" 2>/dev/null

nmcli monitor | while IFS= read -r line; do
	iface=${line%%:*}
	case "$line" in
	*": disconnected"*) notify-send -a network "Network" "$iface disconnected" ;;
	*": unavailable"*)  notify-send -a network "Network" "$iface unavailable" ;;
	*": connected"*)    notify-send -a network "Network" "$iface connected" ;;
	esac
done
