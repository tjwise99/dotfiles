#!/bin/sh
# Wallpaper and theme, once per i3 start. This is what makes a freshly
# provisioned machine come up themed rather than needing theme.sh by hand.
#
# One script rather than two i3 exec lines because the two are ordered and i3
# does not order exec: resolve.py pywal reads the X resource database, and
# `wal -i` is what puts the palette there. Run the other way round it resolves
# nothing, falls back to the defaults hardcoded in resolve.py, and exits 0 —
# the wrong theme, reported as success.
#
# Not in the NixOS provisioning unit for the same reason: both sources read a
# live X session, which a User= oneshot at boot does not have.
set -u

wal -i "$HOME/.config/theme/wallpaper.jpg" || echo "theme: wal failed" >&2

# Whichever source was last applied, so a `theme.sh gtk` survives a logout
# rather than being reset here. Validated rather than passed through: an
# unreadable or garbage state file falls back instead of failing the session.
source=pywal
if [ -r "${XDG_STATE_HOME:-$HOME/.local/state}/theme/source" ]; then
    read -r saved < "${XDG_STATE_HOME:-$HOME/.local/state}/theme/source" || saved=
    case "${saved:-}" in
        pywal | gtk) source="${saved}" ;;
    esac
fi

# theme.sh is what starts polybar and dunst, so the fallback has to start the
# bar itself. A bar with stale colours beats no bar, and the failure is worth
# seeing rather than inferring from an empty screen.
"$HOME/.config/theme/theme.sh" "${source}" || {
    echo "theme: ${source} failed to render — starting the bar unthemed" >&2
    "$HOME/.config/polybar/launch.sh"
}
