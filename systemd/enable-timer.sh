#!/usr/bin/env bash
# Enable the sync timer where systemd runs it. Idempotent, and a no-op on a
# host without a user systemd instance rather than a failure.
set -uo pipefail

if ! command -v systemctl >/dev/null 2>&1; then
    echo "no systemctl — sync timer not enabled"
    exit 0
fi

if ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "no user systemd instance — sync timer not enabled"
    exit 0
fi

systemctl --user daemon-reload
systemctl --user enable --now dotfiles-sync.timer
systemctl --user list-timers dotfiles-sync.timer --no-pager | head -2
