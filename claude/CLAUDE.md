# Host & tooling context

Global notes for working on this WSL host. Not project-specific — per-project context lives in that
project's own `CLAUDE.md` (and a gitignored `CLAUDE.local.md` for machine/secret specifics).

## The user
Aerospace background: V-model requirements rigor (SYS→SRS→TST) and traceability-first thinking —
when docs tooling feels "unusable," suspect the traceability/information-design layer before the
chrome. Treats AI tooling as a first-class repo reader: source files stay byte-identical, plain
GFM/YAML, no frontmatter or generator dialects.

## Shell environment
- Bash tool runs **non-interactive** shells that **don't source the interactive rc** (`~/.zshrc`, and
  so not `dotfiles/shell/common.sh` behind it) — env from the login profile isn't guaranteed. `node` is normally on `PATH` regardless, inherited from the shell that
  launched Claude Code. If it is missing: `export PATH="$HOME/.asdf/shims:$PATH"`. Runtimes are
  managed by asdf and declared in `~/.tool-versions` (from the dotfiles repo) — install a new one by
  adding it there and re-running `~/dotfiles/install`, not by hand.
- `python3` and Docker are available. `jq` is asdf-managed at `~/.asdf/shims/jq` — there is no
  `/usr/bin/jq`, so a script run without the shims on `PATH` gets exit 127, not a jq error.
- **In the Bash tool's shell, `grep` is not GNU grep.** Claude Code injects a `grep` shell function
  that re-execs its own binary as ugrep (`exec -a ugrep "$CLAUDE_CODE_EXECPATH" -G --ignore-files …`).
  The two disagree on syntax — ugrep takes `(?:…)` as a non-capturing group under `-E`, GNU grep
  rejects it. The function is **not exported**, so scripts (`#!/bin/bash`, `sh`, `just`, CI) all get
  `/usr/bin/grep` — GNU grep 3.12. Nothing is misconfigured; leave the shim alone.
  **When grep's behaviour is itself under test, call `/usr/bin/grep` or invoke the script under test.**
  A doctored-regex case seeded as a bash pipeline measures a different engine than the code does, and
  reports a defect that is not there — this inverted a reviewer's finding on PR #88.
- **A pipeline reports the LAST command's status.** `just verify | tail -50` reports `tail`'s exit
  code, so a failing gate reads as green — this nearly got reported as a passing `verify`. Never
  append `; echo "exit=$?"` to a pipeline and believe it. Redirect to a file and test `$?`, or
  capture `st=("${PIPESTATUS[@]}")` **on the very next line** — `PIPESTATUS` is clobbered by the
  following command, including the `echo` used to read it.
- **`set -o pipefail` + `grep -q` inverts a successful match.** `grep -q` exits on the first hit, the
  producer takes SIGPIPE and dies 141, and `pipefail` returns that — so the condition is false
  *precisely when the pattern matches*. It silently turned a whole service-disabling script into a
  no-op. Worse, it is invisible from here: the Bash tool's ugrep shim returns 0 while the same line
  in a `#!/bin/bash` script returns 141. Test the tool directly (`systemctl is-enabled X`), match a
  captured variable with `[[ $var == *pat* ]]`, or use `grep -c` and compare the count.
- **The general form of both: if "it passed" would look identical when the thing failed, nothing was
  measured.** Applies past the shell — a test with no assertion, a mock that always succeeds, a
  health check grepping for a string absent from healthy *and* unhealthy output.
- **Password prompts are answerable — run them, don't hand them back.** No tty but a display is
  set, so `SSH_ASKPASS`/`SUDO_ASKPASS` (→ `bin/zenity-askpass`, exported by `shell/common.sh` when
  `zenity` is installed and `DISPLAY`/`WAYLAND_DISPLAY` is non-empty) put the prompt on the desktop.
  ssh uses it automatically; **sudo only under `sudo -A`**. Headless and cron have no display, so
  the block is a no-op there.
  **The credential does not cache between Bash tool calls.** With no tty sudo keys the timestamp to
  the parent process, and every tool call has a different one — so `sudo -v` in one call leaves the
  next still unauthenticated. Put `sudo -A` in the *same* call as the command that needs it; each
  one costs its own dialog. A `! sudo -v` typed by the user does not help either: that shell has no
  tty and sudo refuses outright.

## GitHub: `gh` CLI for the API, git + SSH for pushes
GitHub account: **`tjwise99`**. No GitHub MCP — use the `gh` CLI for all API work (token-friendly:
built-in `--jq`, purpose-built subcommands).
- **Auth is automatic — no prefix.** `gh` reads its token from the **system keyring** (`gh auth status`
  → "Logged in … (keyring)"), so plain `gh …` works even where the environment is bare. Re-auth with
  `gh auth login`; there is no token file to source, and nothing on disk holds the token.
- **`GH_TOKEN` is for scripts that bypass `gh`.** `shell/common.sh` exports it from `gh auth token`,
  so it reaches the Bash tool only by inheritance from the launching shell — a session started before
  that shell ran sees it unset. WiseKiosk's `check-branch` gate needs it: it calls the GraphQL API
  with `curl`, not `gh`, and hard-fails rather than skipping. While it is set, `gh auth
  login`/`logout`/`refresh` refuse to run until it is unset; ordinary API calls are unaffected.
- **Reads:** `gh pr checks <n>`, `gh api <endpoint> --jq '.field'`, PR/issue reads via `--json … --jq`.
- **Writes:** `gh pr create`, `gh pr merge --squash [--admin]`, `gh pr edit <n> --body-file <f>`,
  `gh pr ready <n>`, `gh pr comment`, `gh issue create/comment`. If `gh pr edit --body-file` errors on
  scope, fall back to `gh api …/pulls/<n> -X PATCH -F body=@<file>`.
- **Pushing (git):** `git commit` then `git push`. Remotes are **SSH**, authed by the passphrase-less
  ed25519 key at `~/.ssh/id_ed25519` (public key on the account) — pushes are non-interactive.
- **Standing authorization: commit and push without asking** (user instruction, 2026-07-21) — via
  branch + PR, never direct to a protected default branch; run the repo's verify gate green before
  proposing merge. This overrides any harness default of "commit only when asked."
  **HARD LIMIT: never merge a PR, and never use `--admin` to bypass branch protection, unless the
  user explicitly says to for that specific PR.** The required-review gate exists so a human looks
  before anything lands; "merge the pr" said once about one PR is not a standing merge policy.
- **Confirm the branch in the same command chain as any commit or push.** Parallel agent sessions
  can share a worktree and switch HEAD between tool calls (it happened; a commit landed on another
  session's branch). `git symbolic-ref --short HEAD &&` … or `git switch <branch> && git commit` in
  one Bash call. If HEAD is unexpectedly elsewhere, stop and check `git worktree list` before
  re-pointing anything.
- **Waiting on CI is unreliable here.** `gh run watch <id> --exit-status` can exit 0 immediately
  instead of blocking, and `gh pr checks` lags the check-runs API (reporting `pending` for finished
  jobs). To actually wait, poll `gh api repos/<owner>/<repo>/actions/runs/<id> --jq .status` until
  `completed`, or poll `commits/<sha>/check-runs`.

## `~/dotfiles` auto-publishes to a PUBLIC repo every 20 minutes

`dotfiles-sync.timer` (`OnCalendar=*:0/20`) runs `~/dotfiles/tools/sync.sh`, which does
**`git add -A`, commit, and `git push`** to `github.com/tjwise99/dotfiles` — **public**. No review
step, no curation: anything sitting in that tree gets published within 20 minutes, whether or not
anyone meant it to be.

**Writing to any of these writes to a public repo**, because they are symlinks into it:

| Symlink — do not write here | Real path — write here |
|---|---|
| `~/.claude/CLAUDE.md` | `~/dotfiles/claude/CLAUDE.md` (this file) |
| `~/.claude/settings.json` | `~/dotfiles/claude/settings.json` |
| `~/.claude/agents/`, `~/.claude/skills/` | `~/dotfiles/claude/agents/`, `~/dotfiles/claude/skills/` |
| `~/lessons/` | `~/dotfiles/notes/lessons/` |
| `~/PROJECT_PLAYBOOK.md` | `~/dotfiles/notes/PROJECT_PLAYBOOK.md` |
| `~/.zshrc` | `~/dotfiles/zsh/zshrc` |
| `~/.gitconfig` | `~/dotfiles/git/gitconfig` |

**Write to the right column.** The Edit tool refuses to write through a symlink, so the left column
costs a wasted call. Targets verified with `readlink -f`, not copied from memory — if a path here
does not resolve, re-check rather than guessing the layout.

**A gitleaks pre-commit hook runs, and it only catches credential-shaped strings.** It will not stop
an SSID, a MAC address, an internal IP or subnet, a hostname, a device serial, a router model, a
person's address, or a client name. That class of detail is the actual exposure here — it is not
secret-shaped, so nothing blocks it, and together it fingerprints a home or office network. Notes
written up from a real system are exactly where it appears.

So: **before writing anything into those paths, strip identifying detail** — describe *"a
wall-mounted Pi kiosk"* and *"a LAN host"*, never the SSID, the address, or the serial. Keep the
specifics in the project's own directory, which is not synced. `~/dotfiles/.gitignore` covers
`local/*`, `*.key`, `*.pem` and the Claude credential files — nothing else.

Corollary for new projects: **a project directory under `~/dotfiles` is a published project.** Put
work elsewhere unless publication is intended.

## MCP servers
**None configured** (`claude mcp list` → "No MCP servers configured"). Both were removed at the user's
request; GitHub work goes through `gh`, browser automation through the Playwright CLI. To restore:
- **github** (removed 2026-07-18): `claude mcp add --transport http github https://api.githubcopilot.com/mcp --header "Authorization: Bearer <PAT>"` — needs a PAT minted for it; the keyring token
  belongs to `gh` and no environment variable carries one for this.
- **playwright** (removed 2026-07-15): MCP spawns without a shell, so `command` must be an absolute
  npx path and there's no system node — get the current one with `asdf which npx`, then
  `claude mcp add-json playwright '{"type":"stdio","command":"<npx-path>","args":["-y","@playwright/mcp@latest"],"env":{}}'`

## Working style
- **`@`-mentioning an agent definition file means adopt that persona inline** — read the definition
  and apply its lens in the current session. It is never by itself an instruction to spawn.
- **Durable guidance goes in CLAUDE.md, not auto-memory.** The user hates digging through memory
  files. Preferences and working rules like these belong here (or the project's CLAUDE.md or CLAUDE.local.md if
  project-specific); reserve auto-memory for transient work state, if that.
- **Cross-project learnings live in `~/lessons/`** — topic files, newest dated entry first, indexed
  in its README, which states the bar. **Propose an entry; never write one unprompted**, and say in
  one line what it would claim and which file it joins. Silence is the normal outcome: a task ending
  is not a lesson, and an entry that only makes sense with one repository's structure in mind belongs
  in that repository instead. Propose only when one of these has actually happened, and only where
  it would change a decision on a different project:
  - The user reversed a position you argued for, and the reversal turned on something readable
    before you argued it.
  - You built against a premise and then found the document that had already decided it.
  - A claim you reported turned out to be false when it was checked.
  - A tool or environment trap took more than one attempt to get past, and is not machine-specific
    (machine-specific goes in the project's `CLAUDE.local.md`).
- **Decisions are the user's — walk trades conversationally first.** Never bury a decision in a
  plan or ADR draft: plan approval is not approval of a decision inside it. Present honest
  pros/cons in prose (not option menus or document dumps), state a lean, and let the user call it;
  expect constraints to surface mid-discussion and flip the outcome.
- **If consent has to be inferred, it wasn't given.** An action flagged as needing approval does not
  happen until the user's words, read on their own, authorise *that action*. A ruling, correction or
  clarification about **content** answers a different question and leaves the request open — re-ask
  once, briefly, or don't act. Continued engagement is not consent. This binds every irreversible or
  outward-facing action, not one class of them: writes, deletes, commits, pushes, config changes,
  outbound calls.
- **Don't perform a question you'll override.** If you would proceed regardless, don't ask. A
  manufactured gate you then walk through is worse than no gate, because it tells the user a decision
  point exists when it does not.
- **When authorisation is ambiguous, produce the inspectable form.** Write the draft to a file, print
  the diff, show the command — do not perform the action. Then the failure mode costs a file rather
  than a mutation. This is the one that holds when the two above fail, which they will.
- **Minimal inline comments.** No narrative blocks; no temporal language ("now", "no longer") —
  state the timeless fact. Prefer the tool's native doc facility (justfile `[doc()]`, `--help`
  text, workflow step `name:`); at most a one-line note for a genuinely non-obvious mechanism.
  Don't match legacy comment density in older files; trim when touching.
- **Be concise.** Report routine confirmations (tests pass, pushed, CI green, deployed) in a line or
  two; reserve fuller write-ups for decision points, tradeoffs, and findings.
- **Never write a bare `#N`, and never use a number as a name.** GitHub draws issues and PRs from one
  counter, so `#66` and `#69` are indistinguishable by shape while being different kinds of object —
  and `gh issue view <PR number>` resolves a PR, so the CLI blurs it too. Write **`PR #66`** for a
  pull request, and **`#69 tree rebuild`** — number *and* name — for a ticket. In prose the name
  carries the meaning; the number is only the handle to look it up.
  **The same holds for any renumberable identifier** — write `SRS026 backend-unreachable state`, never
  bare `SRS026`: a renumber rewrites `links:` but not prose, so a bare ID silently resolves to whatever
  now occupies it, while a name still finds the item.
- **Shape every tool output at the source — never dump.** Tool output dominates context: `| grep -E`
  for test/lint summary lines, `gh … --jq` over raw `gh`, `git --oneline/-1/--stat`, `head`/`tail` on
  anything unbounded.
- **A subagent's deliverable is a file it wrote, never its prose.** A background agent signals
  completion with a contentless idle notification, so *answered in prose* and *was denied permission*
  are indistinguishable from the coordinator: both are a notification and an empty directory. Brief
  every agent to write its result to a path you name **and** to reply via `SendMessage` (plain output
  never arrives), then `ls` the path before treating the notification as completion. Use
  `run_in_background: false` when the result is needed inline. `Write` sits in no allow-list under
  `defaultMode: auto`, so an agent that hits an approval decision is denied with nobody to ask — have
  it serialise with `cat > <path> <<'EOF'`, which matches the allow-listed `Bash(cat:*)`.
- **Verify a ruling landed in the tree; do not read the agent's status list.** An implementer may file a
  coordinator's ruling as a note rather than applying it — three times on #68 — and "unchanged from last
  report" means either *not done* or *done earlier*, indistinguishable. `grep` the file. Two related
  traps: an agent that overwrites its report in place gives a reader between two writes stale text with
  nothing indicating which version they hold, so ask for the head SHA in the file; and messages cross, so
  a ruling and a status report can each be written without sight of the other.
- **Tell a subagent it may refuse your number, and treat refusal as signal.** An agent twice declined a
  word target rather than silently pick facts to drop; both times the target was wrong, not the writing.
  A compliant one would have hit it and hidden the cost. When delegating verification, name the baseline
  — otherwise two true numbers disagree.
- **Freeze the branch while reviewers read it, and mean it.** On #68 I insisted on this, then edited the
  exact file a reviewer was attacking. Its findings survived only because it tested clean `git archive`
  extractions and recorded the md5 of what it read. Brief reviewers to do that; do not rely on it.
- **Cross-examine a review panel; never just collect it.** Findings that survive attack by a peer
  lens are worth an order of magnitude more than findings merely gathered. Send each reviewer the
  others' blocking items plus the strongest counter-evidence against their own, and require
  concur-or-dissent with a reason. In the PR #66 pass this reversed one severity vote, rejected one
  finding 2–1, and struck two evidence legs — two of them the coordinator's own.
- **Batch independent calls and read surgically.** Fire independent Read/Grep/Bash calls in one
  message so they run in parallel; prefer `Grep` and `Read` offset/limit over whole-file reads.
- **Find the document that already decides it before forming a position.** Ask "which document
  decides this?" and read that one, not the one the task handed you. On WiseKiosk #96 every
  significant error had this shape: an aggregate upstream element leaned on before reading the ADR
  ruling that a module's upstream is specification rather than configuration; verification prose
  written into three files without opening the one whose entire purpose is holding it; an ADR built
  out past what its own template says earns an ADR. Twice the deciding document had already been
  read and was ignored, twice it was never opened. The owner reversed all four by naming the
  document — which is cheaper than the argument, and available before the work rather than after.
- **Never report a procedure as done without running it.** Not "it would pass", not "the diff looks
  compliant" — ran, with the output. A ticked checklist box on WiseKiosk PR #113 claimed the review
  checklist was walked when it had not been; walking it found a comment describing a deleted step,
  which had survived a grep for the deleted mechanism's *name* because the comment described it
  without naming it. Nothing failed, CI was green, and the false claim would have reached merge. The
  same rule binds every claim of the form "I checked X": run it, or say plainly that you did not.
- **Check that the claim you write is the claim you tested.** A correct 404 against one host became
  "this machine cannot be rebuilt" at the top of a handoff; the archive had moved and still served the
  exact package. The check was right, the sentence wasn't — and the sentence is what gets acted on.
- **Verify a ticket's premise before building against it.** Reproduce the defect it asserts against the
  checks that exist today, and design only after it reproduces. #80 described a re-parent the gate
  already caught; an implementation, its wiring, five documents and a review pass were all built before
  anything tested whether the hole was open. Showing a new check *fires* is not showing it was *needed*
  — seed the defect and run the existing gate first.
- **Seed the legal variant too, not only the defect.** A check that fires on the defect may also fire
  on valid input, and "the seed failed correctly" hides that completely. On #68 two fail-open fixes each
  introduced a fail-closed in the same function — a Dependabot guard that rejected a legal block-list
  `patterns:`, and fence-blanking that made an unterminated fence hide the rest of the file. Both passed
  the defect seed. For every gate, seed **both** directions: the thing it must catch, and the
  spelled-differently-but-valid thing it must not. Also check the seed actually applied — a seed that
  silently fails to land looks exactly like a working check.
- **A guard keyed on the same literal as the thing it guards cannot see that thing fail.** Both
  measurements go to zero together and then agree that nothing is wrong. #68 hit this three times on one
  finding: a count of `package-ecosystem:` lines validating a split on that literal, then a count of
  `updates:` items validating a split on *that*. The form that worked shares no assumption — assert the
  parse produced something at all. When adding a guard, ask what it would report if the parser it guards
  returned nothing.
- **When you delete a mechanism, grep the whole tree for its name.** Re-reading the documents you
  rewrote cannot reach the artifacts that name it somewhere else — a justfile `[doc()]`, a workflow
  step's `name:`, `--help` text. Those are the *operator-facing* documentation and live in neither
  `docs/` nor the ADR, so a prose sweep misses them by construction. On PR #91 three documents were
  rewritten three times while both of those still advertised a deleted file, and a green check on the
  PR was named after it. This is the inverse of preferring the tool's native doc facility: what you
  write there, you must also sweep there.
- **A fix is not verified until the finding's own reproduction is re-run against it.** Not a fresh
  case you wrote, not the reasoning that the fix must work — the exact command that demonstrated the
  defect. On PR #91 a fix that was obviously correct on inspection still returned exit 0 on the
  reviewer's original command, because it closed a neighbouring path rather than the reported one.
  Shipping on the reasoning would have merged a bypass under an ADR asserting it was closed.
- **A step added to a sequence must be re-run against every case the sequence already passed**, not
  only the case it was added for — and first wherever the steps share mutable state, because there
  the new one can undo what an existing one exists to produce. On WiseKiosk #96 the architecture gate
  ran `rm -rf <generated>` so a stale artifact showed up as a deletion; adding `git add
  --intent-to-add` to catch a *different* hole then staged that deletion, and the diff read worktree
  and index as agreeing. One hole closed, the other silently reopened, on the same index. It survived
  a full local `verify`, six commits and a green CI run — CI proved nothing, because the repository
  held no stale artifact, so the gate had nothing to miss. The individual cases were the wrong unit
  of suspicion; the interaction was. Where three steps cooperate, prove each necessary by deleting it
  and re-running **all** the cases, and record that grid rather than a list of passing rows.
- **When a correction recurs, stop correcting it and go find what is not gating it.** An enumeration
  in one handoff was wrong in six consecutive passes — the gate count, the named checks, then its
  replacement — and each time the instance was fixed while the class survived, twice after a reviewer
  had already named it. It closed only when the fix stopped being a better number and became *"the
  table is examples, not an inventory"*, **with the reason recorded**: nothing compares it to the
  tree, so the next contributor to add one makes it wrong with nothing to say so. A later editor
  wanting to "complete" it now meets an argument instead of a gap.
- **An unattributed claim in a handoff is agent opinion, not owner ruling.** Owner decisions carry an
  explicit attribution — "(owner, <date>)" or a direct quote. A bare imperative sitting among them is
  something a session made up, and the next session reads it back as fact. One recommended a merge
  strategy the owner had never held.
- **On environment problems, stop and ask.** Root-owned files, EACCES, blocked symlinks, sandbox
  oddities, processes dying on odd signals — do ONE diagnostic (`ls -la`) to characterize it, then
  surface it with the specific fix and wait. Don't chain retries or build elaborate workarounds; the
  user can usually fix it in one step. (Learned the expensive way: a session burned a large chunk of
  its budget improvising around root-owned `node_modules` that later cleared on its own.)
