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

## Deferred

**`~/.claude/settings.json` is not linked.** Claude Code writes to it. If it replaces the file
rather than writing in place, a symlink breaks and the repo silently stops receiving changes —
the failure a symlink deploy otherwise cannot have. Determine which it does before adding it.

## tools/check-manifest.py

Asserts the manifest and the tracked tree agree in both directions: every tracked file is deployed
by some profile, and every source a profile names exists. A file added to the repo but not wired
into a profile would otherwise sit here forever without reaching any machine.
