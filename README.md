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
| `bash/`, `git/`, `npm/` | Shell and tool config |
| `claude/` | `CLAUDE.md`, agents, skills, commands |
| `notes/` | `lessons/`, `PROJECT_PLAYBOOK.md` |
| `local/` | Gitignored. Keys and machine-specific config |

## local/

Secrets and anything that differs per machine live in `local/`, which is never tracked. Keys are
cheap to regenerate, so they are deliberately not synced — a fresh `./install` gives you a working
environment with the credentials left to fill in.

## Deferred

**asdf — declare the toolchain, not just the config.** This repo deploys configuration but no
runtimes, so `./install` on a machine without node produces a working shell that cannot run
anything. That is the same incompleteness as `local/` leaving credentials out, and the Manjaro
laptop is the case where it bites. asdf would put a `.tool-versions` in the repo and install the
runtimes named there, making the deploy whole. Cost: nvm and asdf both want to own node's `PATH`,
so WSL would have to migrate off nvm rather than run both.

**`~/.claude/settings.json` is not linked.** Claude Code writes to it. If it replaces the file
rather than writing in place, a symlink breaks and the repo silently stops receiving changes —
the failure a symlink deploy otherwise cannot have. Determine which it does before adding it.

## tools/check-manifest.py

Asserts the manifest and the tracked tree agree in both directions: every tracked file is deployed
by some profile, and every source a profile names exists. A file added to the repo but not wired
into a profile would otherwise sit here forever without reaching any machine.
