#!/usr/bin/env bash
# SubagentStop hook (matches every agent). While the parent session is in orchestrator mode, a
# subagent cannot stop until its deliverable file is non-empty — making CLAUDE.md's "a subagent's
# deliverable is a file it wrote, never its prose" structural instead of advisory. Bounded three
# ways: one enforced retry (stop_hook_active), the harness cap (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP,
# default 8), and a pass-through while background work is in flight. Inert off orchestrator mode.
#
# Pass condition is the ARTEFACT (`-s "$path"`), never last_assistant_message — the agent claiming
# in prose that it wrote the file is the exact failure this exists to catch. exit_reason is not
# used: it does not exist in the SubagentStop schema.
set -u
input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
. "$HOME/dotfiles/claude/orchestrator-gate.sh"

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
aid=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
case "$sid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac   # path safety
case "$aid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
orchestrator_active "$sid" || exit 0

# Paused for background work, not finishing — don't fight the scheduler.
bg=$(printf '%s' "$input" | jq -r '(.background_tasks | length) // 0' 2>/dev/null)
[ "$bg" -gt 0 ] 2>/dev/null && exit 0

path=$(orchestrator_deliverable_path "$sid" "$aid")
[ -s "$path" ] && exit 0                                   # non-empty deliverable: let it stop

# Already blocked once — allow (harness guidance) and leave a trail on stderr.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && {
    printf 'Deliverable %s still missing after one retry; allowing stop.\n' "$path" >&2
    exit 0
}

last=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null | head -c 200)
printf 'You cannot finish yet: %s does not exist or is empty.\nYou ended with: "%s"\nWrite your deliverable now (use the Write tool — allow-listed here — or cat > %s <<'"'"'EOF'"'"' … EOF). If you found nothing, write that and why.\n' \
    "$path" "$last" "$path" >&2
exit 2
