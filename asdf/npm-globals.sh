#!/usr/bin/env bash
# Global npm packages, installed against asdf's node.
#
# asdf declares runtimes; it does not declare what you install into them. A
# package needed by the statusline or the shell has to be named somewhere or
# the next machine silently lacks it.
set -uo pipefail

export PATH="${HOME}/.asdf/shims:${HOME}/.local/bin:${PATH}"

PACKAGES=(
    ccstatusline
)

command -v npm >/dev/null 2>&1 || {
    echo "npm not on PATH — asdf nodejs may not be installed" >&2
    exit 1
}

status=0
for pkg in "${PACKAGES[@]}"; do
    if npm ls -g --depth=0 "${pkg}" >/dev/null 2>&1; then
        echo "ok: ${pkg}"
    else
        echo "installing ${pkg}"
        npm install -g "${pkg}" >/dev/null 2>&1 || { echo "FAILED: ${pkg}" >&2; status=1; }
    fi
done

asdf reshim nodejs >/dev/null 2>&1
exit "${status}"
