#!/usr/bin/env bash
# Assert every runtime named in ~/.tool-versions is actually installed.
#
# Dotbot's asdf directive reports success even when `asdf` is unreachable or a
# plugin fails, which yields a machine with config but no toolchain. This turns
# that into a non-zero exit, which fails ./install.
set -uo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.asdf/shims:${PATH}"
versions="${HOME}/.tool-versions"

if ! command -v asdf >/dev/null 2>&1; then
    echo "asdf is not on PATH after install" >&2
    exit 1
fi

if [ ! -r "${versions}" ]; then
    echo "no readable ${versions}" >&2
    exit 1
fi

status=0

# A plugin named in the profile with no line in ~/.tool-versions installs a shim
# that shadows whatever else provides the command, then refuses to run with
# "No version is set". The loop below reads ~/.tool-versions, so it cannot see
# that at all — the missing entry is the defect.
profile="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/profiles/base.conf.yaml"
if [ -r "${profile}" ]; then
    while read -r plugin; do
        [ -n "${plugin}" ] || continue
        if ! grep -qE "^${plugin}[[:space:]]" "${versions}"; then
            echo "UNDECLARED: ${profile##*/} installs plugin '${plugin}' with no ${versions} line" >&2
            status=1
        fi
    done < <(sed -n 's/^[[:space:]]*-[[:space:]]*plugin:[[:space:]]*\([^[:space:]]*\).*/\1/p' "${profile}")
else
    echo "cannot read ${profile} — the plugin cross-check did not run" >&2
    status=1
fi

while read -r tool version _; do
    case "${tool}" in ''|\#*) continue ;; esac
    if asdf where "${tool}" "${version}" >/dev/null 2>&1; then
        echo "ok: ${tool} ${version}"
    else
        echo "MISSING: ${tool} ${version}" >&2
        status=1
    fi
done < "${versions}"

exit "${status}"
