# Sourced by both bash/bashrc and zsh/zshrc, so it must stay POSIX sh.
#
# Every block here is guarded on the capability it needs, never on the host
# name. The two machines genuinely differ — the laptop has a graphical askpass
# and gh, the WSL box has neither — and testing for the thing rather than the
# box is what lets this file be byte-identical on both.

# Guarded, because nested shells (tmux, subshells, editors, Claude Code) re-run
# this over an already-populated PATH and would stack duplicates. Same idiom as
# /etc/profile.d/home-local-bin.sh, which prepends before this runs — so
# skipping is safe, the entry is already ahead of the system directories.
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

case ":${PATH}:" in
  *":${HOME}/.asdf/shims:"*) ;;
  *) export PATH="${HOME}/.asdf/shims:${PATH}" ;;
esac

# ssh consults this only when no tty is attached, so interactive shells keep
# prompting inline; sudo only under `sudo -A`. Covers the tty-less callers
# (Claude Code, .desktop launchers) that otherwise hit the absent
# /usr/lib/ssh/ssh-askpass. The script is deliberately not tracked in this repo,
# so the -x test is also what makes the whole block a no-op on a host with no
# graphical session to put a prompt on.
if [ -x "${HOME}/.local/bin/zenity-askpass" ]; then
  export SSH_ASKPASS="${HOME}/.local/bin/zenity-askpass"
  export SUDO_ASKPASS="${SSH_ASKPASS}"
fi

# A dedicated PAT for Claude Code's GitHub access, kept independent of the
# deployment token. Rotate by overwriting the file; a host without it gets an
# empty value, which the next block treats as "no gh auth to do".
export GITHUB_MCP_PAT="$(cat "${HOME}/.claude_github_token" 2>/dev/null)"

# Log gh in with the same PAT, so it is authenticated in every shell without a
# second copy of the token. Gated on gh existing as well as on the token, or a
# host without it prints "command not found" once per shell.
if [ -n "${GITHUB_MCP_PAT}" ] && [ -z "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  export GH_TOKEN="${GITHUB_MCP_PAT}"
  echo "${GH_TOKEN}" | gh auth login --with-token
fi

# Resolved rather than hardcoded to /usr/bin/vim: the path differs per host, and
# where vim is absent EDITOR is left as the system set it rather than pointed at
# something that will not run. ranger's rifle opens text files with
# ${VISUAL:-$EDITOR}, which is what makes this ranger's editor setting.
if _vim="$(command -v vim 2>/dev/null)"; then
  export EDITOR="${_vim}" VISUAL="${_vim}"
fi
unset _vim

# The sync timer is silent on success; this is how a failure reaches you.
if [ -f "${HOME}/.dotfiles-sync-failed" ]; then
  printf '\033[33mdotfiles sync failed:\033[0m %s\n' "$(cat "${HOME}/.dotfiles-sync-failed")"
fi
