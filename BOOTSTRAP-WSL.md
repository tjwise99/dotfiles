# Bringing up a WSL box

The prerequisites that live on the Windows side, and the first-run order that
matters. Everything here was walked on Ubuntu 26.04; where a step exists because
something went wrong, the reason is written down rather than the fix alone.

## 1. Windows side, before anything in Linux

**systemd.** WSL boots without it unless told otherwise, and without it the sync
timer never fires. Check inside the distro:

```sh
systemctl --user show-environment >/dev/null 2>&1 && echo on || echo off
```

If off:

```sh
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
```

then from **Windows**: `wsl --shutdown`, and reopen the distro. This is a real
reboot of the VM, not a shell restart. `systemd/enable-timer.sh` prints this
same hint if it finds no user systemd instance, rather than exiting quietly — a
host with no timer writes no failure marker either, so silence there would mean
both "backed up fine" and "has never backed up".

**A Nerd Font.** The prompt is powerlevel10k and draws with glyphs outside
normal Unicode. Without one the prompt renders as boxes. The font is installed
on the *Windows* side — Ubuntu's font packages do nothing for Windows Terminal.
Install JetBrainsMono Nerd Font from nerdfonts.com, then set it in Windows
Terminal → Settings → your Ubuntu profile → Appearance → Font face.

## 2. Pre-flight the package names

The apt column of `packages/manifest.yaml` is the only part of this repo that
can be wrong in a way no other host would show, so check it before installing:

```sh
apt-cache policy $(python3 packages/resolve.py --native)
```

Any entry showing `Candidate: (none)` is a wrong name. Fix the `apt:` value, or
mark it `unavailable` with the reason; do not delete the entry, because
`resolve.py` treats a missing column as an error precisely so a package cannot
vanish silently from one host. All current names resolve on 26.04.

## 3. Clone

There is no SSH key on a fresh machine, so clone over HTTPS:

```sh
git clone --recursive https://github.com/tjwise99/dotfiles.git ~/dotfiles
```

`--recursive` matters: the prompt and the five zsh plugins are submodules. If it
was missed, `git submodule update --init --recursive`.

## 4. Baseline first, then install

`resolve.py --verify` refuses to run with no baseline for this host rather than
running half of what it claims to, and `sync-packages.sh` is the first step of
the install. Write the baseline first — on a fresh image that is exactly the
right moment, since everything explicitly installed is genuinely pre-existing:

```sh
python3 packages/resolve.py --write-baseline
./install --packages
```

`--packages` is not optional here. It is opt-in because it needs root, but asdf
compiles and downloads, so nothing after it succeeds without `build-essential`,
`curl` and `unzip`.

Expect this to take a while on a fresh box: it installs Rust and Go toolchains
and builds `gh-dash` and `gh-review` from pinned upstreams plus local patches.

## 5. Make zsh the login shell

**Do this in the same sitting as step 4, not later.** Bash is not configured by
this repo — there is no `~/.bashrc` — so between installing and switching, a
login shell gets only what `~/.profile` sets. That is enough to keep `PATH`
working and nothing else.

```sh
chsh -s "$(command -v zsh)"
```

Still manual, and still deliberately so: it needs a password, and switching to a
shell that will not start costs a trip to a TTY. Before running it, confirm all
three of the things that make it safe — that zsh runs, that it is a legal login
shell, and that you are not already on it:

```sh
zsh -c 'exit' && echo "zsh runs"
grep -qxF "$(command -v zsh)" /etc/shells && echo "listed in /etc/shells"
getent passwd "$USER" | cut -d: -f7
```

Then close the terminal and reopen it.

## 6. Nix and Home Manager

Tier 0 of `packages/manifest.yaml` lives in
[WiseOS](https://github.com/tjwise99/WiseOS), not here. Until this step runs,
the tools it owns have config deployed on this box and no binary behind it —
`ranger` and `htop` are the visible ones, since `profiles/base.conf.yaml` links
their config directories regardless.

Written from the laptop against Debian's packaging, not a running Ubuntu box.
Step 2's pre-flight is what confirms these names; the group below has no Arch
equivalent, so the laptop proves nothing about it.

`./install --packages` already installed `nix-bin` and `nix-setup-systemd`. Two
things the package does not do on its own:

```sh
sudo nix-store --init
printf 'experimental-features = nix-command flakes\n' | sudo tee -a /etc/nix/nix.conf
sudo systemctl enable --now nix-daemon.socket
```

Then the group gating the daemon socket, which Arch does not have — its socket
is mode `0666`:

```sh
getent group nix-users && sudo usermod -aG nix-users "$USER"
```

That takes effect on next login. Then:

```sh
git clone https://github.com/tjwise99/WiseOS.git ~/code/WiseOS
nix run home-manager/release-26.05 -- switch --flake ~/code/WiseOS#wsl
```

`#wsl` rather than `#wise`: both outputs come from one function taking the
username as its only argument, so an account that is not `wise` is a one-line
change in `WiseOS/flake.nix`.

## 7. Verify

```sh
python3 tools/check-manifest.py --deployed
./asdf/verify-tools.sh
python3 packages/resolve.py --verify
```

All three exit 0 on a correct machine. Then in a new terminal:

```sh
bindkey -lL main          # expect: bindkey -A viins main
echo $HISTFILE            # expect: ~/.zhistory
bindkey -M vicmd v        # expect: "v" edit-command-line
```

And the check that the login shell alone cannot make — that a *non-interactive*
zsh has the toolchain, which is what `~/.zshenv` exists for:

```sh
env -i HOME="$HOME" zsh -c 'command -v node'   # expect: ~/.asdf/shims/node
env -i HOME="$HOME" zsh -c 'command -v rg'     # expect: ~/.nix-profile/bin/rg
env -i HOME="$HOME" zsh -c 'printf DATA'       # expect: DATA, and nothing else
```

The first two are the tier boundary: asdf keeps the runtimes, Nix owns the CLI
tools, and a tool in both must answer Nix.

The third matters as much as either. `ssh host <command>` runs a
non-interactive shell whose stdout *is* the command's output, so anything
printed from `~/.zshenv` ends up prepended to the caller's data.

Last, the pair — the same tool answering the same way whichever shell asks:

```sh
env -i HOME="$HOME" zsh -c   'command -v jq'
env -i HOME="$HOME" zsh -lic 'command -v jq'
```

Either answer alone looks correct; only the pair catches `/etc/profile`
prepending after `~/.zshenv` has set the order.

## 8. Expected to differ from the laptop, correctly

- No `~/.config/zsh/x.zsh`, so no `fixWindows` or `clip` alias. That file is
  deployed by the manjaro profile alone and `zsh/zshrc` tests for it.
- No theme, i3, polybar or Xresources links. Tier 3 is X-only by design.
- History starts empty. `~/.zhistory` is per-machine and never synced.
- `gh` is unauthenticated until `gh auth login` is run here; `shell/env.sh`
  lifts the token out of the keyring and skips the block silently when there is
  none.
- `zenity` is installed on both hosts and backs `SUDO_ASKPASS`, but it only
  engages where a display exists. Under WSL that is WSLg, so it works; over ssh
  without forwarding it correctly does nothing.
