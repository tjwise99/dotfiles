#!/usr/bin/env bash
# Global cargo crates, installed against asdf's rust.
#
# The counterpart to npm-globals.sh: asdf declares the runtime, not what is
# installed into it. asdf-rust points CARGO_HOME at its own install directory,
# so `cargo install` writes to ~/.asdf/installs/rust/<version>/bin and the
# binary is unreachable until the reshim below.
set -uo pipefail

export PATH="${HOME}/.asdf/shims:${HOME}/.local/bin:${PATH}"

CRATES=(
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

asdf reshim rust >/dev/null 2>&1
exit "${status}"
