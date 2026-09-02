#!/usr/bin/env bash
# SessionEnd hook: remove this session's orchestrator-mode marker so a mode left
# ON cannot silently gate a later session. The expiry timestamp inside the marker
# covers a hard kill (SIGKILL, window close, OOM, power loss) that skips SessionEnd.
#
# Deliverables are NOT removed here: they live in the durable ~/.claude/deliverables tree so a
# synthesis the orchestrator did not finish survives the session. Prune them by hand when done.
set -u
input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
# Only a well-formed session id ever reaches the marker path.
case "$sid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
rm -f "$HOME/.claude/orchestrator-mode/$sid"
exit 0
