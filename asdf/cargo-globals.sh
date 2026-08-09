#!/usr/bin/env bash
# Global cargo crates, installed against asdf's rust.
#
# The counterpart to npm-globals.sh: asdf declares the runtime, not what is
# installed into it. These land in ~/.cargo/bin, which shell/common.sh puts on
# PATH — asdf reshim does not reach them.
set -uo pipefail

export PATH="${HOME}/.asdf/shims:${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

CRATES=(
    prr
    gh-review
)

command -v cargo >/dev/null 2>&1 || {
    echo "cargo not on PATH — asdf rust may not be installed" >&2
    exit 1
}

# Captured rather than piped into grep -q: under pipefail that exits 141 via
# SIGPIPE on a match, inverting the test.
installed="$(cargo install --list)"

status=0
for crate in "${CRATES[@]}"; do
    if [[ "${installed}" == *"${crate} v"* ]]; then
        echo "ok: ${crate}"
    else
        echo "installing ${crate}"
        cargo install "${crate}" >/dev/null 2>&1 || { echo "FAILED: ${crate}" >&2; status=1; }
    fi
done

exit "${status}"
