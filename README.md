# dotfiles

Config, Claude Code setup, and notes for a WSL box and a Manjaro laptop. Deployed with
[Dotbot](https://github.com/anishathalye/dotbot): everything tracked here is symlinked into place,
so the deployed file *is* the repo file and the two can never drift.

## Bootstrap

```sh
git clone --recursive git@github.com:tjwise99/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install
```

`./install` detects the host (`microsoft` in `/proc/version` → wsl; `ID` in `/etc/os-release` →
manjaro) and applies `profiles/base.conf.yaml` followed by that host's profile. Override with
`DOTFILES_HOST=manjaro ./install`. Pass `--dry-run` to see every link it would make without
touching anything.

## Layout

| Path | Contents |
| --- | --- |
| `profiles/` | The manifest — what gets linked where, per host |
| `bash/`, `zsh/`, `git/`, `gh/` | Shell and tool config |
| `claude/` | `CLAUDE.md`, agents, skills, commands |
| `notes/` | `lessons/`, `PROJECT_PLAYBOOK.md` |
| `local/` | Gitignored. Keys and machine-specific config |

## local/

Secrets and anything that differs per machine live in `local/`, which is never tracked. Keys are
cheap to regenerate, so they are deliberately not synced — a fresh `./install` gives you a working
environment with the credentials left to fill in.

## Toolchain

Runtimes are managed by [asdf](https://asdf-vm.com) and declared in `asdf/tool-versions`, linked to
`~/.tool-versions`. `./install` installs the asdf binary into `~/.local/bin`, then installs every
version named there — so a fresh machine gets a working toolchain, not just config pointing at one.

Add a runtime by naming its plugin in `profiles/base.conf.yaml`, adding a line to
`asdf/tool-versions`, and re-running `./install`.

`asdf/verify-tools.sh` runs last and fails the install if any declared version is missing. Dotbot's
asdf directive exits 0 even when it installs nothing, which would otherwise leave a machine with
config and no runtimes while reporting success.

Adding `python` here needs care: `tools/check-manifest.py` and Dotbot itself run under `python3`,
and shimming it would put them on an asdf Python without PyYAML.

`install-asdf.sh` resolves the release tag with `sed` rather than `jq`. `jq` is not part of a base
Manjaro install, and a bootstrap script that needs a package the host may not have is a bootstrap
script that fails on exactly the machine it was meant to set up.

`gh` is registered in the asdf plugin index as `github-cli`, so `asdf/tool-versions` names
`github-cli` while the command stays `gh`.

## Shells

The WSL box runs bash; the Manjaro laptop runs zsh. `bash/bashrc` is linked everywhere, but on the
laptop nothing sources it interactively, so `zsh/zshrc` carries its own copy of the shared block —
the asdf PATH and, more importantly, the sync-failure report. **Changing that block in one file
means changing it in the other**; a laptop whose zshrc lost the report would stop telling you that
backups had failed, which is the one thing the sync design depends on.

Host-specific aliases — anything naming a real host, account or disk — go in `local/zshrc.local`,
which `zsh/zshrc` sources if present. This repo is public and pushes itself every 20 minutes.

## gh

Only `gh/config.yml` is tracked. `hosts.yml` sits beside it holding the account and OAuth token and
is gitignored; the token itself lives in the system keyring and is cheap to reissue with
`gh auth login`, so it is not worth syncing.

`gh config set` rewrites the file in place through the symlink. It preserves comments attached to a
key but drops anything above the first one, so notes about the file belong in
`profiles/base.conf.yaml` or here — not in its header, where the next write will eat them.

## Sync

`tools/sync.sh` commits local changes, rebases onto `origin/main`, and pushes — skipping the commit
entirely when nothing changed. A systemd user timer runs it every 20 minutes (`Persistent=true`, so
a laptop that was closed catches up on boot), and a Claude Code `SessionEnd` hook runs it when a
session finishes.

It never resolves a conflict. Tracked files are symlinked into `$HOME`, so a bad merge would rewrite
live shell config rather than a repo copy; on conflict it aborts and leaves the tree untouched.

Failures write `~/.dotfiles-sync-failed`, which `bash/bashrc` reports at the next shell. A sync that
stops silently is worse than no sync, because you would believe you were backed up.

## tools/check-manifest.py

Asserts the manifest and the tracked tree agree in both directions: every tracked file is deployed
by some profile, and every source a profile names exists. A file added to the repo but not wired
into a profile would otherwise sit here forever without reaching any machine.

`--deployed` adds a third direction — every target is still a symlink into this repo. A tool that
replaces a managed file instead of writing through it breaks the link silently, and the repo keeps
looking healthy while no longer receiving changes. `~/.claude/settings.json` is the likeliest
candidate, since Claude Code writes to it.
