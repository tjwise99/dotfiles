#!/usr/bin/env bash
# Install or update the asdf binary into ~/.local/bin, which .bashrc already
# puts on PATH. No sudo: the target is inside $HOME.
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
API="https://api.github.com/repos/asdf-vm/asdf/releases/latest"

# Parsed with sed rather than jq: jq is not part of a base Manjaro install, and
# a bootstrap script that needs a package the host may not have defeats the
# point. One field out of a known-shaped response does not need a JSON parser.
latest="$(curl -fsSL "${API}" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1)"
if [ -z "${latest}" ]; then
    echo "could not resolve the latest asdf release" >&2
    exit 1
fi

if command -v asdf >/dev/null 2>&1; then
    installed="v$(asdf version 2>/dev/null | sed -E 's/^v?([0-9.]+).*/\1/')"
    if [ "${installed}" = "${latest}" ]; then
        echo "asdf ${installed} already current"
        exit 0
    fi
    echo "asdf ${installed} -> ${latest}"
fi

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) asset="asdf-${latest}-linux-amd64.tar.gz" ;;
    Linux/aarch64) asset="asdf-${latest}-linux-arm64.tar.gz" ;;
    Darwin/x86_64) asset="asdf-${latest}-darwin-amd64.tar.gz" ;;
    Darwin/arm64) asset="asdf-${latest}-darwin-arm64.tar.gz" ;;
    *) echo "unsupported platform: $(uname -s)/$(uname -m)" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/${latest}/${asset}" \
    -o "${tmp}/${asset}"
tar -xzf "${tmp}/${asset}" -C "${tmp}"

mkdir -p "${INSTALL_DIR}"
install -m 0755 "${tmp}/asdf" "${INSTALL_DIR}/asdf"
echo "asdf ${latest} installed to ${INSTALL_DIR}/asdf"
