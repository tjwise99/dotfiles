#!/usr/bin/env bash
# PreToolUse hook on Bash. One categorical gate:
#
#   deny — an actual `gh pr merge`, or gh's `--admin` branch-protection bypass.
#          A hard limit: the required-review gate exists so a human looks before
#          anything lands.
#
# The command is split into simple-command segments on shell separators and only
# a segment whose effective command is `gh` is inspected, so an incidental
# mention of "gh pr merge" in an echo, grep, path or commit message is not
# denied. deny is reserved for this categorical rule; heuristics do not belong in
# a hook that cannot offer an override (see claude/README.md).
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

# Inspect each simple command on its own. Splitting on && || | ; means a gh
# invocation chained after something harmless is still seen, without matching
# the same text quoted inside another command's arguments.
while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"          # trim leading whitespace
    # Strip leading wrappers and env-var assignments so `sudo gh …` / `FOO=1 gh …`
    # resolve to their real command.
    while :; do
        case "$seg" in
            sudo\ *|env\ *|command\ *|nohup\ *|time\ *|[A-Za-z_]*=*\ *)
                seg="${seg#* }"
                seg="${seg#"${seg%%[![:space:]]*}"}"
                ;;
            *) break ;;
        esac
    done
    case "$seg" in
        gh|gh\ *)
            if [[ "$seg" =~ (^|[[:space:]])pr[[:space:]]+merge([[:space:]]|$) ]]; then
                decide deny "CLAUDE.md hard limit: never merge a PR unless the user said so for this specific PR. Ask, naming the PR."
            fi
            if [[ "$seg" =~ (^|[[:space:]])--admin([[:space:]=]|$) ]]; then
                decide deny "CLAUDE.md hard limit: --admin bypasses branch protection. Requires explicit per-PR authorization."
            fi
            ;;
    esac
done < <(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||;|\|/\n/g')

exit 0
