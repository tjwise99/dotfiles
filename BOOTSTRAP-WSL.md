# Bootstrapping the WSL box

Written for a session that has never seen this machine. The Manjaro side of
`cross-host-packages` is installed and working; **the WSL side has never been
run**, and this is the run that tests it. Treat every apt package name below as
a claim, not a fact — they were authored from the Manjaro host and never
resolved against a real Ubuntu.

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
reboot of the VM, not a shell restart.

**A Nerd Font.** The prompt is powerlevel10k and draws with glyphs outside
normal Unicode. Without one the prompt renders as boxes. The font is installed
on the *Windows* side — Ubuntu's font packages do nothing for Windows Terminal.
Install JetBrainsMono Nerd Font from nerdfonts.com, then set it in Windows
Terminal → Settings → your Ubuntu profile → Appearance → Font face.

## 2. Pre-flight the package names

This is the step most likely to find a defect, so do it before anything is
installed:

```sh
apt-cache policy build-essential git curl unzip zsh vim ranger htop fastfetch
```

Any entry showing `Candidate: (none)` is a wrong name in
`packages/manifest.yaml`. `fastfetch` is the most likely — it reached Ubuntu's
archive late, so an older LTS may not carry it. Fix the `apt:` value there, or
mark it `unavailable` with the reason; do not delete the entry, because
`resolve.py` treats a missing column as an error precisely so a package cannot
vanish silently from one host.

## 3. Clone

There is no SSH key on a fresh machine, so clone over HTTPS:

```sh
git clone --recursive https://github.com/tjwise99/dotfiles.git ~/dotfiles
cd ~/dotfiles && git switch cross-host-packages
```

`--recursive` matters more than it used to: the prompt and the four zsh plugins
are submodules now. If it was missed, `git submodule update --init --recursive`.

## 4. Baseline first, then install

`resolve.py --verify` refuses to run with no baseline for this host rather than
running half of what it claims to. `sync-packages.sh` is the *first* step of the
install, so without a baseline the whole run stops there. Write it first — on a
fresh image that is exactly the right moment, since everything explicitly
installed is genuinely pre-existing:

```sh
python3 packages/resolve.py --write-baseline
./install --packages
```

`--packages` is not optional here. It is opt-in because it needs root, but asdf
compiles and downloads, so nothing after it succeeds without `build-essential`,
`curl` and `unzip`.

## 5. Make zsh the login shell

Nothing in this repo does this, deliberately — it needs a password and it is
not idempotent in a way an installer should own:

```sh
chsh -s "$(command -v zsh)"
```

Then close the terminal and reopen it. Until this is done the install completes
and deploys a `~/.zshrc` that nothing reads.

## 6. Verify

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

## 7. Expected to differ from the laptop, correctly

- No `~/.config/zsh/x.zsh`, so no `fixWindows` or `clip` alias. That file is
  deployed by the manjaro profile alone and `zsh/zshrc` tests for it.
- No theme, i3, polybar or Xresources links. Tier 3 is X-only by design.
- History starts empty. `~/.zhistory` is per-machine and never synced.
- `gh` is unauthenticated until `~/.claude_github_token` exists;
  `shell/common.sh` skips that block silently when it does not.
- The sync timer backs up to `origin/main`. While `cross-host-packages` is
  checked out it will commit locally and push nothing.

## 8. Worth reporting back

- Which apt names had no candidate.
- Whether systemd was already on.
- Whether the prompt rendered, or showed boxes.
- Whether `resolve.py --verify` found anything beyond the baseline.
