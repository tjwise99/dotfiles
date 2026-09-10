#!/usr/bin/env bash
# Rustup components, installed against asdf's rust.
#
# asdf declares the toolchain; it does not declare which rustup components
# ride along. grcov's source-based coverage path shells out to llvm-profdata
# and, missing it, prints an error but still exits 0 — producing a report with
# fabricated 100% coverage instead of failing. llvm-tools-preview ships a
# version-matched llvm-profdata for the active toolchain, which is what fixes
# that silently.
set -uo pipefail

export PATH="${HOME}/.asdf/shims:${HOME}/.local/bin:${PATH}"

COMPONENTS=(
    llvm-tools-preview
)

command -v rustup >/dev/null 2>&1 || {
    echo "rustup not on PATH — asdf rust may not be installed" >&2
    exit 1
}

status=0
for component in "${COMPONENTS[@]}"; do
    if rustup component list --installed | grep -q "^${component%-preview}"; then
        echo "ok: ${component}"
    else
        echo "installing ${component}"
        rustup component add "${component}" >/dev/null 2>&1 || { echo "FAILED: ${component}" >&2; status=1; }
    fi
done

exit "${status}"
