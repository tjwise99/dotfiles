#!/usr/bin/env bash
# Sourced by guard-read.sh / guard-bash.sh / guard-publish.sh, AND run standalone as the
# PreToolUse hook for Grep|Glob. Defines orchestrator_gate: while a session is in orchestrator
# mode, deny main-thread tool calls that pull file/diff/tree CONTENT into the orchestrating
# context, so the only way to look at or change a file is to send a subagent. deny, not ask:
# the human is never prompted; the model gets a reason and redirects, like guard-read.sh's gate.
#
# Layered: when the overlay does not fire, control returns to the sourcing guard so its own
# check still runs, main thread and subagent alike. The overlay never fires in a subagent
# (agent_id), and never on the deliverables scratch tree — agents write findings there and the
# orchestrator must read them back to verify delivery (CLAUDE.md's grep-the-file rule).
#
# Marker: ~/.claude/orchestrator-mode/<session_id>, contents = epoch expiry. Stale/corrupt
# markers are pruned on sight, so a dead session cannot gate a later one (S2) and a truncated
# or non-numeric expiry cannot wedge a session (S1). Fails OPEN: any inability to evaluate the
# mode (no jq, no date, no session_id) returns without gating, so ordinary work is never broken.
#
# Accepted classifier limits: command substitution $(…), find -exec / xargs fan-out, and a
# quoted '|' inside a pattern are not caught. The native Grep/Glob tools ARE gated (via the
# standalone hook). This shapes the cheap, common sinks; it is not a sandbox.

SCRATCH_PREFIX="/tmp/claude-1000/"
ORCH_DELIVERABLES="/tmp/claude-1000/orchestrator-deliverables"   # under SCRATCH_PREFIX (readable by the orchestrator)

# Shared with the SubagentStart/Stop deliverable hooks: is orchestrator mode live for a session,
# and where is a given subagent's deliverable. Same expiry semantics as the gate.
orchestrator_active() {
    local sid="$1" marker exp now
    marker="$HOME/.claude/orchestrator-mode/$sid"
    [ -f "$marker" ] || return 1
    now=$(date +%s 2>/dev/null); case "$now" in ''|*[!0-9]*) return 1 ;; esac
    exp=$(head -n1 "$marker" 2>/dev/null); case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
    [ "$exp" -gt "$now" ]
}
orchestrator_deliverable_path() { printf '%s/%s/%s.md' "$ORCH_DELIVERABLES" "$1" "$2"; }

_orch_deny() {
    local tool="$1" reason
    reason="Orchestrator mode is ON: ${tool} on the main thread is gated to keep the orchestrating context lean. Delegate to a subagent — recon reads/greps freely, edits run in an Agent — and have it write findings under ${SCRATCH_PREFIX} then return <=10 lines. The orchestrator may read/grep deliverables under ${SCRATCH_PREFIX}. To work inline, the human runs /orchestrate off."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(printf '%s' "$reason" | jq -R -s '.')"
    exit 0
}

_orch_is_scratch() { case "$1" in "$SCRATCH_PREFIX"*) return 0 ;; *) return 1 ;; esac; }

# git's real subcommand, past global options (-C path, -c k=v, --git-dir=…, --no-pager, -p…).
# Without this, `git -C <dir> show` — the invocation form CLAUDE.md tells sessions to prefer —
# walks straight past a `git show*` prefix match. (B1)
_orch_git_subcmd() {
    local rest="$1" tok
    set -- $rest
    shift
    while [ $# -gt 0 ]; do
        tok="$1"
        case "$tok" in
            -C|-c|--git-dir|--work-tree|--namespace|--exec-path) shift 2; continue ;;
            --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|-c=*) shift; continue ;;
            --no-pager|--paginate|-p|--bare|--no-replace-objects|--literal-pathspecs|--no-optional-locks) shift; continue ;;
            -*) shift; continue ;;
            *) printf '%s' "$tok"; return 0 ;;
        esac
    done
    return 1
}

# True if any simple-command in a Bash string dumps content into context. Tunable knob.
_orch_bash_is_heavy() {
    local cmd="$1" cseg seg h tok nonflag sub t
    [ -n "$cmd" ] || return 1

    # Deliverables channel: anything touching the scratch tree is an intentional, thin read of
    # an agent's own output, never a source-tree sink. (B5)
    case "$cmd" in *"$SCRATCH_PREFIX"*) return 1 ;; esac

    # Split on command separators only, NOT single '|' — each result is one command. (B4)
    while IFS= read -r cseg; do
        seg="${cseg%%|*}"                        # only a pipeline's HEAD opens files; rest filter
        t="${seg//2>/ }"; t="${t//&>/ }"; t="${t//>&/ }"
        case "$t" in *">"*) continue ;; esac     # stdout redirected to disk => not a context sink
        seg="${seg#"${seg%%[![:space:]]*}"}"
        while :; do                              # strip wrappers / env= / block keywords
            case "$seg" in
                sudo\ *|env\ *|command\ *|nohup\ *|time\ *|do\ *|then\ *|else\ *|[A-Za-z_]*=*\ *)
                    seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
                *) break ;;
            esac
        done
        h="${seg%% *}"
        case "$h" in
            rg|ag) return 0 ;;
            cat|head|tail|less|more|bat|nl)
                for tok in $seg; do [ "$tok" = "$h" ] && continue; case "$tok" in -*) ;; *) return 0 ;; esac; done ;;
            sed|awk|jq|diff)                     # heavy only with a FILE operand (bare = pipe filter)
                nonflag=0
                for tok in $seg; do [ "$tok" = "$h" ] && continue; case "$tok" in -*) ;; *) nonflag=$((nonflag + 1)) ;; esac; done
                [ "$nonflag" -ge 2 ] && return 0 ;;
            grep|egrep|fgrep)
                nonflag=0
                case " $seg " in *--recursive*|*--include*) return 0 ;; esac
                for tok in $seg; do
                    [ "$tok" = "$h" ] && continue
                    case "$tok" in -[!-]*[rR]*|-[rR]|--recursive) return 0 ;; -*) ;; *) nonflag=$((nonflag + 1)) ;; esac
                done
                [ "$nonflag" -ge 2 ] && return 0 ;;
            gh)  case "$seg" in *" pr diff"*) return 0 ;; esac ;;
            git)
                sub=$(_orch_git_subcmd "$seg") || sub=""
                case "$sub" in
                    show|blame|grep) return 0 ;;
                    diff)
                        case "$seg" in
                            *--stat*|*--numstat*|*--shortstat*|*--name-only*|*--name-status*|*--dirstat*) : ;;
                            *) return 0 ;;
                        esac ;;
                    log) case "$seg" in *\ -p*|*--patch*|*\ -G*|*\ -S*|*\ -u*) return 0 ;; esac ;;
                esac ;;
        esac
    done < <(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||;/\n/g')
    return 1
}

orchestrator_gate() {
    local payload="$1" dir f have now exp any_live sid tool cmd fp
    dir="$HOME/.claude/orchestrator-mode"

    # Fast path, no jq/date: empty or absent dir => mode off for every session.
    [ -d "$dir" ] || return 0
    have=
    for f in "$dir"/*; do [ -e "$f" ] && { have=1; break; }; done
    [ -n "$have" ] || return 0

    now=$(date +%s 2>/dev/null); case "$now" in ''|*[!0-9]*) return 0 ;; esac  # fail open

    # Prune stale/corrupt markers (self-healing); live == a future numeric expiry. (S1, S2)
    any_live=
    for f in "$dir"/*; do
        [ -e "$f" ] || continue
        exp=$(head -n1 "$f" 2>/dev/null); case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
        if [ "$exp" -gt "$now" ]; then any_live=1; else rm -f "$f" 2>/dev/null; fi
    done
    [ -n "$any_live" ] || return 0

    command -v jq >/dev/null 2>&1 || return 0                                  # fail open

    # R3: never overlay a subagent. agent_id is present only inside subagents.
    [ -n "$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null)" ] && return 0

    sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$sid" ] || return 0
    [ -f "$dir/$sid" ] || return 0                                             # this session not gated

    tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
    case "$tool" in
        Read)
            fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
            _orch_is_scratch "$fp" && return 0
            _orch_deny "Read" ;;
        Edit|Write|NotebookEdit)
            fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
            _orch_is_scratch "$fp" && return 0
            _orch_deny "$tool" ;;
        Grep|Glob)
            fp=$(printf '%s' "$payload" | jq -r '.tool_input.path // empty' 2>/dev/null)
            _orch_is_scratch "$fp" && return 0
            _orch_deny "$tool" ;;
        Bash)
            cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
            _orch_bash_is_heavy "$cmd" && _orch_deny "Bash" ;;
    esac
    return 0
}

# Executed directly (not sourced): the PreToolUse hook for Grep|Glob. Sourced by a guard:
# BASH_SOURCE[0] != $0, so this is skipped and only the functions are defined.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    orchestrator_gate "$(cat)"
fi
