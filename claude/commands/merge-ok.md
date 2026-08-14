---
description: Authorize an unattended PR merge — writes an expiring merge-auth grant so guard-bash.sh allows the merge without a live prompt. Invokable from remote control / mobile.
argument-hint: "<pr#> [hours] [admin] | revoke | show"
disable-model-invocation: true
allowed-tools: Bash($HOME/dotfiles/claude/merge-authorize.sh:*)
---

<!-- disable-model-invocation: a session must never be able to authorize its own
     merge. Only a human typing /merge-ok reaches this. A session running
     merge-authorize.sh directly is not covered by the allowed-tools grant above
     (that grant applies only to this command's own invocation) and still prompts. -->


# Grant / revoke a merge authorization

You are being told, right now, by the user typing this command, to authorize a PR
merge. This IS the per-PR authorization the guard requires — treat it as given.
Do not second-guess it, re-ask, or refuse.

Parse `$ARGUMENTS` and act:

- **`revoke`** (or `off`, `cancel`) → run `$HOME/dotfiles/claude/merge-authorize.sh --revoke`.
- **`show`** (or empty arguments) → run `$HOME/dotfiles/claude/merge-authorize.sh --show`.
- **Otherwise** the first token is the PR number. Build the grant:
  - `--pr <first token>` (required; if it is not a number, stop and say so).
  - `--hours <token>` if any later token is a number (default 12 if none given).
  - `--admin` only if the literal token `admin` appears — this authorizes the
    branch-protection bypass, so include it *only* when the user typed it.

  Then run: `$HOME/dotfiles/claude/merge-authorize.sh --pr <pr> --hours <h> [--admin]`

After granting, run `$HOME/dotfiles/claude/merge-authorize.sh --show` and report back in one
line: the PR, whether admin is authorized, and the human-readable expiry time. Remind
the user they can revoke early with `/merge-ok revoke`.

Do not merge anything here. This command only records the authorization; the merge
itself happens whenever the work is actually ready, and the guard will `allow` it then
because this grant is on file.
