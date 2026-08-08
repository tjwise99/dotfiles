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

# --------------------------------------------------------- shell behaviour --
#
# Aliases and functions live here rather than in one rc file, so the shell
# behaves the same on both hosts. Anything needing X is in zsh/zshrc.x, which
# only the laptop deploys.

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias dirsize='sudo du -hc . | sort -rh | head -20'

# Leave the shell in whatever directory ranger quit from. --choosedir writes the
# final path to a temp file; `command` avoids recursing into this function.
# Written without `local`, which this file's POSIX constraint does not have.
ranger() {
  _rgr_tmp="$(mktemp -t ranger-cd.XXXXXX)" || return 1
  command ranger --choosedir="${_rgr_tmp}" -- "${@:-${PWD}}"
  if [ -f "${_rgr_tmp}" ]; then
    _rgr_dest="$(cat -- "${_rgr_tmp}")"
    if [ -n "${_rgr_dest}" ] && [ -d "${_rgr_dest}" ] && [ "${_rgr_dest}" != "${PWD}" ]; then
      cd -- "${_rgr_dest}" || :
    fi
  fi
  rm -f -- "${_rgr_tmp}"
  unset _rgr_tmp _rgr_dest
}

# ------------------------------------------------------------ sync health --
#
# Two signals, because they fail differently. The marker means a run happened
# and failed. The stamp means a run happened at all — and its absence is the
# only thing that can report a host where the timer never fires, which is WSL
# whenever /etc/wsl.conf has not turned systemd on. That host writes no marker
# precisely because nothing runs to write one, so a report built on the marker
# alone describes a healthy machine that has never once backed up.

if [ -f "${HOME}/.dotfiles-sync-failed" ]; then
  printf '\033[33mdotfiles sync failed:\033[0m %s\n' "$(cat "${HOME}/.dotfiles-sync-failed")"
fi

if [ ! -f "${HOME}/.dotfiles-sync-stamp" ]; then
  printf '\033[33mdotfiles sync has never run on this host\033[0m (see README, Sync)\n'
elif [ -n "$(find "${HOME}/.dotfiles-sync-stamp" -mmin +1440 2>/dev/null)" ]; then
  printf '\033[33mdotfiles sync last ran %s\033[0m\n' \
    "$(date -r "${HOME}/.dotfiles-sync-stamp" '+%Y-%m-%d %H:%M')"
fi
