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

`./install --packages` additionally installs what [Packages](#packages) declares. It is the only
step that needs root, so it is opt-in and every other step stays runnable unattended — but on a
genuinely fresh machine it is not optional, because asdf compiles and the compiler is one of the
things it installs.

Bringing up a WSL box has prerequisites that live on the Windows side and a first-run order that
matters: [`BOOTSTRAP-WSL.md`](BOOTSTRAP-WSL.md).

## Layout

| Path | Contents |
| --- | --- |
| `profiles/` | The manifest — what gets linked where, per host |
| `packages/` | What each host installs from its own package manager |
| `bash/`, `zsh/`, `git/`, `gh/` | Shell and tool config |
| `zsh/plugins/` | Submodules. Prompt and zsh plugins, pinned so both hosts match |
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

`asdf/verify-tools.sh` fails the install if any declared version is missing. Dotbot's asdf directive
exits 0 even when it installs nothing, which would otherwise leave a machine with config and no
runtimes while reporting success.

It also asserts that every plugin `profiles/base.conf.yaml` installs has a line in
`asdf/tool-versions`. The two are separate declarations and only the second one reaches a shim: a
plugin named in the profile alone installs a shim that shadows the distro's binary and then answers
`No version is set`, which is strictly worse than not adopting the tool. Checking `~/.tool-versions`
alone cannot see it, because the missing entry is the defect.

Adding `python` here needs care: `tools/check-manifest.py` and Dotbot itself run under `python3`,
and shimming it would put them on an asdf Python without PyYAML.

`install-asdf.sh` resolves the release tag with `sed` rather than `jq`. `jq` is not part of a base
Manjaro install, and a bootstrap script that needs a package the host may not have is a bootstrap
script that fails on exactly the machine it was meant to set up. The `jq` in the asdf block above is
not a reason to switch back: it is installed *by* that block, so it does not exist yet at the point
`install-asdf.sh` runs.

`gh` is registered in the asdf plugin index as `github-cli`, so `asdf/tool-versions` names
`github-cli` while the command stays `gh`.

## Packages

`packages/manifest.yaml` names what each host installs from its own package manager, in three tiers
by who owns the tool:

| Tier | Owner | Cross-host |
| --- | --- | --- |
| 1 | asdf, via `asdf/tool-versions` | One pinned version everywhere; no package names at all |
| 2 | `shared:` in the manifest | The same tool under two names |
| 3 | `manjaro:` in the manifest | Needs X, so it has one column and no mapping |

Tier 2 is the only place the two hosts can disagree, which is why the design pushes work up into
tier 1 rather than across into a bigger table. A tool asdf can provide needs no names here, and for
one Ubuntu renames — `fd` as `fdfind`, `bat` as `batcat` — asdf is also what keeps the command the
same on both hosts.

`packages/sync-packages.sh` expands the list and hands it whole to `pacman` or `apt-get`. It
resolves nothing, orders nothing and removes nothing; the moment it needs to special-case a package,
the answer is a package manager that is itself cross-distro, not more rows. The manifest header
records that tripwire, because nothing measures it — the file gets one row longer at a time and no
single addition looks like the one that tipped it.

`packages/resolve.py --verify` checks both directions. Declared-but-absent asks whether a package is
present at all, not whether it was installed by name: `curl`, `git`, `zsh` and `xclip` are all on
the laptop and none appear in `pacman -Qqe`, because each arrived as a dependency. The undeclared
direction is measured over explicit installs only, against `packages/baseline-<host>.txt` — the
untriaged set that predates the manifest, recorded so the check reports what was installed since
rather than everything the ISO shipped. It fails when that file is absent rather than silently
running half of what it claims to.

An entry with no name for a supported host must say `unavailable` and why. A missing column is an
error: a resolver that drops what it does not recognise reports success over whatever survived.

## Shells

zsh is the login shell on both hosts, and `zsh/zshrc` is deployed on both. It sources its prompt and
plugins from `zsh/plugins/`, which are pinned submodules, rather than from `/usr/share` — Manjaro
packages them, Ubuntu names them differently and puts them elsewhere, and sourcing by distro path
would make the file behave according to which machine it landed on. `zsh/p10k.zsh` is Manjaro's own
generated prompt config, tracked here so the prompt survived that move unchanged.

Those paths are written out in full rather than built from a variable, because
`tools/check-manifest.py` vouches for a tracked file by finding its path as a literal string in a
deployed one, and an interpolated prefix is never contiguous with the rest of the path.

`zsh/zshrc` also carries the shell behaviour that came with `manjaro-zsh-config` — the bindings for
keys zsh leaves unbound (Home, End, Delete, page keys, word-wise motion), `WORDCHARS`, the
completion styles and the history options. None of it is plugin config, and all of it was invisible
while a distro package supplied it: only the laptop had any of it, and dropping the package would
silently take it away. `HISTFILE` stays at `~/.zhistory` because the history is already there, and
pointing elsewhere strands it rather than losing it, which is harder to notice.

The keymap is vi. `edit-command-line` on `v` is the reason — it opens the line under construction in
`$EDITOR` and runs what comes back — with text objects and `surround` bound so `ci"` and `cs'"`
behave as they do in vim. Every binding for a named key is installed in `viins` and `vicmd` both,
and insert mode keeps `^A ^E ^W ^U ^K ^R` and a working backspace, so no existing habit has to be
unlearned before normal mode is worth reaching for. `KEYTIMEOUT=1` is what makes Escape respond
immediately; the escape sequences that would otherwise be lost to it are bound explicitly rather
than resolved by timing. The mode itself is reported by the `vi_mode` segment in `~/.p10k.zsh` and
by the cursor, which is a block in normal mode and a beam in insert.

`shell/common.sh` holds what both shells need — the asdf PATH, askpass, `gh` auth, `EDITOR`, the
aliases, the `ranger` wrapper and the sync health report — and both rc files source it, so there is
one copy. It must stay POSIX sh. Every block in it is guarded on the capability it needs rather than
on the host name, which is what lets it be byte-identical on both machines.

`zsh/zshrc.x` is the part that needs X. Only `profiles/manjaro.conf.yaml` deploys it, and `zsh/zshrc`
sources it if it is there, so the WSL box runs the same zshrc and simply never finds it.
`bash/bashrc` is still deployed on WSL: an inbound non-interactive bash and a Windows-side
`wsl -e bash -lc` both read it, and it is what sources `shell/common.sh` for them.

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

Two signals reach the next shell through `shell/common.sh`, because they fail differently. Failures
write `~/.dotfiles-sync-failed`. Every run, successful or not, touches `~/.dotfiles-sync-stamp`, and
its absence or age is the only thing that can describe a host where the timer never fires at all —
that host writes no failure marker precisely because nothing runs to write one, so a report built on
the marker alone calls it healthy. A sync that stops silently is worse than no sync, because you
would believe you were backed up.

WSL is where that case is real: it boots without systemd unless `/etc/wsl.conf` contains
`[boot]\nsystemd=true` and the distro has been restarted with `wsl --shutdown`. Until then nothing
runs the timer there and the `SessionEnd` hook is the only thing backing the repo up.
`systemd/enable-timer.sh` says so loudly instead of exiting quietly.

`systemctl --user disable dotfiles-sync.timer` deletes
`~/.config/systemd/user/dotfiles-sync.timer`, which is Dotbot's deployed symlink rather than an
enable link. Re-running `./install` puts it back.

## tools/check-manifest.py

Asserts the manifest and the tracked tree agree in both directions: every tracked file is deployed
by some profile, and every source a profile names exists. A file added to the repo but not wired
into a profile would otherwise sit here forever without reaching any machine.

`--deployed` adds a third direction — every target is still a symlink into this repo. A tool that
replaces a managed file instead of writing through it breaks the link silently, and the repo keeps
looking healthy while no longer receiving changes. `~/.claude/settings.json` is the likeliest
candidate, since Claude Code writes to it.
