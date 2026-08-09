#!/usr/bin/env bash
# Build gh-review from a pinned upstream commit plus patches/gh-review.patch.
#
# The published crate has neither the single-file diff view nor diff-line
# wrapping, so this replaces `cargo install gh-review`. Upstream is pinned by
# commit rather than tracked, because the patch is written against that tree
# and a moving target would fail to apply on a machine nobody is watching.
#
# Builds in its own clone under ~/.cache: a working copy elsewhere must never
# be reset by an unattended install.
set -uo pipefail

export PATH="${HOME}/.asdf/shims:${HOME}/.local/bin:${PATH}"

UPSTREAM="https://github.com/Neville-Loh/gh-review"
COMMIT="fe7bd3c864d803977bf414535051025917cb1244"
# Resolved from the repo root so the repo-relative path appears below as one
# contiguous literal, which is how tools/check-manifest.py vouches for a tracked
# file. A prefix that exists only after dirname has run never joins the rest,
# and the patch then reports as tracked but never deployed.
PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/asdf/patches/gh-review.patch"
SRC="${HOME}/.cache/gh-review-src"
STAMP="${SRC}/.built"

command -v cargo >/dev/null 2>&1 || {
    echo "cargo not on PATH — asdf rust may not be installed" >&2
    exit 1
}

if [ ! -r "${PATCH}" ]; then
    echo "missing patch: ${PATCH}" >&2
    exit 1
fi

# Keyed on both inputs, so editing the patch or moving the pin rebuilds.
want="${COMMIT} $(sha256sum "${PATCH}" | cut -d' ' -f1)"
if [ -r "${STAMP}" ] && [ "$(cat "${STAMP}")" = "${want}" ] &&
    command -v gh-review >/dev/null 2>&1; then
    echo "ok: gh-review (patched, ${COMMIT:0:7})"
    exit 0
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

echo "building gh-review (patched, ${COMMIT:0:7})"
cargo install --path "${SRC}" --force >/dev/null 2>&1 || {
    echo "FAILED: gh-review build" >&2
    exit 1
}

asdf reshim rust >/dev/null 2>&1
printf '%s' "${want}" >"${STAMP}"
echo "ok: gh-review (patched, ${COMMIT:0:7})"
