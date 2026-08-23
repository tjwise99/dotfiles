#!/bin/sh
# Emits desktop notifications for network interface state changes.
# Replaces nm-applet's notifications without claiming a tray icon.
#
# Reads the kernel's own event stream rather than a manager's. The previous
# version monitored NetworkManager, and when this host moved to iwd it did not
# fail — `nmcli monitor` printed "NetworkManager is stopped" and then blocked
# forever, so the script stayed in the process list emitting nothing. Nothing
# reports a notifier that has gone quiet, which is what makes the manager the
# wrong thing to watch: `ip monitor` says the same thing under NetworkManager,
# iwd, or a hand-run dhcpcd.

pkill -f "ip -o monitor link address" 2>/dev/null

ip -o monitor link address 2>/dev/null | awk '
    # Address gained or lost. Carries the address itself, which is the part
    # actually worth reading off a notification.
    $1 == "Deleted" && $4 == "inet" { print $3 "|lost its address"; fflush(); next }
    $3 == "inet"                    { print $2 "|up at " $4;        fflush(); next }

    # Carrier. NO-CARRIER is checked first because a downed interface still
    # carries the UP flag — UP is the admin state, LOWER_UP is the physical one.
    $2 ~ /:$/ && $3 ~ /NO-CARRIER/  { s=$2; sub(/:$/,"",s); print s "|disconnected"; fflush(); next }
    $2 ~ /:$/ && $3 ~ /LOWER_UP/    { s=$2; sub(/:$/,"",s); print s "|connected";    fflush(); next }
' | while IFS='|' read -r iface msg; do
	case "${iface}" in
		# Docker churns these as containers start and stop: docker0, the
		# br-<hex> bridge per user network, and a veth<hex> per container.
		lo|docker0|br-*|veth*) continue ;;
	esac
	notify-send -a network "Network" "${iface} ${msg}"
done
