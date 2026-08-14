#!/usr/bin/env bash
# Grant / revoke ahead-of-time authorization for `gh pr merge`, read by
# guard-bash.sh. Writes ~/.claude/merge-auth — outside ~/dotfiles, so it is
# never published, and it carries an expiry so a forgotten grant lapses on its
# own. Run it yourself with `! claude/merge-authorize.sh …`, or tell a session
# to, when you want an unattended merge to land without a live prompt.
#
#   merge-authorize.sh [--pr N] [--admin] [--hours H]   grant (default: any PR, 12h)
#   merge-authorize.sh --revoke                          delete the grant
#   merge-authorize.sh --show                            print the active grant
#
# Scope it (--pr N) unless you truly mean "merge whatever is ready". --admin is
# required for a branch-protection bypass; a plain grant will not authorize one.
set -eu

auth="$HOME/.claude/merge-auth"
pr=""; admin=0; hours=12; action=grant

while [ $# -gt 0 ]; do
    case "$1" in
        --pr)     pr="${2:?--pr needs a number}"; shift 2 ;;
        --admin)  admin=1; shift ;;
        --hours)  hours="${2:?--hours needs a number}"; shift 2 ;;
        --revoke) action=revoke; shift ;;
        --show)   action=show; shift ;;
        -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

case "$action" in
    revoke)
        rm -f "$auth"
        echo "merge-auth revoked"
        ;;
    show)
        if [ -f "$auth" ]; then cat "$auth"; else echo "no active merge-auth"; fi
        ;;
    grant)
        case "$pr" in ''|*[!0-9]*) [ -z "$pr" ] || { echo "--pr must be a number" >&2; exit 2; } ;; esac
        case "$hours" in ''|*[!0-9]*) echo "--hours must be a number" >&2; exit 2 ;; esac
        expires=$(date -d "+${hours} hours" +%s)
        mkdir -p "$(dirname "$auth")"
        { printf 'pr=%s\n' "$pr"; printf 'admin=%s\n' "$admin"; printf 'expires=%s\n' "$expires"; } > "$auth"
        printf 'merge-auth granted: pr=%s admin=%s expires=%s (%sh)\n' \
            "${pr:-<any>}" "$admin" "$(date -d "@$expires" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$expires")" "$hours"
        ;;
esac
