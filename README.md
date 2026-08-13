# dotfiles

Config, Claude Code setup, and notes for a WSL box and a Manjaro laptop. Deployed with
[Dotbot](https://github.com/anishathalye/dotbot): everything tracked here is symlinked into place,
so the deployed file *is* the repo file and the two can never drift. The one exception is
[`system/`](#system), which is copied into `/etc` and so has to check for drift instead.

## Bootstrap

```sh
git clone --recursive git@github.com:tjwise99/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install
```

`./install` detects the host (`microsoft` in `/proc/version` → wsl; `ID` in `/etc/os-release` →
manjaro or nixos) and applies `profiles/base.conf.yaml`, then `profiles/desktop.conf.yaml` if the
host has an X server, then that host's own profile. Override with `DOTFILES_HOST=manjaro ./install`.
Pass `--dry-run` to see every link it would make without touching anything.

The desktop links are keyed on having a display rather than on the distro, so the laptop keeps one
declaration of its desktop across a move from Manjaro to NixOS. A copy per host would be two lists
that can disagree with nothing comparing them.

`./install --packages` additionally installs what [Packages](#packages) declares, and
`./install --system` applies what [`system/`](#system) holds. Those are the two steps that need
root, so both are opt-in and every other step stays runnable unattended — but on a genuinely fresh
machine neither is optional: asdf compiles and the compiler is one of the packages, and without
`--system` the Manjaro host comes up with no network configuration at all.

Bringing up a WSL box has prerequisites that live on the Windows side and a first-run order that
matters: [`BOOTSTRAP-WSL.md`](BOOTSTRAP-WSL.md).

## Layout

| Path | Contents |
| --- | --- |
| `profiles/` | The manifest — what gets linked where, per host |
| `packages/` | What each host installs from its own package manager |
| `system/` | Root-owned config under `/etc`, copied rather than linked |
| `shell/`, `zsh/`, `git/`, `gh/` | Shell and tool config |
| `nvim/` | NvChad-based Neovim config, vendored from upstream |
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

Python is owned by uv, not by asdf and not by the distro. `asdf/uv-python.sh` runs `uv python
install --default`, which is the part that matters: without `--default` uv installs `python3.14`
only, and the bare `python3` that mason and every shebang look for still resolves to whatever the
host shipped. The script then creates a venv with the interpreter it resolved rather than reporting
the install as success — `~/.local/bin` is only ahead of `/usr/bin` if `shell/env.sh` put it there,
and a `python3` that resolves elsewhere looks identical until mason tries to build something.

Shadowing the distro `python3` is safe here for a reason worth writing down, because it is not
visible from the shebangs: `packages/resolve.py`, `tools/check-manifest.py` and Dotbot's own
launcher each prepend `dotbot/lib/pyyaml/lib` to `sys.path`. They need *a* Python 3.7+, never the
host's, and never PyYAML installed anywhere. A consumer added later that imports a third-party
module without vendoring it is what would break, and nothing here would catch it.

`install-asdf.sh` resolves the release tag with `sed` rather than `jq`. `jq` is not part of a base
Manjaro install, and a bootstrap script that needs a package the host may not have is a bootstrap
script that fails on exactly the machine it was meant to set up. The `jq` in the asdf block above is
not a reason to switch back: it is installed *by* that block, so it does not exist yet at the point
`install-asdf.sh` runs.

`gh` is registered in the asdf plugin index as `github-cli`, so `asdf/tool-versions` names
`github-cli` while the command stays `gh`.

## Packages

`packages/manifest.yaml` names what each host installs from its own package manager, in tiers by who
owns the tool:

| Tier | Owner | Cross-host |
| --- | --- | --- |
| 0 | Nix, via [WiseOS](https://github.com/tjwise99/WiseOS)' `home/wise.nix` | One build everywhere; no package names here at all |
| 1 | asdf, via `asdf/tool-versions` | One pinned version everywhere; no package names here at all |
| 2 | `shared:` in the manifest | The same tool under two names |
| 3 | `manjaro:` in the manifest | Needs X, so it has one column and no mapping |

Tier 2 is the only place the two hosts can disagree, which is why the design pushes work up out of
it rather than across into a bigger table. Tier 0 is what a tool declared per-distro cannot do:
follow a machine with no distro package manager to declare it to. `shared:` is down to the
bootstrap set as a result.

**A tool leaves tiers 1-3 only after every host that needs it can get it from tier 0.** Removing a
row reaches the other host within 20 minutes of a commit, and a host not yet running Home Manager
has nothing to supply the replacement.

`packages/sync-packages.sh` expands the list and hands it whole to `pacman` or `apt-get`. It
resolves nothing, orders nothing and removes nothing.

`packages/resolve.py --verify` checks both directions. Declared-but-absent asks whether a package is
present at all, not whether it was installed by name: `curl`, `git`, `zsh` and `xclip` are all on
the laptop and none appear in `pacman -Qqe`, because each arrived as a dependency. The undeclared
direction is measured over explicit installs only, against `packages/baseline-<host>.txt` — the
untriaged set that predates the manifest, recorded so the check reports what was installed since
rather than everything the ISO shipped. It fails when that file is absent rather than silently
running half of what it claims to.

An entry with no name for a supported host must say `unavailable` and why. A missing column is an
error: a resolver that drops what it does not recognise reports success over whatever survived.

## system/

The Manjaro host's network stack, and the only tracked config that is copied rather than symlinked.
Applied by `profiles/manjaro.conf.yaml` alone: a NixOS host declares the same two daemons in its own
system configuration, so it neither runs this step nor needs these files.
`system/apply.sh` writes `system/iwd/main.conf` and `system/network/20-wired.network` into `/etc`,
then enables `iwd`, `systemd-networkd` and `systemd-resolved`. Copies rather than links because
`/home` is its own partition — a service starting before it is mounted would read a dangling path —
and because a root daemon's config should not sit somewhere its own unprivileged user can rewrite.

The two daemons split the interfaces rather than sharing them. `iwd` owns `wlan0` including its IP,
which is what the polybar wifi glyph opens `impala` against; `systemd-networkd` matches `Name=en*`
and so takes the wired port without ever reaching the radio, `docker0` or a veth pair. Both hand
DNS to `systemd-resolved`, which is why `/etc/resolv.conf` is the resolved stub.

Copying gives up the guarantee the rest of the repo has, so `system/apply.sh` reports drift when run
without `--system` instead of reporting nothing — missing files, files that differ, units that are
not enabled and running. What it deliberately does not carry is the credential under `/var/lib/iwd`:
that is a PSK and this repo is public. A rebuilt host joins its network once, by hand.

## Neovim

`nvim/` is linked whole to `~/.config/nvim`, on every host — it is a TUI, so it runs the same over
ssh and under WSL. It is an [NvChad](https://nvchad.com) v2.5 config, vendored from a friend's public
dotfiles rather than written here, with the AI stack removed: `copilot.lua` and `codecompanion.nvim`
both need a GitHub Copilot subscription this account does not have, and a plugin that fails auth on
every startup is worse than an absent one. `nvim/lua/configs/blink.lua` lost its `codecompanion`
completion source with them.

Pinned to Neovim v0.11.3 rather than current stable. Two separate reasons, and only the first is a
hard floor: the config drives LSP through `vim.lsp.config` / `vim.lsp.enable`, which do not exist
before 0.11, and `nvim/lazy-lock.json` is the plugin set this config was actually observed working
against, locked while upstream was on 0.11. Moving to 0.12 means moving both together.

`lazy-lock.json` is the pin, and it is tracked. `:Lazy restore` puts the tree back on it; `:Lazy
update` moves it, and the changed lock file is the commit. Plugin code itself lives in
`~/.local/share/nvim` and is not tracked — nothing lazy.nvim writes lands back in this repo except
that one file.

Two things do not install themselves on first launch:

| Step | Command | Notes |
| --- | --- | --- |
| Plugins | `:Lazy restore` | Bootstraps itself; treesitter compiles its 34 parsers on the first start |
| LSP, formatters, debuggers | `:MasonToolsInstall` | 40 tools, and the slowest step by a wide margin |

Mason is what pulls in the runtime dependencies the rest of this file already provides: node and go
and cargo from asdf, a C compiler from `base-devel`, and a `python3` that can build a venv from uv.

The clangd config is upstream's and is left as-is. It only attaches inside a project holding a
`.clangd-docker` marker, so on a host with no such project it is inert rather than wrong.

Glyphs need a Nerd Font. Manjaro installs `ttf-jetbrains-mono-nerd` from the manifest; under WSL the
font belongs to the Windows terminal emulator, so it is not a package this repo can declare.

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

The shell config is split by *when zsh reads it*, not by what it configures, because zsh reads two
different files for two different kinds of shell:

| File | Read by | Holds |
| --- | --- | --- |
| `shell/env.sh` | `~/.zshenv` — **every** zsh — and `~/.profile` | asdf PATH, askpass, `gh` auth, `EDITOR` |
| `shell/interactive.sh` | `~/.zshrc` — interactive only | aliases, the `ranger` wrapper, sync health |

`~/.zshrc` is not read by `ssh host <command>` or by a zsh script, so environment placed there
reaches neither: before `~/.zshenv` existed, `env -i zsh -c 'command -v rg'` found nothing, because
the asdf shims were set up in a file those callers never open. The split is what fixes that, and it
has to be a split rather than a move — a non-interactive shell's stdout **is** the command's output,
so the sync-health banner printed from `~/.zshenv` prepends itself to the data every `ssh host cat
…` returns. Both halves stay POSIX sh, because `~/.profile` is read by lightdm's Xsession and that
is `/bin/sh`.

Every block in `env.sh` is guarded on the capability it needs rather than on the host name, which is
what lets both files be byte-identical on the two machines.

`zsh/zshrc.x` is the part that needs X. Only `profiles/manjaro.conf.yaml` deploys it, and `zsh/zshrc`
sources it if it is there, so the WSL box runs the same zshrc and simply never finds it.

Bash is not configured by this repo. zsh is the login shell everywhere, `~/.zshenv` covers the
non-interactive callers `~/.bashrc` was once kept for, and the scripts here with a `bash` shebang
use it as a language — a non-interactive bash reads no rc file, so they never wanted one.

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

Two signals reach the next shell through `shell/interactive.sh`, because they fail differently. Failures
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
