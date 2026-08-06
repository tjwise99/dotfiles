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
