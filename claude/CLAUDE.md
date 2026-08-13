# Working rules

Global rules for working on the user's hosts. Per-project context lives in that project's own
`CLAUDE.md`, and machine-specific detail in its gitignored `CLAUDE.local.md`.

**This file states invariants only.** Which tools exist, where they resolve, how the GitHub token is
stored, whether Docker is installed — all of that differs between the machines this file syncs to,
and is printed at session start by `claude/host-facts.sh`. Those lines are authoritative; nothing
here should be read as a claim about the machine you are on.

## The user
Aerospace background: V-model requirements rigor (SYS→SRS→TST) and traceability-first thinking —
when docs tooling feels "unusable," suspect the traceability/information-design layer before the
chrome. Treats AI tooling as a first-class repo reader: source files stay byte-identical, plain
GFM/YAML, no frontmatter or generator dialects.

## Delegation
**Standing authorization: spawn subagents without asking** (user instruction, 2026-08-13). Opus 5's
default prompt bundle carries "do not call the AgentTool unless the user requested it" — this is that
request, standing, and it does not need repeating each session. Delegate research, codebase sweeps
and review whenever a fresh or parallel context is worth more than the tokens it costs.
- **`independent-reviewer` for any diff this session wrote.** Independence is a property of context,
  not of instruction — an agent cannot review its own work by being told to be critical.
- **A subagent's deliverable is a file it wrote, never its prose.** Brief every agent to write its
  result to a path you name, then `ls` that path before treating completion as real: a background
  agent's idle notification is contentless, so *answered in prose* and *was denied permission* look
  identical from here. `Write` sits in no allow-list under `defaultMode: auto`, so have it serialise
  with `cat > <path> <<'EOF'`, which matches the allow-listed `Bash(cat:*)`.
- **Verify a ruling landed in the tree; never read it off the agent's status list.** "Unchanged from
  last report" means either *not done* or *done earlier*, indistinguishable. `grep` the file.
- **Cross-examine a panel, never just collect it.** Send each reviewer the others' blocking findings
  plus the strongest counter-evidence against their own, and require concur-or-dissent with a reason.
  Findings that survive attack by a peer lens are worth far more than findings merely gathered.
- **Tell an agent it may refuse your number**, and treat refusal as signal about the number rather
  than about the agent. A compliant one hits the target and hides what it cost.
- **`@`-mentioning an agent definition file means adopt that persona inline** — never a spawn.

## Shell environment
- **The Bash tool's shell sources no startup file** — not `~/.zshenv`, not `~/.zshrc`. Everything in
  the environment arrived by inheritance from the shell that launched Claude Code, so a session
  started before a config change does not see it.
- **That shell is zsh.** Two bash reflexes fail *silently*:
  - **No word splitting on unquoted `$VAR`** — `SSH="ssh -o …"; $SSH host cmd` runs the whole string
    as one command name, exit 127. Use a quoted array: `ssh=(ssh -o …); "${ssh[@]}" host cmd`.
  - **`$PIPESTATUS` is unset**; zsh spells it `$pipestatus` and indexes from **1**, not 0.
  Scripts are unaffected — a `#!/bin/bash` shebang and just's `[script('bash')]` both pin bash.
- **`grep` in the Bash tool is ugrep**, injected as a shell function re-execing Claude Code's own
  binary. It is not exported, so scripts, `just` and CI all get GNU grep, and the two disagree on
  syntax. Nothing is misconfigured; leave the shim alone. **When grep's behaviour is itself under
  test, call `/usr/bin/grep` or invoke the script under test** — a case seeded as a Bash-tool
  pipeline measures a different engine than the code does, and reports a defect that is not there.
- **A pipeline reports the LAST command's status.** `just verify | tail -50` reports `tail`'s exit
  code, so a failing gate reads green. Never append `; echo "exit=$?"` to a pipeline and believe it —
  redirect to a file and test `$?` **on the very next line**, before anything clobbers it.
- **`set -o pipefail` + `grep -q` inverts a successful match.** `-q` exits on the first hit, the
  producer dies of SIGPIPE at 141, and pipefail returns that — so the condition is false *precisely
  when the pattern matches*. Use `grep -c` and compare the count, or match a captured variable with
  `[[ $var == *pat* ]]`. Note `grep -c … || echo 0` emits **two** lines, because grep prints `0` and
  also exits 1.
- **Runtimes are asdf-managed** in `~/.tool-versions` — add one there and re-run `~/dotfiles/install`
  rather than installing by hand.
- **Password prompts are answerable — run them, don't hand them back.** `SSH_ASKPASS`/`SUDO_ASKPASS`
  put the prompt on the desktop; ssh consults it automatically, **sudo only under `sudo -A`**. The
  credential does not cache between Bash calls — no tty means sudo keys the timestamp to a parent
  process that differs every call — so `sudo -A` must sit in the *same* call as the command needing
  it. Headless and cron have no display; the mechanism is a no-op there.
- **If "it passed" would look identical when the thing failed, nothing was measured.** True well past
  the shell: a test with no assertion, a mock that always succeeds, a health check grepping for a
  string absent from healthy *and* unhealthy output.

## `~/dotfiles` auto-publishes to a PUBLIC repo

`dotfiles-sync.timer` runs `tools/sync.sh` every 20 minutes, which does **`git add -A`, commit and
`git push`** to the public `github.com/tjwise99/dotfiles`. No review step, no curation: anything
sitting in that tree is published, whether or not anyone meant it to be.

**These are symlinks into it — write to the right column:**

| Do not write here | Write here |
|---|---|
| `~/.claude/CLAUDE.md` | `~/dotfiles/claude/CLAUDE.md` (this file) |
| `~/.claude/settings.json` | `~/dotfiles/claude/settings.json` |
| `~/.claude/agents/`, `skills/`, `commands/` | `~/dotfiles/claude/{agents,skills,commands}/` |
| `~/lessons/` | `~/dotfiles/notes/lessons/` |
| `~/PROJECT_PLAYBOOK.md` | `~/dotfiles/notes/PROJECT_PLAYBOOK.md` |
| `~/.zshrc` | `~/dotfiles/zsh/zshrc` |
| `~/.gitconfig` | `~/dotfiles/git/gitconfig` |

The Edit tool refuses to write through a symlink, so the left column costs a wasted call. Resolve
with `readlink -f` rather than trusting this table.

**The gitleaks pre-commit hook only catches credential-shaped strings.** It will not stop an SSID, a
MAC address, an internal IP or subnet, a hostname, a device serial, a router model, a person's
address, or a client name. That class is the actual exposure here — not secret-shaped, so nothing
blocks it, and together it fingerprints a home or office network. **Strip identifying detail before
writing into those paths**: describe *"a wall-mounted Pi kiosk"* and *"a LAN host"*. The specifics
belong in the project's own directory, which is not synced. It is installed globally through
`core.hooksPath`, so a repo that sets its own `core.hooksPath` silently runs without it.

Corollary: **a project directory under `~/dotfiles` is a published project.** Put work elsewhere
unless publication is intended.

## GitHub
Account **`tjwise99`**. Use the `gh` CLI for all API work — it authenticates itself, so no prefix is
needed, and it is token-friendly (`--jq`, purpose-built subcommands). Pushes go over SSH with a
passphrase-less key, so they are non-interactive.
- **Standing authorization: commit and push without asking** (user instruction, 2026-07-21) — via
  branch + PR, never direct to a protected default branch, with the repo's verify gate green before
  merge is proposed. Overrides any harness default of "commit only when asked."
- **HARD LIMIT: never merge a PR, and never use `--admin` to bypass branch protection, unless the
  user says so for that specific PR.** The required-review gate exists so a human looks before
  anything lands; "merge the PR" said once about one PR is not a standing merge policy.
- **Confirm the branch in the same command chain as any commit or push** — `git symbolic-ref --short
  HEAD && …`. Parallel sessions can share a worktree and switch HEAD between tool calls; a commit
  once landed on another session's branch. If HEAD is unexpected, stop and check `git worktree list`.
- **Waiting on CI is unreliable here.** `gh run watch --exit-status` can exit 0 immediately instead
  of blocking, and `gh pr checks` lags the check-runs API. Poll `gh api
  repos/<owner>/<repo>/actions/runs/<id> --jq .status` until `completed` instead.
- To restore an MCP server if ever wanted: GitHub needs its own PAT (`claude mcp add --transport http
  github https://api.githubcopilot.com/mcp --header "Authorization: Bearer <PAT>"`); Playwright needs
  an absolute npx path from `asdf which npx`, because MCP spawns without a shell.

## Working style
- **Decisions are the user's — walk trades conversationally first.** Present honest pros and cons in
  prose, not option menus or document dumps; state a lean and let the user call it. Never bury a
  decision in a plan or ADR draft: plan approval is not approval of a decision inside it. Expect
  constraints to surface mid-discussion and flip the outcome.
- **If consent has to be inferred, it wasn't given.** A ruling or clarification about *content*
  answers a different question and leaves the request open; continued engagement is not consent. This
  binds every irreversible or outward-facing action. Two corollaries: **don't perform a gate you
  would walk through anyway** — a manufactured decision point is worse than none — and **when
  authorisation is ambiguous, produce the inspectable form**: write the draft, print the diff, show
  the command. Then the failure mode costs a file rather than a mutation.
- **Never report a procedure as done without running it.** Not "it would pass", not "the diff looks
  compliant" — ran, with the output. Binds every claim of the form "I checked X": run it, or say
  plainly that you did not.
- **Check that the claim you write is the claim you tested.** A correct 404 against one host once
  became "this machine cannot be rebuilt" at the top of a handoff. The check was right, the sentence
  wasn't — and the sentence is what gets acted on.
- **Prove a check can fail before trusting it.** Seed the defect *and* the spelled-differently-but-
  valid variant, because a gate that catches the defect may also reject legal input, and "the seed
  failed correctly" hides that completely. Confirm the seed actually landed — one that silently fails
  to apply looks exactly like a working check. A guard keyed on the same literal as the thing it
  guards cannot see that thing fail; both measurements go to zero together and then agree nothing is
  wrong. A fix is not verified until the finding's **own** reproduction is re-run against it. A step
  added to a sequence must be re-run against every case the sequence already passed, first where the
  steps share mutable state, because there a new step can undo what an existing one exists to produce.
- **Verify a ticket's premise before building against it.** Reproduce the defect it asserts against
  the checks that exist today, and design only once it reproduces. Showing that a new check fires is
  not showing it was needed.
- **Find the document that already decides it before forming a position.** Ask "which document
  decides this?" and read that one, not the one the task handed you.
- **When a correction recurs, stop correcting the instance and find what is not gating the class** —
  and record the reason, so the next editor meets an argument rather than a gap.
- **When you delete a mechanism, grep the whole tree for its name.** A justfile `[doc()]`, a workflow
  step's `name:`, `--help` text — operator-facing documentation lives outside `docs/`, so a prose
  sweep misses it by construction.
- **An unattributed claim in a handoff is agent opinion, not owner ruling.** Owner decisions carry an
  explicit "(owner, <date>)" or a direct quote. A bare imperative sitting among them is something a
  session made up, and the next session reads it back as fact.
- **Never write a bare `#N`, and never use a number as a name.** GitHub draws issues and PRs from one
  counter, so `#66` and `#69` are indistinguishable by shape while being different kinds of object.
  Write **`PR #66`** and **`#69 tree rebuild`** — number *and* name. The same holds for any
  renumberable ID: write `SRS026 backend-unreachable state`, never bare `SRS026`, because a renumber
  rewrites `links:` but not prose.
- **Minimal inline comments.** No narrative blocks, no temporal language ("now", "no longer") — state
  the timeless fact. Prefer the tool's native doc facility (justfile `[doc()]`, `--help`, workflow
  step `name:`). Trim legacy comment density when touching a file rather than matching it.
- **On environment problems, stop and ask.** Root-owned files, EACCES, blocked symlinks, sandbox
  oddities, processes dying on odd signals — do one diagnostic to characterise it, then surface it
  with the specific fix and wait. Don't chain retries or build elaborate workarounds; the user can
  usually fix it in one step.
