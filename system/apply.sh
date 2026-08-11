#!/usr/bin/env bash
# Install the root-owned configuration this host's network stack needs.
#
# The only part of this repo that is copied rather than symlinked, because
# dotbot links into $HOME and these live under /etc. Two things make a symlink
# wrong here specifically: /home is its own partition, so a service starting
# before it is mounted would read a dangling path; and a root daemon's config
# would end up on a path its own unprivileged user can rewrite.
#
# Copying gives up the guarantee the rest of the repo has — /etc can drift with
# nothing to say so. That is why the unprivileged path reports the difference
# instead of reporting nothing, the same shape as packages/sync-packages.sh.
set -uo pipefail

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# source:target
FILES=(
    "system/iwd/main.conf:/etc/iwd/main.conf"
    "system/network/20-wired.network:/etc/systemd/network/20-wired.network"
)

# iwd owns wlan0 including its IP; systemd-networkd owns the wired link only.
# Both hand DNS to systemd-resolved, so all three are one stack, not three
# independent choices.
UNITS=(iwd systemd-networkd systemd-resolved)

# Enabling systemd-networkd pulls this in through the preset, and it measures
# the wrong thing here: it sees only networkd's links, and the one it has is a
# usually-empty wired port, so it reports not-online on a machine whose wifi is
# fine. Measured, not assumed — with the port cableless it blocks for its full
# timeout and then fails, and RequiredForOnline=no does not rescue it: nothing
# is left to satisfy it rather than something failing it. Kept in the checked
# set because a preset re-run is exactly the thing that would quietly undo it.
DISABLED_UNITS=(systemd-networkd-wait-online.service)

RESOLV_STUB=/run/systemd/resolve/stub-resolv.conf

problems=0
note() {
    echo "system: ${*}"
    problems=$((problems + 1))
}

check() {
    problems=0
    for pair in "${FILES[@]}"; do
        src="${BASEDIR}/${pair%%:*}"
        dst="${pair#*:}"
        if [ ! -e "${dst}" ]; then
            note "missing: ${dst}"
        elif ! cmp -s "${src}" "${dst}"; then
            note "differs from ${pair%%:*}: ${dst}"
        fi
    done
    for unit in "${UNITS[@]}"; do
        [ "$(systemctl is-enabled "${unit}" 2>&1)" = "enabled" ] || note "not enabled: ${unit}"
        [ "$(systemctl is-active "${unit}" 2>&1)" = "active" ] || note "not active: ${unit}"
    done
    for unit in "${DISABLED_UNITS[@]}"; do
        [ "$(systemctl is-enabled "${unit}" 2>&1)" = "enabled" ] && note "enabled, should not be: ${unit}"
    done
    [ "$(readlink -f /etc/resolv.conf)" = "${RESOLV_STUB}" ] \
        || note "/etc/resolv.conf does not resolve to ${RESOLV_STUB}"
}

if [ "${DOTFILES_SYSTEM:-0}" != "1" ]; then
    echo "system: skipped (needs root) — run ./install --system to apply it"
    check
    [ "${problems}" -eq 0 ] || exit 1
    exit 0
fi

# Why -A is picked per invocation rather than always: packages/sync-packages.sh.
sudo_() {
    if [ ! -t 0 ] && [ -x "${SUDO_ASKPASS:-}" ]; then
        sudo -A "${@}"
    else
        sudo "${@}"
    fi
}

for pair in "${FILES[@]}"; do
    src="${BASEDIR}/${pair%%:*}"
    dst="${pair#*:}"
    cmp -s "${src}" "${dst}" && continue
    echo "system: writing ${dst}"
    sudo_ install -D -m 0644 -o root -g root "${src}" "${dst}" || exit 1
done

sudo_ systemctl enable --now "${UNITS[@]}" || exit 1

# After the enable above, not before it: that is what turns this one back on.
for unit in "${DISABLED_UNITS[@]}"; do
    [ "$(systemctl is-enabled "${unit}" 2>&1)" = "enabled" ] || continue
    echo "system: disabling ${unit}"
    sudo_ systemctl disable "${unit}" || exit 1
done

if [ "$(readlink -f /etc/resolv.conf)" != "${RESOLV_STUB}" ]; then
    echo "system: pointing /etc/resolv.conf at ${RESOLV_STUB}"
    sudo_ ln -sf "${RESOLV_STUB}" /etc/resolv.conf || exit 1
fi

# networkd re-reads .network files only when told to, so a first run that
# enabled it and a later one that changed the file both need this.
sudo_ networkctl reload || exit 1

check
[ "${problems}" -eq 0 ] || exit 1
echo "system: ok — ${#FILES[@]} files, ${#UNITS[@]} units"
