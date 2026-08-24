#!/usr/bin/env bash
# SubagentStart hook (matches every agent). While the parent session is in orchestrator mode,
# tell each spawned subagent — in its own initial context, before its first action — the
# deliverable path it must write before it can finish. The path is a pure function of
# (session_id, agent_id), both carried by this event, so deliverable-verify.sh recomputes the
# identical path with no shared state. Inert when the session is not orchestrating.
set -u
input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
. "$HOME/dotfiles/claude/orchestrator-gate.sh"

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
aid=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
case "$sid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac   # path safety: both interpolated into mkdir/paths
case "$aid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
orchestrator_active "$sid" || exit 0

path=$(orchestrator_deliverable_path "$sid" "$aid")
mkdir -p "$(dirname "$path")" 2>/dev/null || exit 0
msg="Your deliverable file is ${path}. Write your findings there — it must exist and be non-empty before you finish; you cannot stop until it does. Keep your chat reply to <=10 lines pointing at that file. Finding nothing is a valid result: write the file saying so, and why."
printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":%s}}\n' \
    "$(printf '%s' "$msg" | jq -R -s '.')"
exit 0
