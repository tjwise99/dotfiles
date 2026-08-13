# Interactive-shell behaviour: aliases, wrappers, and the reports that print at
# a new prompt. Sourced by ~/.zshrc alone.
#
# The split from shell/env.sh is what makes printing safe here. zsh reads
# ~/.zshenv for every shell including the one behind `ssh host <command>`, where
# anything written to stdout is prepended to the caller's data; it reads
# ~/.zshrc only when interactive.
#
# Kept out of zsh/zshrc so the file stays about zsh — keymap, completion,
# prompt — rather than about this machine's habits.

# Re-assert the PATH order from shell/env.sh: ~/.zshrc is the only stage that
# runs after /etc/profile, which the distro's Nix packaging prepends to. First,
# because the `command -v` guards below ask PATH what they resolve to.
command -v __wise_path_apply >/dev/null 2>&1 && __wise_path_apply

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias dirsize='sudo du -hc . | sort -rh | head -20'

# Guarded for the same reason shell/env.sh guards EDITOR: nvim arrives from asdf,
# so on a host that has not finished ./install it is absent, and an unguarded
# alias would take `vim` down with it rather than falling back to the vim that is
# there. EDITOR stays on vim deliberately — an alias reaches this shell only, so
# pointing git, ranger and sudoedit at nvim is a separate decision from this one.
command -v nvim >/dev/null 2>&1 && alias vim='nvim'

# zoxide takes over `cd` rather than adding a second `z` command. That is what
# makes it learn anything: the database is only fed by the command already being
# typed, and a `z` kept alongside `cd` mostly gets forgotten.
#
# The cost is that `cd` stops failing on a bad argument. Given a name that is not
# an existing path it consults the database instead, so a typo becomes a jump
# somewhere plausible rather than an error. `cd ./thing` and `cd ../thing` are
# unchanged — a path-shaped argument is still just a path.
#
# Skipped under Claude Code, following upstream. It does not cover the Bash tool,
# which reads no startup file at all, but it does cover an interactive zsh opened
# inside a session — where a silent jump lands in an agent's hands rather than in
# front of someone who can see it happen.
if command -v zoxide >/dev/null 2>&1 && [ "${CLAUDECODE:-}" != "1" ]; then
  eval "$(zoxide init --cmd cd zsh)"
fi

# Leave the shell in whatever directory ranger quit from. --choosedir writes the
# final path to a temp file; `command` avoids recursing into this function.
ranger() {
  local tmp dest
  tmp="$(mktemp -t ranger-cd.XXXXXX)" || return 1
  command ranger --choosedir="${tmp}" -- "${@:-${PWD}}"
  if [ -f "${tmp}" ]; then
    dest="$(cat -- "${tmp}")"
    if [ -n "${dest}" ] && [ -d "${dest}" ] && [ "${dest}" != "${PWD}" ]; then
      cd -- "${dest}" || :
    fi
  fi
  rm -f -- "${tmp}"
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
