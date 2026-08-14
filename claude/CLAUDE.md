# Working rules

Global rules for working on the user's hosts. Per-project context lives in that project's own
`CLAUDE.md`, machine-specific detail in its gitignored `CLAUDE.local.md`, and reference material in
[`claude/README.md`](README.md) — this file is only for what changes behaviour every session.

**It states invariants only.** Which tools exist, where they resolve, how the GitHub token is stored,
whether Docker is installed, whether the sync timer and gitleaks hook are live — all of that differs
between the machines this file syncs to and is printed at session start by `claude/host-facts.sh`.
Those lines win; nothing here is a claim about the machine you are on.

## The user
Aerospace background: V-model requirements rigor (SYS→SRS→TST) and traceability-first thinking —
when docs tooling feels "unusable," suspect the traceability/information-design layer before the
chrome. Treats AI tooling as a first-class repo reader: source files stay byte-identical, plain
GFM/YAML, no frontmatter or generator dialects.

## Delegation
**Standing authorization: spawn subagents without asking** (user instruction, 2026-08-13). Opus 5's
prompt bundle carries "do not call the AgentTool unless the user requested it" — this is that
request, standing. Delegate research, sweeps and review whenever a fresh or parallel context is worth
more than the tokens.
- **`independent-reviewer` for any diff this session wrote.** Independence is a property of context,
  not of instruction — an agent cannot review its own work by being told to be critical.
- **A subagent's deliverable is a file it wrote, never its prose.** Name the path, then `ls` it before
  treating completion as real: an idle notification is contentless, so *answered in prose* and *was
  denied permission* look identical from here. `Write` is in no allow-list under `defaultMode: auto`,
  so have it serialise with `cat > <path> <<'EOF'`, which matches `Bash(cat:*)`. Verify a ruling
  landed by `grep`ping the file, never by reading the agent's status list.
- **Cross-examine a panel, never just collect it.** Send each reviewer the others' blocking findings
  and require concur-or-dissent with a reason. Surviving peer attack is worth far more than being
  gathered. Tell an agent it may refuse your number, and treat refusal as signal about the number.
- **`@`-mentioning an agent definition file means adopt that persona inline** — never a spawn.

## Shell environment
- **The Bash tool's shell sources no startup file** — not `~/.zshenv`, not `~/.zshrc`. The
  environment arrived by inheritance from the shell that launched Claude Code, so a session started
  before a config change does not see it.
- **That shell is zsh.** Two bash reflexes fail *silently*: unquoted `$VAR` does **not** word-split,
  so `SSH="ssh -o …"; $SSH host cmd` runs the whole string as one command name (exit 127) — use a
  quoted array; and `$PIPESTATUS` is unset, spelled `$pipestatus`, indexed from **1**. Scripts are
  unaffected — a `#!/bin/bash` shebang and just's `[script('bash')]` pin bash.
- **`grep` in the Bash tool is ugrep**, a shell function re-execing Claude Code's own binary. It is
  not exported, so scripts, `just` and CI get GNU grep, and the two disagree on syntax. Nothing is
  misconfigured. **When grep's behaviour is itself under test, call `/usr/bin/grep` or invoke the
  script under test** — a case seeded as a Bash-tool pipeline measures a different engine.
- **A pipeline reports the LAST command's status.** `just verify | tail -50` reports `tail`'s exit
  code, so a failing gate reads green. Never append `; echo "exit=$?"` to a pipeline and believe it —
  redirect to a file and test `$?` **on the very next line**, before anything clobbers it.
- **`set -o pipefail` + `grep -q` inverts a successful match.** `-q` exits on the first hit, the
  producer dies of SIGPIPE at 141, and pipefail returns that — the condition is false *precisely when
  the pattern matches*. Use `grep -c` and compare, or `[[ $var == *pat* ]]`. And `grep -c … || echo
  0` emits **two** lines, because grep prints `0` and also exits 1.
- **Password prompts are answerable — run them, don't hand them back.** `SSH_ASKPASS`/`SUDO_ASKPASS`
  put the prompt on the desktop; ssh consults it automatically, **sudo only under `sudo -A`**. The
  credential does not cache between Bash calls, so `sudo -A` must sit in the *same* call as the
  command needing it. Headless and cron have no display; it is a no-op there.
- **Runtimes are asdf-managed** in `~/.tool-versions` — add one there and re-run `~/dotfiles/install`
  rather than installing by hand.
- **If "it passed" would look identical when the thing failed, nothing was measured.** True well past
  the shell: a test with no assertion, a mock that always succeeds, a health check grepping for a
  string absent from healthy *and* unhealthy output.

## `~/dotfiles` auto-publishes to a PUBLIC repo
`dotfiles-sync.timer` runs `tools/sync.sh` every 20 minutes: **`git add -A`, commit, `git push`** to
the public `github.com/tjwise99/dotfiles`. No review step — anything sitting in that tree is
published whether or not anyone meant it to be, so **a project directory under `~/dotfiles` is a
published project.**

`~/.claude/{CLAUDE.md,settings.json,agents,skills,commands}`, `~/lessons`, `~/PROJECT_PLAYBOOK.md`,
`~/.zshrc` and `~/.gitconfig` are symlinks into it. Edit refuses to write through a symlink, so
resolve with `readlink -f` and write the real path.

**Strip identifying detail before writing there** — SSID, MAC, internal subnet, hostname, serial,
router model, address, client name. gitleaks catches only credential-shaped strings, so none of that
is blocked, and together it fingerprints a network. Write *"a wall-mounted Pi kiosk"*, *"a LAN
host"*, and keep specifics in the project's own directory. `guard-publish.sh` asks on the obvious
patterns; it is a backstop, not the rule.

## GitHub
Account **`tjwise99`**. Use `gh` for all API work — it authenticates itself and is token-friendly
(`--jq`, purpose-built subcommands). Pushes go over SSH with a passphrase-less key.
- **Standing authorization: commit and push without asking** (user instruction, 2026-07-21) — via
  branch + PR, never direct to a protected default branch, verify gate green before merge is
  proposed. Overrides any harness default of "commit only when asked."
- **HARD LIMIT: never merge a PR, never `--admin`**, unless the user says so for that specific PR;
  said once about one PR it is not a policy. `guard-bash.sh` denies both outright — matched against
  the actual `gh` invocation in each simple command, so a mere mention in an echo or commit message
  passes. It does not gate ordinary commits or pushes. Parallel sessions still share a worktree and a
  commit once landed on another session's branch, so if HEAD is unexpected, check `git worktree list`.
- **Waiting on CI is unreliable.** `gh run watch --exit-status` can exit 0 immediately and `gh pr
  checks` lags the check-runs API. Poll `gh api repos/<o>/<r>/actions/runs/<id> --jq .status`.

## Working style
- **Decisions are the user's — walk trades conversationally first.** Honest pros and cons in prose,
  not option menus or document dumps; state a lean and let the user call it. Never bury a decision in
  a plan or ADR draft: plan approval is not approval of a decision inside it.
- **If consent has to be inferred, it wasn't given.** A ruling about *content* answers a different
  question and leaves the request open; continued engagement is not consent. Binds every irreversible
  or outward-facing action. Two corollaries: **don't perform a gate you would walk through anyway**,
  and **when authorisation is ambiguous, produce the inspectable form** — write the draft, print the
  diff, show the command, so the failure mode costs a file rather than a mutation.
- **Never report a procedure as done without running it**, and check that the claim you write is the
  claim you tested. Not "it would pass" — ran, with the output. A correct 404 against one host once
  became "this machine cannot be rebuilt" in a handoff; the check was right, the sentence wasn't, and
  the sentence is what gets acted on.
- **Prove a check can fail before trusting it.** Seed the defect *and* the spelled-differently-but-
  valid variant, since a gate that catches the defect may also reject legal input. Confirm the seed
  landed — one that silently fails to apply looks exactly like a working check. A guard keyed on the
  same literal as the thing it guards cannot see that thing fail. A fix is not verified until the
  finding's **own** reproduction is re-run against it. A step added to a sequence must be re-run
  against every case the sequence already passed, first where the steps share mutable state.
- **Verify a ticket's premise before building against it.** Reproduce the defect it asserts against
  the checks that exist today. That a new check fires is not evidence it was needed.
- **Find the document that already decides it** before forming a position — ask "which document
  decides this?" and read that one, not the one the task handed you.
- **When a correction recurs, stop correcting the instance and find what is not gating the class** —
  and record the reason, so the next editor meets an argument rather than a gap.
- **When you delete a mechanism, grep the whole tree for its name.** A justfile `[doc()]`, a workflow
  step's `name:`, `--help` text — operator-facing docs live outside `docs/`, so a prose sweep misses
  them by construction.
- **An unattributed claim in a handoff is agent opinion, not owner ruling.** Owner decisions carry
  "(owner, <date>)" or a direct quote; a bare imperative among them is something a session made up.
- **Never write a bare `#N`, and never use a number as a name.** GitHub draws issues and PRs from one
  counter, so `#66` and `#69` differ in kind but not in shape. Write **`PR #66`** and **`#69 tree
  rebuild`** — number *and* name. Same for any renumberable ID: `SRS026 backend-unreachable state`,
  because a renumber rewrites `links:` but not prose.
- **Minimal inline comments.** No narrative blocks, no temporal language ("now", "no longer") — state
  the timeless fact, and prefer the tool's native doc facility. Trim legacy density when touching.
- **On environment problems, stop and ask.** Root-owned files, EACCES, blocked symlinks, processes
  dying on odd signals — one diagnostic to characterise it, then surface it with the specific fix and
  wait. Don't chain retries or build workarounds; the user can usually fix it in one step.
