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

# Guarded, because nested shells (tmux, subshells, editors, Claude Code) re-run
# this over an already-populated PATH and would stack duplicates. Same idiom as
# /etc/profile.d/home-local-bin.sh, which prepends before this runs — so
# skipping is safe, the entry is already ahead of the system directories.
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

# Home Manager's session variables, which is what puts ~/.nix-profile/bin on
# PATH at all — by way of the nix.sh it sources. Guarded on the file, so it
# skips where standalone Home Manager has not run: the WSL box, and NixOS, where
# the module form installs into /etc/profiles/per-user and the system already
# carries that. The script guards itself against being sourced twice.
#
# Ahead of the asdf block on purpose. Both prepend, so whichever runs last ends
# up first, and asdf owns the runtime versions this host shares with WSL.
if [ -f "${HOME}/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "${HOME}/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

case ":${PATH}:" in
  *":${HOME}/.asdf/shims:"*) ;;
  *) export PATH="${HOME}/.asdf/shims:${PATH}" ;;
esac

if [ -d "${HOME}/bin" ]; then
  case ":${PATH}:" in
    *":${HOME}/bin:"*) ;;
    *) export PATH="${HOME}/bin:${PATH}" ;;
  esac
fi

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
