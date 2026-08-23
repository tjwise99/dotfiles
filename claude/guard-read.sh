#!/usr/bin/env bash
# PreToolUse hook on Read. Oversized images are the single largest context sink
# measured across this machine's transcripts: 26 image reads accounted for 54%
# of all tool-result context ever, averaging ~84k tokens each against ~273 for
# every other kind of call. One of them cost 166k tokens in a single result.
#
# Denies rather than asks, because the remedy is automatic and lossless: the
# model downscales and re-reads without involving anyone. 1568px is the long
# edge beyond which the vision encoder gains nothing, so shrinking to it throws
# away cost, not detail.
set -u

payload=$(cat)

# Orchestrator-mode overlay (main thread only; inert unless /orchestrate is ON).
. "$HOME/dotfiles/claude/orchestrator-gate.sh"
orchestrator_gate "$payload"

path=""
if command -v jq >/dev/null 2>&1; then
    path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
    path=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))
except Exception: print("")' 2>/dev/null)
fi
[ -n "$path" ] && [ -f "$path" ] || exit 0

case "${path,,}" in
    *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.tif|*.tiff|*.gif) ;;
    *) exit 0 ;;
esac

bytes=$(stat -c %s "$path" 2>/dev/null || echo 0)

edge=0
if command -v magick >/dev/null 2>&1; then
    edge=$(magick identify -format '%[fx:max(w,h)]' "$path"[0] 2>/dev/null || echo 0)
fi
[ -n "$edge" ] || edge=0

# Canvas is the real cost driver, so where magick can measure it that answer is
# final — including when it says the image is already small. Byte size is only a
# stand-in for hosts without magick. Checking both would reject the very file
# this hook's own remedy produces, since a downscaled PNG of a dense image stays
# large on disk; the guard would then deny its own fix forever.
if [ "$edge" -gt 0 ]; then
    [ "$edge" -le 1600 ] && exit 0
elif [ "$bytes" -le 800000 ]; then
    exit 0
fi

small="/tmp/claude-1000/downscaled-$(basename "${path%.*}").jpg"
reason="$(basename "$path") is $((bytes/1024))KB, long edge ${edge}px. Images this size have cost ~150k tokens each on this machine. Downscale first — the vision encoder gains nothing past 1568px, so this loses no detail: magick '$path' -resize '1568x1568>' -quality 85 '$small' && read '$small' instead."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$reason" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"Image too large to read directly; downscale to 1568px first."')"
exit 0
