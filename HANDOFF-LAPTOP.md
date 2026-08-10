# Handoff: verify the zsh-only shell change on the laptop

Transient. Delete this file once the checks below have been run and whatever
they turn up has been fixed — it describes one migration, not how the repo
works.

## What happened

`PR #2 zsh-only shell` splits `shell/common.sh` into `shell/env.sh` (sourced by
`~/.zshenv`, silent, every zsh) and `shell/interactive.sh` (sourced by
`~/.zshrc`, interactive only), deletes `bash/bashrc`, moves `bash/profile` to
`shell/profile`, and adds a guarded `chsh` step to `./install --packages`.

All of it was written and deployed on the **WSL box**. None of it has run on the
laptop. Every real defect this migration turned up was of one shape — correct on
the machine it was written on, broken on the other — so treat the list below as
the part of the work that is not done rather than a formality.

Do not re-run the checks in *Already verified* — they were measured on WSL and
repeating them on Manjaro tests nothing new.

## Before the checks

They assume `PR #2` is merged and the laptop has pulled and run
`./install --packages` from a terminal. Run it from a real terminal the first
time, deliberately: `packages/sync-packages.sh` picks `sudo -A` only when there
is no tty, so a terminal exercises the plain-`sudo` branch, and check 2 below is
the first execution of the other one on this distro.

## The checks

### 1. The graphical session still has a PATH — highest risk

`~/.profile` moved from `bash/profile` to `shell/profile`. lightdm's Xsession
sources it as `/bin/sh` before the session starts, and it is the only thing that
puts `~/.local/bin` and the asdf shims on the *session* PATH. zsh never reads
`~/.profile` at all — verified: a login zsh reads `~/.zshenv` and nothing else —
so this file's entire remaining purpose is the laptop's desktop.

Log out and back in, then from a terminal launched by **rofi or i3**, not one
that was already open:

```sh
echo $PATH | tr ':' '\n' | grep -E 'asdf/shims|local/bin'
```

Both must appear. If they do not, i3, polybar and anything started from rofi are
running without the toolchain, which surfaces later as unrelated-looking
breakage rather than as a PATH problem.

### 2. `sudo_`'s pacman branch — never executed anywhere

`packages/sync-packages.sh` gained a `sudo_` helper because plain `sudo` fails
with no tty. Only the **apt** path has ever run. The pacman and `pamac build`
calls are unexercised on any machine.

```sh
./install --packages          # from a terminal
```

Expect exit 0 and `packages ok — N declared, M present (manjaro)`. Then the
tty-less path, which is the case the helper exists for:

```sh
setsid ./install --packages < /dev/null   # or run it from a Claude Code session
```

A zenity dialog should appear. `sudo: a terminal is required to authenticate`
means the helper did not engage.

### 3. `chsh` step — first unattended run

`shell/set-login-shell.sh` now runs inside `--packages`. The laptop is already
on zsh, so it must no-op:

```
login shell already /usr/bin/zsh
```

Anything else — especially it attempting a change — is a bug. All four refusal
paths were exercised on WSL (not opted in, zsh absent, not in `/etc/shells`,
zsh present but exits non-zero) and each left the shell untouched, but the
already-correct case has only ever been observed on WSL.

### 4. askpass moved, and settings.json no longer sets it

`SUDO_ASKPASS` now points at `~/dotfiles/bin/zenity-askpass` and is exported by
`shell/env.sh`, guarded on `zenity` plus a non-empty display. The two hardcoded
`/home/wise/...` entries were removed from `claude/settings.json`, which had been
overriding it.

```sh
echo $SUDO_ASKPASS            # expect ~/dotfiles/bin/zenity-askpass
sudo -A id -un                # expect root, via a dialog
```

Then the branch WSL cannot reach naturally — an ssh host-key prompt should give
a **question** dialog, not a password box:

```sh
./bin/zenity-askpass "Are you sure you want to continue connecting (yes/no)?"
```

**The one to think about:** Claude Code now inherits `SUDO_ASKPASS` from the
shell that launched it rather than getting it from `settings.json`. A session
started from a desktop launcher or an IDE, rather than from a shell, may not
have it. Worth checking how you actually start it there.

`~/.local/bin/zenity-askpass` is now unused and can be deleted once check 4
passes. Confirm the tracked one works first.

### 5. Inbound ssh — applies here, not on WSL

This is what `~/.zshenv` exists for and it could not be tested on WSL: no sshd
there, and inbound ssh to that box is forbidden (owner, 2026-08-09). From
another machine:

```sh
ssh <laptop> 'command -v rg; printf DATA'
```

Expect a shim path and a bare `DATA`. **Anything printed before `DATA` is a
failure** — a non-interactive shell's stdout is the command's output, so a
banner from `~/.zshenv` corrupts every remote command. The equivalent path was
verified on WSL through `wsl.exe -e zsh -lc`, which pipes to Windows the same
way.

### 6. Needs eyes, not a command

- Prompt glyphs render (boxes mean a missing Nerd Font, which is host-side).
- `ci"`, `ci(`, `cs'"`, `ds(` behave as in vim. `bindkey` reporting the binding
  was verified; the behaviour was not.
- Cursor is a block in normal mode, a beam in insert, and switches on Escape.
- `^W` stops at `.` and `;`. `WORDCHARS` was dropping only `/&` before the fix,
  so this is the change most likely to feel different.
- `ranger` still leaves the shell in the directory you quit from. The function
  moved files and now uses `local`.
- `d` on a PR in gh-dash launches `gh-review`. That binding shadows the built-in
  diff, and `gh-review` runs from an asdf shim — the one place both custom
  builds meet.

## Already verified on WSL — do not repeat

`check-manifest --deployed`, `verify-tools`, `resolve --verify` and
`./install --packages` all exit 0. Login shell is `/usr/bin/zsh`. `~/.zshenv`,
`~/.zshrc`, `~/.profile` linked; `~/.bashrc` reaped. Non-interactive zsh has the
shims and prints nothing to stdout. Interactive startup produces zero bytes of
stderr. `sudo -A` and the askpass yes/no branch both work. The chsh step is
idempotent on re-run.

## Report back

- Whether the graphical session kept its PATH (check 1).
- Whether the pacman branch worked with and without a tty (check 2).
- How Claude Code is launched there, and whether it has `SUDO_ASKPASS` (check 4).
- Anything in check 6 that felt wrong rather than merely different.
