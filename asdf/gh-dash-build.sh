#!/usr/bin/env bash
# Build gh-dash from a pinned upstream commit plus patches/gh-dash.patch, and
# install it over the gh extension binary.
#
# The patch adds an `is:blocked` / `-is:blocked` filter token to issue sections
# and drops the notifications view from the switcher. The filter cannot run
# server-side: GitHub's search index does not carry issue dependencies, so
# `-is:blocked` sent to the API matches every open issue whether or not any is
# blocked. Upstream is pinned by commit rather than tracked, because the patch
# is written against that tree and a moving target would fail to apply on a
# machine nobody is watching.
#
# Builds in its own clone under ~/.cache: a working copy elsewhere must never be
# reset by an unattended install.
set -uo pipefail

export PATH="${HOME}/.asdf/shims:${HOME}/.local/bin:${PATH}"

UPSTREAM="https://github.com/dlvhdr/gh-dash"
COMMIT="a613ef744c99ef8d8ead33467813c6ee6086af52"
PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/gh-dash.patch"
SRC="${HOME}/.cache/gh-dash-src"
STAMP="${SRC}/.built"
EXT="${HOME}/.local/share/gh/extensions/gh-dash"

command -v go >/dev/null 2>&1 || {
    echo "go not on PATH — asdf golang may not be installed" >&2
    exit 1
}

if [ ! -r "${PATCH}" ]; then
    echo "missing patch: ${PATCH}" >&2
    exit 1
fi

# `gh extension upgrade` replaces the binary with an unpatched release, which
# looks identical to a correct install from the outside. Keying the stamp on the
# installed binary's own hash is what notices that and rebuilds.
installed_hash() {
    [ -x "${EXT}/gh-dash" ] && sha256sum "${EXT}/gh-dash" | cut -d' ' -f1
}

want="${COMMIT} $(sha256sum "${PATCH}" | cut -d' ' -f1)"
if [ -r "${STAMP}" ] && [ "$(cat "${STAMP}")" = "${want} $(installed_hash)" ]; then
    echo "ok: gh-dash (patched, ${COMMIT:0:7})"
    exit 0
fi

if [ ! -d "${EXT}" ]; then
    gh extension install dlvhdr/gh-dash >/dev/null 2>&1 || {
        echo "FAILED: gh extension install dlvhdr/gh-dash" >&2
        exit 1
    }
fi

if [ ! -d "${SRC}/.git" ]; then
    git clone --quiet "${UPSTREAM}" "${SRC}" || {
        echo "FAILED: clone ${UPSTREAM}" >&2
        exit 1
    }
fi

git -C "${SRC}" fetch --quiet origin || {
    echo "FAILED: fetch ${UPSTREAM}" >&2
    exit 1
}
git -C "${SRC}" reset --hard --quiet "${COMMIT}" || {
    echo "FAILED: ${COMMIT} not found in ${UPSTREAM}" >&2
    exit 1
}
git -C "${SRC}" clean -qfd

git -C "${SRC}" apply "${PATCH}" || {
    echo "FAILED: patch does not apply to ${COMMIT}" >&2
    exit 1
}

echo "building gh-dash (patched, ${COMMIT:0:7})"
(cd "${SRC}" && go build -o "${SRC}/gh-dash" .) >/dev/null 2>&1 || {
    echo "FAILED: gh-dash build" >&2
    exit 1
}

install -m 0755 "${SRC}/gh-dash" "${EXT}/gh-dash" || {
    echo "FAILED: installing over ${EXT}/gh-dash" >&2
    exit 1
}

printf '%s' "${want} $(installed_hash)" >"${STAMP}"
echo "ok: gh-dash (patched, ${COMMIT:0:7})"
