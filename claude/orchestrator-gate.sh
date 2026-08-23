#!/usr/bin/env bash
# Sourced by guard-read.sh / guard-bash.sh / guard-publish.sh. Defines
# orchestrator_gate, an overlay that — while a session is in orchestrator mode —
# denies main-thread tool calls that would pull file/diff/tree CONTENT into the
# orchestrating context, so the only way to look at or change a file is to send a
# subagent. It is deny, not ask: the human is never prompted, the model is handed
# a reason and redirects itself, exactly like guard-read.sh's image gate.
#
# Layered, not replacing: when the overlay does not fire, control returns to the
# sourcing guard so its own check (image size / merge gate / secret scan) still
# runs — for the main thread AND for subagents. The overlay itself never fires in
# a subagent (agent_id), so the very agents doing the delegated work are untouched.
#
# Mode marker: ~/.claude/orchestrator-mode/<session_id>, contents = epoch expiry.
# Set/cleared by orchestrator-toggle.sh (the /orchestrate command); expiry and
# orchestrator-cleanup.sh (SessionEnd) both guard against a stale marker gating a
# later session. Marker dir is a real path, never the published dotfiles tree.
#
# Fails OPEN by design: any inability to evaluate the mode (no jq, no session_id)
# returns without gating, so this productivity overlay can never break ordinary
# work — unlike the guards it rides on, which fail closed.

# Print a deny decision naming the delegate path, then exit the whole hook.
_orch_deny() {
    local tool="$1" reason
    reason="Orchestrator mode is ON: ${tool} on the main thread is gated to keep the orchestrating context lean. Delegate this — Explore/Agent subagent for read-only recon, Agent (code-monkey) for edits. The subagent reads and edits freely and returns a thin summary; write findings to a file, return <=10 lines. To work inline instead, the human runs /orchestrate off."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(printf '%s' "$reason" | jq -R -s '.')"
    exit 0
}

# True if any simple-command in a Bash string dumps content into context. This is
# the tunable knob: it targets the unambiguous sinks (git show/diff/log -p/blame,
# codebase searchers, file readers with a path) and deliberately spares thin
# status commands and pipe-filters. Split mirrors guard-bash.sh.
_orch_bash_is_heavy() {
    local cmd="$1" seg h tok nonflag
    [ -n "$cmd" ] || return 1
    while IFS= read -r seg; do
        seg="${seg#"${seg%%[![:space:]]*}"}"                     # trim leading ws
        while :; do                                              # strip wrappers/env=
            case "$seg" in
                sudo\ *|env\ *|command\ *|nohup\ *|time\ *|[A-Za-z_]*=*\ *)
                    seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
                *) break ;;
            esac
        done
        h="${seg%% *}"
        case "$h" in
            rg|ag)                    return 0 ;;                 # codebase searchers
            cat|head|tail|less|more|bat|nl|sed|awk)
                for tok in $seg; do                              # heavy iff a path arg
                    [ "$tok" = "$h" ] && continue
                    case "$tok" in -*) ;; *) return 0 ;; esac
                done ;;
            grep|egrep|fgrep)
                nonflag=0
                case " $seg " in *--recursive*|*--include*) return 0 ;; esac
                for tok in $seg; do
                    [ "$tok" = "$h" ] && continue
                    case "$tok" in
                        -[!-]*[rR]*|-[rR]|--recursive) return 0 ;;   # tree search
                        -*) ;;
                        *) nonflag=$((nonflag + 1)) ;;               # pattern, then file
                    esac
                done
                [ "$nonflag" -ge 2 ] && return 0 ;;
            git)
                case "$seg" in
                    git\ show*|git\ blame*|git\ grep*) return 0 ;;
                    git\ diff*)
                        case "$seg" in
                            *--stat*|*--numstat*|*--shortstat*|*--name-only*|*--name-status*|*--dirstat*) : ;;
                            *) return 0 ;;
                        esac ;;
                    git\ log*)
                        case "$seg" in *\ -p*|*--patch*|*\ -G*|*\ -S*|*\ -u*) return 0 ;; esac ;;
                esac ;;
        esac
    done < <(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||;|\|/\n/g')
    return 1
}

orchestrator_gate() {
    local payload="$1" dir f sid marker now exp tool cmd
    dir="$HOME/.claude/orchestrator-mode"

    # Fast path, no jq: if no marker exists anywhere, mode is off for every
    # session and every ordinary tool call pays only this one stat.
    [ -d "$dir" ] || return 0
    for f in "$dir"/*; do [ -e "$f" ] && break || return 0; done

    command -v jq >/dev/null 2>&1 || return 0                    # can't evaluate -> open

    # R3: never overlay a subagent. agent_id is present only inside subagents;
    # the transcript-path shape is a documented-as-implementation secondary check.
    [ -n "$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null)" ] && return 0
    case "$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)" in
        */subagents/agent-*) return 0 ;;
    esac

    sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$sid" ] || return 0
    marker="$dir/$sid"
    [ -f "$marker" ] || return 0                                 # this session: mode off

    now=$(date +%s 2>/dev/null)
    exp=$(head -n1 "$marker" 2>/dev/null)
    case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
    if [ -n "$now" ] && [ "$exp" -gt 0 ] && [ "$now" -ge "$exp" ]; then
        rm -f "$marker" 2>/dev/null                             # expired -> clear, don't gate
        return 0
    fi

    tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
    case "$tool" in
        Read|Edit|Write|NotebookEdit) _orch_deny "$tool" ;;
        Bash)
            cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
            _orch_bash_is_heavy "$cmd" && _orch_deny "Bash" ;;
    esac
    return 0
}
