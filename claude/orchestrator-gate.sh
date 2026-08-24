#!/usr/bin/env bash
# Sourced by guard-read.sh / guard-bash.sh / guard-publish.sh, AND run standalone as the
# PreToolUse hook for Grep|Glob. Defines orchestrator_gate: while a session is in orchestrator
# mode, deny main-thread tool calls that pull file/diff/tree CONTENT into the orchestrating
# context, so the only way to look at or change a file is to send a subagent. deny, not ask:
# the human is never prompted; the model gets a reason and redirects, like guard-read.sh's gate.
#
# Layered: when the overlay does not fire, control returns to the sourcing guard so its own
# check still runs, main thread and subagent alike. The overlay never fires in a subagent
# (agent_id), and never on the deliverables scratch tree (see the scratch exemption below).
#
# Marker: ~/.claude/orchestrator-mode/<session_id>, contents = epoch expiry. Corrupt markers are
# pruned always and expired ones when the clock is readable, so a dead session cannot gate a
# later one (S2) and a truncated expiry cannot wedge a session (S1). Fails OPEN: any inability to
# evaluate the mode returns without gating.
#
# The Bash classifier catches the common, reflexive sinks; it is NOT a sandbox. A determined
# bypass through shell features it does not parse — command substitution $(…), `eval`, `xargs`,
# `find -exec`, a pattern split by an unquoted-looking `|`, a base64'd path — can still get
# content through. It is a habit gate for an LLM orchestrator, not a security boundary.

SCRATCH_PREFIX="/tmp/claude-1000/"
ORCH_DELIVERABLES="/tmp/claude-1000/orchestrator-deliverables"

# Single liveness predicate (shared with the deliverable hooks): marker exists with a future
# numeric expiry. Returns 1 (not live) when the clock is unreadable — callers then fail open.
_orch_marker_live() {
    local f="$1" exp now
    [ -f "$f" ] || return 1
    now=$(date +%s 2>/dev/null); case "$now" in ''|*[!0-9]*) return 1 ;; esac
    exp=$(head -n1 "$f" 2>/dev/null); case "$exp" in ''|*[!0-9]*) return 1 ;; esac
    [ "$exp" -gt "$now" ]
}
orchestrator_active() { _orch_marker_live "$HOME/.claude/orchestrator-mode/$1"; }
orchestrator_deliverable_path() { printf '%s/%s/%s.md' "$ORCH_DELIVERABLES" "$1" "$2"; }

_orch_deny() {
    local tool="$1" reason
    reason="Orchestrator mode is ON: ${tool} on the main thread is gated to keep the orchestrating context lean. Delegate to a subagent — recon reads/greps freely, edits run in an Agent — and have it write findings under ${SCRATCH_PREFIX} then return <=10 lines. The orchestrator may read/grep deliverables under ${SCRATCH_PREFIX}. To work inline, the human runs /orchestrate off."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(printf '%s' "$reason" | jq -R -s '.')"
    exit 0
}

_orch_is_scratch() { case "$1" in "$SCRATCH_PREFIX"*) return 0 ;; *) return 1 ;; esac; }
_orch_looks_like_file() { case "$1" in -*|'<'*|'>'*) return 1 ;; */*|?*.?*) return 0 ;; *) return 1 ;; esac; }

# A single Bash segment is exempt only when it names a scratch path AND no path outside scratch —
# so `cat <scratch>/x && git show HEAD` no longer slips (that splits into two segments). (NB1)
_orch_seg_scratch_only() {
    local tok saw=
    for tok in $1; do
        case "$tok" in
            "$SCRATCH_PREFIX"*) saw=1 ;;
            -*|'<'*|'>'*) ;;
            */*|/*|?*.?*) return 1 ;;
        esac
    done
    [ -n "$saw" ]
}

# git's real subcommand, past global options. Guarded against a trailing option-with-argument so
# `git -C` (empty var) cannot spin the loop. (B1, NS1)
_orch_git_subcmd() {
    local rest="$1" tok
    set -- $rest; shift
    while [ $# -gt 0 ]; do
        tok="$1"
        case "$tok" in
            -C|-c|--git-dir|--work-tree|--namespace|--exec-path)
                [ $# -ge 2 ] || return 1; shift 2; continue ;;
            --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*)
                shift; continue ;;
            --no-pager|--paginate|-p|--bare|--no-replace-objects|--literal-pathspecs|--no-optional-locks)
                shift; continue ;;
            -*) shift; continue ;;
            *) printf '%s' "$tok"; return 0 ;;
        esac
    done
    return 1
}

# True if any simple-command in a Bash string dumps content into context. Tunable knob.
_orch_bash_is_heavy() {
    local cmd="$1" seg h tok sub stripped first
    [ -n "$cmd" ] || return 1
    # Split on EVERY separator including a single '|' — each pipeline stage can open a file. (NB2)
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[![:space:]]*}"}"
        [ -n "$seg" ] || continue
        # Redirect detection: drop 2>> &>> 2> &> >& and quoted spans, then a remaining '>' means
        # stdout goes to a file — output to disk, not context. (NB3)
        stripped=$(printf '%s' "$seg" | sed -e 's/2>>//g' -e 's/&>>//g' -e 's/2>//g' -e 's/&>//g' -e 's/>&//g' -e "s/'[^']*'//g" -e 's/"[^"]*"//g')
        case "$stripped" in *">"*) continue ;; esac
        # Strip wrappers and a leading VAR=val assignment — first token only, so a mid-command
        # `--foo=bar` cannot chop the real command off. (NB4)
        while :; do
            case "$seg" in
                sudo\ *|env\ *|command\ *|nohup\ *|time\ *|do\ *|then\ *|else\ *)
                    seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
                *)
                    first="${seg%% *}"
                    case "$first" in
                        [A-Za-z_][A-Za-z0-9_]*=*) seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
                        *) break ;;
                    esac ;;
            esac
        done
        _orch_seg_scratch_only "$seg" && continue
        h="${seg%% *}"
        case "$h" in
            rg|ag) return 0 ;;
            cat|head|tail|less|more|bat|nl)                 # read files: any real operand
                for tok in $seg; do
                    [ "$tok" = "$h" ] && continue
                    case "$tok" in -*|'<'*|'>'*) ;; *) return 0 ;; esac
                done ;;
            sed|awk|jq|diff)                                # first operand is a script/pattern
                for tok in $seg; do
                    [ "$tok" = "$h" ] && continue
                    _orch_looks_like_file "$tok" && return 0
                done ;;
            grep|egrep|fgrep)
                case " $seg " in *" --recursive"*|*" --include"*) return 0 ;; esac
                for tok in $seg; do
                    [ "$tok" = "$h" ] && continue
                    case "$tok" in -[rR]*|-[!-]*[rR]*) return 0 ;; esac   # short cluster with r/R
                    _orch_looks_like_file "$tok" && return 0
                done ;;
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
    done < <(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||;|\|/\n/g')
    return 1
}

orchestrator_gate() {
    local payload="$1" dir f have now exp sid tool cmd fp
    dir="$HOME/.claude/orchestrator-mode"

    # Fast path, no jq/date: empty or absent dir => mode off for every session.
    [ -d "$dir" ] || return 0
    have=; for f in "$dir"/*; do [ -e "$f" ] && { have=1; break; }; done
    [ -n "$have" ] || return 0

    # Prune: corrupt markers always (S1); expired ones only when the clock is readable, so a
    # transient date failure never deletes a live marker. (S2)
    now=$(date +%s 2>/dev/null); case "$now" in ''|*[!0-9]*) now='' ;; esac
    for f in "$dir"/*; do
        [ -e "$f" ] || continue
        exp=$(head -n1 "$f" 2>/dev/null)
        case "$exp" in ''|*[!0-9]*) rm -f "$f" 2>/dev/null; continue ;; esac
        [ -n "$now" ] && [ "$exp" -le "$now" ] && rm -f "$f" 2>/dev/null
    done

    command -v jq >/dev/null 2>&1 || return 0                     # fail open

    # R3: never overlay a subagent. agent_id is present only inside subagents.
    [ -n "$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null)" ] && return 0

    sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$sid" ] || return 0
    orchestrator_active "$sid" || return 0                        # this session not gated (NS6)

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

# Executed directly (not sourced): the PreToolUse hook for Grep|Glob. Sourced by a guard,
# BASH_SOURCE[0] != $0, so only the functions are defined.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    orchestrator_gate "$(cat)"
fi
