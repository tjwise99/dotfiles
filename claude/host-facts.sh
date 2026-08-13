#!/usr/bin/env bash
# SessionStart hook. Emits what is actually true of the machine running this
# session, so CLAUDE.md can state invariants and never per-host facts.
#
# Output is the SessionStart additionalContext JSON envelope, built with bash
# parameter expansion rather than jq — jq is one of the tools this very script
# exists to report as possibly absent.
#
# grep -c rather than grep -q throughout: under `set -o pipefail` a -q match
# kills the producer with SIGPIPE and returns 141, inverting the test.
set -u

export PATH="${HOME}/.nix-profile/bin:${HOME}/.local/bin:${HOME}/.asdf/shims:${PATH}"

out=""
say() { out+="$1"$'\n'; }

origin() {
    case "$1" in
        "${HOME}"/.nix-profile/bin/*) printf 'nix' ;;
        /nix/store/*)                 printf 'nix-store' ;;
        "${HOME}"/.asdf/shims/*)      printf 'asdf' ;;
        "${HOME}"/.local/bin/*)       printf 'local' ;;
        /usr/bin/*|/bin/*)            printf 'system' ;;
        *)                            printf '%s' "${1%/*}" ;;
    esac
}

found=()
missing=()
for t in jq just gh gitleaks rg zenity python3 node docker; do
    if p=$(command -v "$t" 2>/dev/null); then
        found+=("${t}=$(origin "$p")")
    else
        missing+=("$t")
    fi
done

say "## Host facts — resolved at session start; authoritative over any host claim in CLAUDE.md"
say "shell=${SHELL##*/} tools: ${found[*]:-none}"
if [ ${#missing[@]} -gt 0 ]; then
    say "NOT INSTALLED HERE: ${missing[*]} — do not propose a plan that needs one"
fi

hosts_yml="${HOME}/.config/gh/hosts.yml"
# `grep -c || echo 0` emits two lines when grep prints 0 and also exits 1.
tok_lines=$(grep -c 'oauth_token:' "$hosts_yml" 2>/dev/null; true)
[ -n "$tok_lines" ] || tok_lines=0
if ! command -v gh >/dev/null 2>&1; then
    say "gh token: gh is not installed here"
elif [ "$tok_lines" -gt 0 ]; then
    say "gh token: PLAINTEXT in ~/.config/gh/hosts.yml — never cat it into a transcript"
else
    say "gh token: system keyring — nothing on disk holds it"
fi

if [ -n "${GH_TOKEN:-}" ]; then
    say "GH_TOKEN: set"
else
    say "GH_TOKEN: unset — scripts that call the API without gh will fail"
fi

if [ -f "${HOME}/.claude.json" ] && command -v jq >/dev/null 2>&1; then
    names=$(jq -r '(.mcpServers // {}) | keys | join(" ")' "${HOME}/.claude.json" 2>/dev/null || true)
    say "mcp servers: ${names:-none configured}"
fi

timer=$(systemctl --user is-active dotfiles-sync.timer 2>/dev/null || true)
if [ "$timer" = "active" ]; then
    say "dotfiles-sync.timer: ACTIVE — anything in ~/dotfiles is pushed PUBLIC within 20 min"
else
    say "dotfiles-sync.timer: ${timer:-absent} — ~/dotfiles is not auto-publishing right now"
fi

hooks_path=$(git config --global core.hooksPath 2>/dev/null || true)
if [ -n "$hooks_path" ] && [ -e "${hooks_path/#\~/$HOME}/pre-commit" ]; then
    say "gitleaks pre-commit: armed globally via core.hooksPath (a repo setting its own disables it)"
else
    say "gitleaks pre-commit: NOT ARMED — nothing scans staged credentials"
fi

esc=${out//\\/\\\\}
esc=${esc//\"/\\\"}
esc=${esc//$'\n'/\\n}
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
exit 0
