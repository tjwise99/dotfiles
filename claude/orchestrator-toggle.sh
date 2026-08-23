#!/usr/bin/env bash
# UserPromptExpansion hook (matcher: orchestrate|work-ticket). Fires in the
# slash-command expansion path, before the model sees anything, and only for a
# human-typed command — a subagent cannot reach it (agent_id guard). Sets/clears
# the session-keyed orchestrator-mode marker that orchestrator-gate.sh reads.
#
#   /orchestrate on | /orchestrate   -> ON
#   /orchestrate off                 -> OFF
#   /orchestrate <other>             -> report state, no change
#   /work-ticket <n>                 -> ON (a ticket orchestrates by default)
#
# The marker holds an epoch expiry so a stale one cannot gate a later session;
# orchestrator-cleanup.sh (SessionEnd) and the gate's expiry check both back it up.
# session_id is a documented hook field, so this needs no undocumented env.
set -u
input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

# A subagent must not be able to flip the mode.
[ -n "$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)" ] && exit 0

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
turn_on() { date -d "+${ttl_hours} hours" +%s > "$marker" 2>/dev/null || echo 0 > "$marker"; }

on_msg="Main-thread Read/Edit/Write and content-dumping Bash (git show/diff, rg, file readers) are denied with a reminder — no human prompt. Delegate recon to Explore, edits to an Agent (code-monkey); have them write findings to a file and return <=10 lines. Agent/gh/thin status Bash stay free. The human can /orchestrate off to suspend."

case "$name" in
    work-ticket)
        turn_on
        emit "Orchestrator mode auto-enabled for this ticket. ${on_msg}"
        ;;
    *)
        case "$arg" in
            off)   rm -f "$marker"; emit "Orchestrator mode is now OFF. Main-thread tools are unrestricted." ;;
            ""|on) turn_on;         emit "Orchestrator mode is now ON. ${on_msg}" ;;
            *)     state=$( [ -f "$marker" ] && echo ON || echo OFF )
                   emit "Orchestrator mode is ${state} (unchanged; use /orchestrate on or /orchestrate off)." ;;
        esac
        ;;
esac
exit 0
