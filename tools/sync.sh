#!/usr/bin/env bash
# Commit local changes, integrate the other machine's, push.
#
# Never resolves a conflict. Tracked files are symlinked into $HOME, so a bad
# merge rewrites live shell config rather than a repo copy — on conflict this
# aborts and leaves the tree exactly as it was.
#
# Failures land in ~/.dotfiles-sync-failed, which bash/bashrc reports at the
# next shell. A sync that stops silently is worse than no sync.
set -uo pipefail

REPO="${HOME}/dotfiles"
MARKER="${HOME}/.dotfiles-sync-failed"
BRANCH="main"

cd "${REPO}" || exit 1

fail() {
    printf '%s\n' "$*" >"${MARKER}"
    echo "dotfiles sync: $*" >&2
    exit 1
}

# Reported, not enforced: a tracked file no profile deploys should still be
# backed up. Losing it to protect it would be the wrong trade.
gate_note=""
if ! python3 tools/check-manifest.py >/dev/null 2>&1; then
    gate_note="manifest gate failing — run tools/check-manifest.py"
fi

if [ -n "$(git status --porcelain)" ]; then
    git add -A
    scope="$(git diff --cached --name-only | cut -d/ -f1 | sort -u | paste -sd, -)"
    count="$(git diff --cached --name-only | wc -l)"
    git commit -q -m "sync: ${scope} (${count} file(s))" \
        || fail "commit failed — pre-commit hook or gitleaks refused it"
fi

git fetch -q origin || fail "fetch failed — no network, or the remote is gone"

if ! git rebase -q "origin/${BRANCH}" >/dev/null 2>&1; then
    git rebase --abort >/dev/null 2>&1
    fail "rebase conflict with origin/${BRANCH} — resolve by hand in ${REPO}"
fi

if [ -n "$(git log "origin/${BRANCH}..HEAD" --oneline)" ]; then
    git push -q origin "${BRANCH}" || fail "push rejected"
fi

if [ -n "${gate_note}" ]; then
    printf '%s\n' "${gate_note}" >"${MARKER}"
    exit 0
fi

rm -f "${MARKER}"
