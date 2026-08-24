#!/usr/bin/env bash
# SessionEnd hook: remove this session's orchestrator-mode marker so a mode left
# ON cannot silently gate a later session. The expiry timestamp inside the marker
# covers a hard kill (SIGKILL, window close, OOM, power loss) that skips SessionEnd.
set -u
input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
# Only a well-formed session id: never interpolate '..' or a slash into an rm -rf path.
case "$sid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
rm -f "$HOME/.claude/orchestrator-mode/$sid"
rm -rf "/tmp/claude-1000/orchestrator-deliverables/$sid" 2>/dev/null   # deliverables are per-session
exit 0
