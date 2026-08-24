---
description: Take a ticket from scope → mandatory plan → implementation → /pr-ready. Human-gated at planning and merge.
argument-hint: <issue-number>
---

# Work a ticket

Input: issue number **`$ARGUMENTS`**.

**The split of labour.** The main thread (this session) owns scoping, planning, and acts solely as an orchestrator. It will perform no work on its own. Typing `/work-ticket` turns orchestrator mode ON automatically, enforcing this mechanically: main-thread `Read`/`Edit`/`Write` and content-dumping `Bash` are denied with a reminder to delegate (`/orchestrate off` to suspend).
Review, and applying review fixes is delegated to other agents. It plans work and delegates
questions back to the owner for making decision Implementation may runs in a dedicated subagent unless an approved recommendation to work scope inline is accepted; step 2 decides
which. Keeping implementation churn out of the planning/review context is the reason to delegate it,
and the only reason.

**Always open with a planning pass**, however small the ticket looks. The plan _is_ the implementer's
brief, so there is no straight-to-implementation escape hatch.

## 1. Discover

- Run **`/discover $ARGUMENTS`** — it pulls the ticket, fans out read-only recon, and brings the open
  decisions up to you *before* anything is planned. Discovery done late, mid-implementation, is the
  failure this flow exists to prevent; do not shortcut it.
- Its output — a surface map and your answered decisions — is the plan's input. Confirm from it the
  **base branch** (a milestone ticket usually targets its epic's integration branch, a standalone
  improvement the default branch) and any **blockers or dependencies**.

## 2. Plan

Run **`/plan $ARGUMENTS`** — it plans from the discovery brief, decomposes the work into items,
decides the implementation shape (one implementer vs a team of implementers in isolated worktrees) and
PR ownership, and gates on plan-mode approval before any code. Do not plan inline; `/plan` owns it,
carrying the base branch confirmed in step 1.

Post the approved approach and resolved decisions back to the ticket (`gh issue comment`) so the record
outlives the session.

## 3. Implement

Once approved, implement per the step-2 decision. Either way:

- **Implement per the plan's shape decision.** One implementer works in this session's tree so the
  diff is reviewed in place; a team of implementers each takes its own worktree, since parallel
  implementers sharing one tree collide.
- **Brief the implementer so it need not re-derive context**: ticket number and summary, base branch
  (have it `git switch -c <branch> <base>` first), the approved plan, **scope boundaries**
  (ticket-only, no drive-by changes), any shared contract it must update if touched, and the repo's
  conventions — match surrounding idiom, comment density, and naming.
- **Commit per work-item.** A granular commit each time a plan task finishes, with a clear message —
  not one giant commit at the end. This checkpoints progress so work survives a dead session, and
  gives a clean per-item history to review. Under squash-merge these collapse anyway, so there is no
  cost to committing often.
- **Open the PR at the start of the work**, not the end. Push the branch and `gh pr create --base
  <base>` so **CI is running while implementation continues** and results are ready by `/pr-ready`.
- **Verify checks CI-faithfully.** Where a repo documents a local check that diverges from CI —
  typically a package CI installs in isolation but which resolves from a parent directory locally —
  use the repo's CI-faithful recipe or read the CI job. Never sign off on the known-divergent local
  command.
- **The implementer does not run `/pr-ready` and does not merge.** It reports what changed and the PR
  URL, and stops.

## 4. Hand off to /pr-ready

The PR is open with CI running. Run **`/pr-ready`**, which owns the rest: verification, the code
review, the documentation sweep, memory housekeeping, and PR hygiene.

**Tell it who wrote the code** — whether implementation ran inline on this thread or in a subagent,
and whether this thread wrote the plan. That is the only input it needs from you: `/pr-ready` owns
the review-mode decision and holds the single copy of that table. Do not re-derive the answer here.

Relay its verdict.

**Do not merge unless the user explicitly asks.** The merge is the irreversible, human-gated step,
and in a repo that publishes artifacts from its default branch it is also a release.
