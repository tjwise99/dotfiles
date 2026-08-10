#!/usr/bin/env bash
# Make zsh the login shell. Part of the opt-in root phase, because chsh needs
# privilege and because zsh has to be installed before this can succeed —
# packages/sync-packages.sh, which declares it, runs earlier in the same phase.
#
# Every exit path says what it did. A step that changes the shell you log in
# with is not one to be quiet about, in either direction.
#
# The guards exist because the failure is expensive and asymmetric: a login
# shell that will not start is recovered from a TTY, physically, on the laptop.
# So this refuses in every case it cannot prove safe, and refusing is a no-op
# rather than an install failure — the shell simply stays what it was.
set -uo pipefail

if [ "${DOTFILES_PACKAGES:-0}" != "1" ]; then
    echo "login shell: skipped (needs root) — run ./install --packages to set it"
    exit 0
fi

target="$(command -v zsh 2>/dev/null)"
current="$(getent passwd "${USER}" | cut -d: -f7)"

if [ -z "${target}" ]; then
    echo "WARNING: zsh is not installed — login shell left as ${current}" >&2
    exit 0
fi

# Resolved before comparing, not string-matched. /bin is a symlink to usr/bin on
# both distros, so passwd holding /bin/zsh and `command -v` giving /usr/bin/zsh
# name one file by two paths — and a string compare then reads "already correct"
# as "needs changing" and runs chsh on every install. Invisible on the machine
# this was written on, because there the script had itself written the resolved
# form into passwd.
if [ "$(readlink -f "${current}")" = "$(readlink -f "${target}")" ]; then
    echo "login shell already ${current}"
    exit 0
fi

# chsh validates this itself and refuses, but it refuses after prompting for a
# password, and the message it gives does not say which of the two things was
# wrong. Checked here so the reason is in the install output.
if ! grep -qxF "${target}" /etc/shells; then
    echo "WARNING: ${target} is not listed in /etc/shells — login shell left as ${current}" >&2
    exit 0
fi

# The guard that matters. Everything above proves zsh is installed and eligible;
# only this proves it runs. A zsh that exits non-zero here is one that would
# leave you unable to log in, and the whole point is to find that out now.
if ! "${target}" -c 'exit 0' >/dev/null 2>&1; then
    echo "WARNING: ${target} does not run — login shell left as ${current}" >&2
    exit 1
fi

echo "changing login shell: ${current} -> ${target}"
if ! sudo -A chsh -s "${target}" "${USER}"; then
    echo "WARNING: chsh failed — login shell left as ${current}" >&2
    exit 1
fi

# Read back rather than trusting the exit status: chsh writing nothing and
# reporting success is the case that would otherwise be reported as done.
now="$(getent passwd "${USER}" | cut -d: -f7)"
if [ "${now}" != "${target}" ]; then
    echo "WARNING: chsh reported success but the shell is still ${now}" >&2
    exit 1
fi

echo "login shell is now ${target} — open a new terminal for it to take effect"
