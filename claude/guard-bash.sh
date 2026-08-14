#!/usr/bin/env bash
# PreToolUse hook on Bash. Gates PR merges — it does not forbid them.
#
#   A real `gh pr merge`, or gh's `--admin` branch-protection bypass, is:
#     allow — when an unexpired, matching grant sits in ~/.claude/merge-auth
#             (written by claude/merge-authorize.sh). This is the ahead-of-time
#             path: authorize once, walk away, let an unattended merge land
#             without a live prompt. --admin needs the grant to carry admin=1.
#     ask   — otherwise. The harness prompts; your approval IS the per-PR
#             authorization. No grant on file, expired, or the wrong PR all
#             fall here, so the safe default is a question, never a silent yes.
#
# The command is split into simple-command segments on shell separators and only
# a segment whose effective command is `gh` is inspected, so an incidental
# mention of "gh pr merge" in an echo, grep, path or commit message is untouched.
# Ordinary commits and pushes are never gated. deny is not used here: a gate that
# hard-refuses legal input with no override is a worse failure than one that asks.
set -u

payload=$(cat)
auth="$HOME/.claude/merge-auth"

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

# Read the ahead-of-time grant, if any. Plain key=value so no parser is needed;
# a missing, malformed or expired file simply yields no authorization.
a_pr=""; a_admin=0; a_expires=0
if [ -f "$auth" ]; then
    while IFS='=' read -r k v; do
        v="${v%$'\r'}"
        case "$k" in
            pr)      a_pr="$v" ;;
            admin)   a_admin="$v" ;;
            expires) a_expires="$v" ;;
        esac
    done < "$auth"
fi
now=$(date +%s 2>/dev/null)

# Is this specific merge command covered by the grant? Conservative: any doubt
# (bad expiry, admin without admin-scope, an explicit PR that doesn't match, a
# scoped grant against an unidentifiable PR) returns non-zero, which routes to ask.
authorized() {
    local cmd_pr="$1" cmd_admin="$2"
    [ -f "$auth" ] || return 1
    case "$a_expires" in ''|*[!0-9]*) return 1 ;; esac
    case "$now" in ''|*[!0-9]*) return 1 ;; esac
    [ "$now" -lt "$a_expires" ] || return 1
    if [ "$cmd_admin" = 1 ] && [ "$a_admin" != 1 ] && [ "$a_admin" != true ]; then
        return 1
    fi
    if [ -n "$a_pr" ]; then
        [ -n "$cmd_pr" ] && [ "$cmd_pr" = "$a_pr" ] || return 1
    fi
    return 0
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
            is_merge=0; has_admin=0
            [[ "$seg" =~ (^|[[:space:]])pr[[:space:]]+merge([[:space:]]|$) ]] && is_merge=1
            [[ "$seg" =~ (^|[[:space:]])--admin([[:space:]=]|$) ]] && has_admin=1
            [ "$is_merge" = 1 ] || [ "$has_admin" = 1 ] || continue

            cmd_pr=""
            if [[ "$seg" =~ /pull/([0-9]+) ]]; then
                cmd_pr="${BASH_REMATCH[1]}"
            elif [[ "$seg" =~ (^|[[:space:]])([0-9]+)([[:space:]]|$) ]]; then
                cmd_pr="${BASH_REMATCH[2]}"
            fi

            if authorized "$cmd_pr" "$has_admin"; then
                decide allow "Pre-authorized merge (merge-auth grant active)."
            fi
            decide ask "Merge gate: approving is your per-PR authorization. For an unattended merge, grant ahead with claude/merge-authorize.sh --pr N [--admin] [--hours H]."
            ;;
    esac
done < <(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||;|\|/\n/g')

exit 0
