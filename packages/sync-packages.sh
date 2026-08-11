#!/usr/bin/env bash
# Install what packages/manifest.yaml names for this host, then verify it.
#
# Deliberately not a package manager: no resolution, no ordering, no version
# constraint, no removal. It expands a list and hands the whole list to the
# host's own tool in one call, which is what keeps this a declaration rather
# than a second thing with opinions about your system. If it ever needs to
# special-case a package, that is the signal to adopt a real cross-distro
# manager — see the tripwire in packages/manifest.yaml.
set -uo pipefail

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVE=("python3" "${BASEDIR}/packages/resolve.py")

HOST="${DOTFILES_HOST:-$("${RESOLVE[@]}" --host)}"

# NixOS declares its packages in the system config, so there is nothing here to
# install and nothing to verify against. Before the skip block below rather than
# in the case at the bottom: the non---packages path still calls resolve.py
# --verify, and this host has no manifest column for it to read.
if [ "${HOST}" = "nixos" ]; then
    echo "packages: owned by Nix on this host — nothing to install or verify"
    exit 0
fi

# Plain `sudo` reads the password from the terminal and fails outright without
# one — "a terminal is required to authenticate" — so this step worked when run
# by hand and broke under every tty-less caller: an editor's task runner, a
# systemd unit, Claude Code. `-A` is the fix but not unconditionally: it forces
# the graphical prompt even where a perfectly good terminal is attached, and on
# a headless host with no SUDO_ASKPASS it fails where plain sudo would have
# worked. Pick per invocation on the two things that actually decide it.
sudo_() {
    if [ ! -t 0 ] && [ -x "${SUDO_ASKPASS:-}" ]; then
        sudo -A "${@}"
    else
        sudo "${@}"
    fi
}

if [ "${DOTFILES_PACKAGES:-0}" != "1" ]; then
    echo "packages: skipped (needs root) — run ./install --packages to apply them"
    # Verification needs no privileges, so the skip still reports drift rather
    # than reporting nothing.
    "${RESOLVE[@]}" --host "${HOST}" --verify
    exit $?
fi

native="$("${RESOLVE[@]}" --host "${HOST}" --native)" || exit 1

case "${HOST}" in
    manjaro)
        # --needed so an already-correct machine is a no-op rather than a
        # reinstall. Word splitting is intended: one call, whole list.
        # shellcheck disable=SC2086
        sudo_ pacman -S --needed --noconfirm ${native} || exit 1
        aur="$("${RESOLVE[@]}" --host "${HOST}" --aur)" || exit 1
        if [ -n "${aur}" ]; then
            # yay, not pamac. pamac asks for privilege through polkit, which no
            # agent answers when there is no session — so the AUR step failed
            # outright under every tty-less caller while SUDO_ASKPASS sat there
            # unread, because that is a sudo mechanism. yay uses sudo, which is
            # what the rest of this file already solves.
            #
            # Not wrapped in sudo_: makepkg refuses to run as root, so yay
            # elevates only the install step itself. The -A decision is passed
            # down on the same two conditions sudo_ tests rather than made here.
            #
            # --needed for the reason the pacman call above has it. pamac had no
            # equivalent and rebuilt both packages on every run.
            aurflags=""
            if [ ! -t 0 ] && [ -x "${SUDO_ASKPASS:-}" ]; then
                aurflags="--sudoflags -A"
            fi
            # shellcheck disable=SC2086
            yay -S --needed --noconfirm ${aurflags} ${aur} || exit 1
        fi
        ;;
    wsl)
        sudo_ apt-get update -qq || exit 1
        # shellcheck disable=SC2086
        sudo_ apt-get install -y ${native} || exit 1
        ;;
    *)
        echo "no package step for host '${HOST}'" >&2
        exit 1
        ;;
esac

exec "${RESOLVE[@]}" --host "${HOST}" --verify
