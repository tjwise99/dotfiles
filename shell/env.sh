# Environment for every shell, interactive or not. Sourced by ~/.zshenv, which
# zsh reads for all shells, and by ~/.profile for the graphical session.
#
# Nothing here may write to stdout. `ssh host <command>` runs a non-interactive
# shell and its output is the command's output — a banner or a warning printed
# from this file lands in the caller's data. What prints belongs in
# shell/interactive.sh, which only ~/.zshrc reads.
#
# POSIX sh: ~/.profile is read by lightdm's Xsession, which is not zsh.
#
# Every block is guarded on the capability it needs, never on the host name,
# which is what lets this file be byte-identical on both machines. The guard
# must test the capability itself and not an artefact that usually accompanies
# it: see the askpass block, where "the helper has been installed" stood in for
# "there is a display" until a host had one and not the other.

# Move one directory to the front of PATH, removing it from wherever it already
# is. Removing before prepending is the point: it makes the call idempotent, so
# it can run again later, and authoritative, so the last caller decides.
#
# Written with parameter expansion rather than `for dir in ${PATH}` under
# IFS=":" because zsh does not word-split unquoted parameters — that loop reads
# the whole PATH as a single element here and as many elsewhere.
__wise_path_prefer() {
  [ -n "${1:-}" ] || return 0
  __wp_out=""
  __wp_rest="${PATH}:"
  while [ -n "${__wp_rest}" ]; do
    __wp_dir="${__wp_rest%%:*}"
    __wp_rest="${__wp_rest#*:}"
    [ -n "${__wp_dir}" ] || continue
    [ "${__wp_dir}" = "$1" ] && continue
    __wp_out="${__wp_out:+${__wp_out}:}${__wp_dir}"
  done
  PATH="$1${__wp_out:+:${__wp_out}}"
  export PATH
  unset __wp_out __wp_rest __wp_dir
}

# Home Manager's session variables, which is what puts ~/.nix-profile/bin on
# PATH at all — by way of the nix.sh it sources. Guarded on the file, so it
# skips where standalone Home Manager has not run: the WSL box, and NixOS, where
# the module form installs into /etc/profiles/per-user and the system already
# carries that. The script guards itself against being sourced twice.
if [ -f "${HOME}/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "${HOME}/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

# The front of PATH, most preferred first:
#
#   ~/bin                            hand-written scripts
#   ~/.nix-profile/bin               Home Manager, standalone form
#   /etc/profiles/per-user/<u>/bin   Home Manager, NixOS module form
#   ~/.asdf/shims                    language runtimes
#   ~/.local/bin                     pip and npm user installs
#
# Applied least-preferred first, because each call moves its argument to the
# front and so the last call wins.
#
# This used to be four guarded prepends, which made the order a property of who
# prepended last rather than a decision. Two things prepend after this file and
# neither is visible from it: Manjaro's nix package ships
# /etc/profile.d/nix-daemon.sh, which /etc/zsh/zprofile reaches through
# /etc/profile — after ~/.zshenv. So a login shell put Nix ahead of asdf and a
# non-interactive shell put asdf ahead of Nix, on the same machine, and NixOS
# ships no such file and disagreed with both. `ssh laptop just --version` and a
# terminal on that laptop ran different binaries, and nothing reported it.
#
# Nix ahead of asdf reverses what this file used to intend. The reason recorded
# for asdf-first was that asdf owns the runtime versions shared with the WSL
# box, but Nix packages none of those runtimes, so they never competed. What
# does overlap is the CLI tools moving into home.packages, and there Nix is the
# destination.
__wise_path_apply() {
  __wise_path_prefer "${HOME}/.local/bin"
  __wise_path_prefer "${HOME}/.asdf/shims"

  # USER is unset under some launchers; LOGNAME and the home directory's own
  # name are the fallbacks. Guarded on the directory, so a wrong guess adds
  # nothing rather than adding a path that does not exist.
  __wp_peruser="/etc/profiles/per-user/${USER:-${LOGNAME:-${HOME##*/}}}/bin"
  [ -d "${__wp_peruser}" ] && __wise_path_prefer "${__wp_peruser}"
  unset __wp_peruser

  [ -d "${HOME}/.nix-profile/bin" ] && __wise_path_prefer "${HOME}/.nix-profile/bin"
  [ -d "${HOME}/bin" ] && __wise_path_prefer "${HOME}/bin"
  return 0
}

__wise_path_apply

# ssh consults this only when no tty is attached, so interactive shells keep
# prompting inline; sudo only under `sudo -A`. Covers the tty-less callers
# (Claude Code, .desktop launchers) that otherwise hit the absent
# /usr/lib/ssh/ssh-askpass.
#
# Guarded on the capability, not on the helper's presence. Testing whether the
# script had been installed measured "did someone put it here by hand", which is
# a proxy for having a display and stands in for it only until it doesn't: this
# is what left the WSL box exporting a path that did not exist. A display is
# also ssh's own condition for consulting SSH_ASKPASS, and its absence is what
# correctly disarms this under cron, a systemd unit, or ssh without forwarding.
if command -v zenity >/dev/null 2>&1 && [ -n "${DISPLAY}${WAYLAND_DISPLAY}" ]; then
  export SSH_ASKPASS="${HOME}/dotfiles/bin/zenity-askpass"
  export SUDO_ASKPASS="${SSH_ASKPASS}"
fi

# gh keeps its token in the system keyring, so nothing on disk holds it. Lift it
# into the environment for scripts that read GH_TOKEN directly rather than
# shelling out to gh — WiseKiosk's check-branch gate calls the API with curl.
# An empty result is not exported, or the gate reads a set-but-blank token.
#
# Here rather than in the interactive half precisely because those callers are
# scripts. The emptiness guard also keeps the cost to one `gh` spawn per shell
# tree: a child inherits the export and skips the block.
if [ -z "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  gh_token="$(gh auth token 2>/dev/null)"
  [ -n "${gh_token}" ] && export GH_TOKEN="${gh_token}"
  unset gh_token
fi

# Resolved rather than hardcoded to /usr/bin/vim: the path differs per host, and
# where vim is absent EDITOR is left as the system set it rather than pointed at
# something that will not run. ranger's rifle opens text files with
# ${VISUAL:-$EDITOR}, which is what makes this ranger's editor setting.
if _vim="$(command -v vim 2>/dev/null)"; then
  export EDITOR="${_vim}" VISUAL="${_vim}"
fi
unset _vim
