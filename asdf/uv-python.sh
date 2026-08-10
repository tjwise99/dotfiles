#!/usr/bin/env bash
# The Python interpreter, installed and owned by uv.
#
# uv is the only thing that manages Python here: packages/manifest.yaml declares
# no distro python3, and asdf/tool-versions has no python plugin. `--default`
# is what makes that usable — without it uv installs `python3.14` only, and the
# bare `python3` that mason, conform and every shebang look for still resolves
# to whatever the distro shipped, or to nothing at all.
set -uo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.asdf/shims:${PATH}"

# One minor behind current, and pinned by a consumer rather than by taste:
# mason validates each Python tool's requires-python before installing it, and
# cmake-language-server caps at <3.14. It fails loudly, so the day this can move
# is the day a `MasonToolsInstall` stops reporting it.
VERSION=3.13.15

command -v uv >/dev/null 2>&1 || {
    echo "uv not on PATH — the asdf uv plugin may not be installed" >&2
    exit 1
}

# --default is still gated as a preview feature; naming it opts in rather than
# printing an "experimental" warning on every install.
uv python install --default --preview-features python-install-default "${VERSION}" || {
    echo "FAILED: uv python install ${VERSION}" >&2
    exit 1
}

# Resolving python3 and running venv, rather than trusting the line above. The
# install can succeed while `python3` still resolves somewhere else — the shim
# lands in ~/.local/bin, so anything earlier on PATH wins silently. mason builds
# every Python tool by calling `python3 -m venv`, so that exact call is the one
# worth measuring.
resolved="$(command -v python3 2>/dev/null)"
if [ -z "${resolved}" ]; then
    echo "python3 is not on PATH after uv python install" >&2
    exit 1
fi

case "${resolved}" in
    "${HOME}/.local/bin/"*) ;;
    *) echo "warning: python3 resolves to ${resolved}, not uv's" >&2 ;;
esac

probe="$(mktemp -d)"
trap 'rm -rf "${probe}"' EXIT
if python3 -m venv "${probe}/venv" >/dev/null 2>&1; then
    echo "ok: python3 $(python3 --version 2>&1 | cut -d' ' -f2) at ${resolved}, venv works"
else
    echo "python3 at ${resolved} cannot create a venv — mason's Python tools will fail" >&2
    exit 1
fi
