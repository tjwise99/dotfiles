#!/usr/bin/env bash
# Enable the sync timer where systemd runs it, and say so loudly where it does
# not. Idempotent.
#
# Exiting 0 quietly was right for the installer and wrong for the machine: WSL
# boots without systemd unless /etc/wsl.conf sets systemd=true, and a host with
# no timer never runs tools/sync.sh, so it never writes the failure marker
# either. Silence then means both "backed up fine" and "has never backed up".
# shell/interactive.sh reports the stamp's age for the same reason; this is the half
# that can name the cause while the installer is still running.
set -uo pipefail

wsl_hint() {
    cat >&2 <<'EOF'

  WSL boots without systemd unless it is turned on. Inside this distro:

      printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf

  then, from Windows:  wsl --shutdown   and reopen the distro.

  Until then nothing syncs this repo on a timer here, and the SessionEnd hook
  is the only thing backing it up.
EOF
}

if ! command -v systemctl >/dev/null 2>&1 || \
   ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "WARNING: no user systemd instance — the sync timer is NOT enabled" >&2
    [ -r /proc/version ] && grep -qi microsoft /proc/version && wsl_hint
    exit 0
fi

systemctl --user daemon-reload
systemctl --user enable --now dotfiles-sync.timer
# sed, not `| head -2`: with pipefail, head closing the pipe early SIGPIPEs
# list-timers (exit 141) and fails this script — and the unit — over a purely
# informational print. sed reads all input, so it exits 0.
systemctl --user list-timers dotfiles-sync.timer --no-pager | sed -n '1,2p'
