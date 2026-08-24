#!/usr/bin/env bash
# UserPromptExpansion hook (matcher anchored to orchestrate|work-ticket|discover|plan|implement).
# Fires in the slash-command expansion path, before the model sees anything.
#
# This event is HUMAN-INITIATED — it fires for a command typed in the composer, not for a
# subagent's tool calls — and that is what keeps a delegate from flipping the mode. The event
# does not carry agent_id, so there is no in-band subagent field to key on; human-initiation is
# the guarantee. (A fork's expansion is the one exotic exception, and it can only turn the mode
# ON, which is harmless.)
#
#   /orchestrate on | /orchestrate                  -> ON
#   /orchestrate off                                -> OFF
#   /orchestrate <other>                            -> report state, no change
#   /work-ticket | /discover | /plan | /implement   -> ON (these commands orchestrate)
#
# Marker holds an epoch expiry; the gate prunes a stale/corrupt one and orchestrator-cleanup.sh
# removes it at SessionEnd. session_id is a documented field, so no undocumented env is needed.
set -u
input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$sid" ] || exit 0
name=$(printf '%s' "$input" | jq -r '.command_name // empty' 2>/dev/null)
arg=$(printf '%s' "$input" | jq -r '.command_args // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

dir="$HOME/.claude/orchestrator-mode"
mkdir -p "$dir"
marker="$dir/$sid"
ttl_hours=8

emit() {
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":%s}}\n' \
        "$(printf '%s' "$1" | jq -R -s '.')"
}
# Portable epoch — no GNU-only `date -d`. If even `date +%s` fails, write nothing rather than a
# marker with no valid expiry (the gate treats an unparseable expiry as expired anyway). (S1)
turn_on() {
    local n; n=$(date +%s 2>/dev/null)
    case "$n" in ''|*[!0-9]*) return 0 ;; esac
    echo $(( n + ttl_hours * 3600 )) > "$marker"
}

on_msg="Main-thread Read/Edit/Write/NotebookEdit, the Grep/Glob tools, and content-dumping Bash (git show/diff, rg, file readers, gh pr diff) are denied with a reminder — no human prompt. Delegate recon and edits to subagents; have them write findings under /tmp/claude-1000/ and return <=10 lines, which the orchestrator can read/grep there. /orchestrate off to suspend."

case "$name" in
    orchestrate)
        case "$arg" in
            off)   rm -f "$marker"; emit "Orchestrator mode is now OFF. Main-thread tools are unrestricted." ;;
            ""|on) turn_on;         emit "Orchestrator mode is now ON. ${on_msg}" ;;
            *)     state=$( [ -f "$marker" ] && echo ON || echo OFF )
                   emit "Orchestrator mode is ${state} (unchanged; use /orchestrate on or /orchestrate off)." ;;
        esac ;;
    work-ticket|discover|plan|implement)
        turn_on
        emit "Orchestrator mode auto-enabled for /${name}. ${on_msg}" ;;
esac
exit 0
