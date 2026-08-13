#!/usr/bin/env bash
# PreToolUse hook on Bash. Two gates that CLAUDE.md previously stated in prose
# with nothing enforcing them.
#
#   deny  — `gh pr merge` and any --admin branch-protection bypass. A hard limit:
#           the required-review gate exists so a human looks before anything lands.
#   ask   — `git commit` / `git push` whose command chain does not confirm HEAD.
#           Parallel sessions share a worktree and switch HEAD between tool calls;
#           a commit once landed on another session's branch.
#
# Scans the whole command string rather than filtering on a prefix, because
# `git fetch && gh pr merge 5` has no dangerous prefix and merges just the same.
set -u

payload=$(cat)

extract() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null && return
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null && return
    fi
    # No parser: fall back to the raw envelope. Crude, but a gate that cannot
    # read its input must not silently pass the thing it exists to catch.
    printf '%s' "$payload"
}

cmd=$(extract)
[ -n "$cmd" ] || exit 0

decide() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
    exit 0
}

case "$cmd" in
    *"gh pr merge"*)
        decide deny "CLAUDE.md hard limit: never merge a PR unless the user said so for this specific PR. Ask, naming the PR."
        ;;
    *--admin*)
        decide deny "CLAUDE.md hard limit: --admin bypasses branch protection. Requires explicit per-PR authorization."
        ;;
esac

case "$cmd" in
    *"git commit"*|*"git push"*)
        case "$cmd" in
            *"git symbolic-ref"*|*"git switch "*|*"git checkout "*|*"--show-current"*)
                ;;
            *)
                decide ask "CLAUDE.md: confirm the branch in the same command chain as any commit or push. Prefix with 'git symbolic-ref --short HEAD &&' or 'git switch <branch> &&'."
                ;;
        esac
        ;;
esac

exit 0
