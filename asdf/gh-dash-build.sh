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

# go from asdf, gh from tier 0. Both Nix profile forms: standalone Home Manager
# links ~/.nix-profile, the NixOS module does not.
export PATH="${HOME}/.nix-profile/bin:/etc/profiles/per-user/${USER:-${LOGNAME:-${HOME##*/}}}/bin:${HOME}/.asdf/shims:${HOME}/.local/bin:${PATH}"

UPSTREAM="https://github.com/dlvhdr/gh-dash"
COMMIT="a613ef744c99ef8d8ead33467813c6ee6086af52"
# Resolved from the repo root so the repo-relative path appears below as one
# contiguous literal, which is how tools/check-manifest.py vouches for a tracked
# file. A prefix that exists only after dirname has run never joins the rest,
# and the patch then reports as tracked but never deployed.
PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/asdf/patches/gh-dash.patch"
SRC="${HOME}/.cache/gh-dash-src"
STAMP="${SRC}/.built"
EXT="${HOME}/.local/share/gh/extensions/gh-dash"

command -v go >/dev/null 2>&1 || {
    echo "go not on PATH — asdf golang may not be installed" >&2
    exit 1
}

# Skipped rather than failed, unlike go above: gh is tier 0, and on a fresh box
# ./install runs before Nix does. Re-running ./install after that step builds
# it. Loud, because a silent skip here reads the same as a successful build.
command -v gh >/dev/null 2>&1 || {
    echo "skipped: gh-dash — gh not on PATH; re-run ./install after Home Manager" >&2
    exit 0
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
