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
        sudo pacman -S --needed --noconfirm ${native} || exit 1
        aur="$("${RESOLVE[@]}" --host "${HOST}" --aur)" || exit 1
        if [ -n "${aur}" ]; then
            # shellcheck disable=SC2086
            pamac build --no-confirm ${aur} || exit 1
        fi
        ;;
    wsl)
        sudo apt-get update -qq || exit 1
        # shellcheck disable=SC2086
        sudo apt-get install -y ${native} || exit 1
        ;;
    *)
        echo "no package step for host '${HOST}'" >&2
        exit 1
        ;;
esac

exec "${RESOLVE[@]}" --host "${HOST}" --verify
