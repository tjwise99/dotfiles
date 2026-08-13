#!/usr/bin/env bash
# PreToolUse hook on Edit|Write. Everything under ~/dotfiles is pushed to a
# public repo within 20 minutes, and the gitleaks pre-commit hook only catches
# credential-shaped strings. The actual exposure is network-shaped detail — a
# MAC, an internal subnet, an SSID, a PSK — which is not secret-shaped, so
# nothing blocks it, and together it fingerprints a home or office network.
#
# Decision is `ask`, not `deny`: these are heuristics, and a legal write that a
# gate refuses with no override is a worse failure than one that asks. A prompt
# still cannot be walked past silently, which is the whole point.
set -u

payload=$(cat)

field() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r "$1 // \"\"" 2>/dev/null && return
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$payload" | python3 -c "import json,sys
p='''$2'''
try:
    d=json.load(sys.stdin).get('tool_input',{})
    print(''.join(str(d.get(k,'')) for k in p.split(',')))
except Exception: print('')" 2>/dev/null && return
    fi
    printf ''
}

path=$(field '.tool_input.file_path' 'file_path')
[ -n "$path" ] || exit 0

# Only guards the published tree. Resolve, because ~/.claude/* are symlinks into it.
real=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
dotfiles=$(readlink -f "$HOME/dotfiles" 2>/dev/null || printf '%s' "$HOME/dotfiles")
case "$real" in
    "$dotfiles"/*) ;;
    *) exit 0 ;;
esac

body=$(field '(.tool_input.content // "") + (.tool_input.new_string // "")' 'content,new_string')
[ -n "$body" ] || exit 0

hits=""
add() { hits="${hits}${hits:+; }$1"; }

# grep -c, never -q: under pipefail a -q match kills the producer with SIGPIPE.
count() { printf '%s' "$body" | /usr/bin/grep -cEi "$1" 2>/dev/null || true; }

[ "$(count '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b')" != "0" ] && add "MAC address"
[ "$(count '\b(10\.[0-9]{1,3}|192\.168|169\.254|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b')" != "0" ] && add "private/link-local IP"
[ "$(count '\b(ssid|psk|wpa_passphrase|pre-shared)\b[[:space:]]*[:=]')" != "0" ] && add "wireless network identifier"

[ -n "$hits" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s -> PUBLIC repo (auto-pushed within 20 min). Content matches: %s. Confirm this is generic (\\"a LAN host\\", \\"a wall-mounted Pi kiosk\\") and not real network detail."}}\n' \
    "${real#$HOME/}" "$hits"
exit 0
