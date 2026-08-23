---
description: Take a ticket from scope → mandatory plan → implementation → /pr-ready. Human-gated at planning and merge.
argument-hint: <issue-number>
---

# Work a ticket

Input: issue number **`$ARGUMENTS`**.

**The split of labour.** The main thread (this session) owns scoping, planning, and acts solely as an orchestrator. It will perform no work on its own.
Review, and applying review fixes is delegated to other agents. It plans work and delegates
questions back to the owner for making decision Implementation may runs in a dedicated subagent unless an approved recommendation to work scope inline is accepted; step 2 decides
which. Keeping implementation churn out of the planning/review context is the reason to delegate it,
and the only reason.

**Always open with a planning pass**, however small the ticket looks. The plan _is_ the implementer's
brief, so there is no straight-to-implementation escape hatch.

## 1. Pull the ticket

- Drop into plan mode.
- `gh issue view $ARGUMENTS`, plus anything it depends on. Read it fully.
- Identify: the **base branch** (a milestone ticket usually targets its epic's integration branch, a
  standalone improvement the default branch), any **blockers or dependencies**, and **whether the
  design decisions are already locked in the ticket body**.

## 2. Plan, and get approval

Even a pre-scoped one-line ticket gets a planning pass. Scale depth to the ticket — light for the
trivial, thorough for the ambiguous — but never skip it, and **surface open decisions to the user**
rather than choosing silently. Where the ticket body already locks the approach, this is fast:
confirm the plan matches, note the base branch and scope boundaries, done.

Decide two things explicitly here:

- **Where implementation runs, and by whom.** Small, self-contained ticket → inline on this thread.
  Larger or churn-heavy work → a dedicated implementer subagent, so the planning and review context
  stays clean. **Name the agent, do not leave it to description-matching** — an architect-flavoured
  agent selected by topic will make design decisions this flow put in the plan step on purpose. Where
  the plan settles the design, `code-monkey` is the right implementer: it implements without
  deciding, and halts if the plan turns out to be ambiguous. Pick the model to match the work; do not
  default to the heaviest for mechanical implementation.
- **Who opens the PR.** Decide explicitly, because `/pr-ready` needs one to exist. Either the
  implementer opens it (brief it to) or this thread does after implementation.
- **How review will run.** `/pr-ready` owns this — see its review-mode table, which is the single
  definition. Note the consequence now: _implementation inline on this thread means this session
  cannot review its own work_, and a fresh-context reviewer becomes mandatory rather than optional.

Then **exit plan mode for approval before any code is written.**

Post the approved approach and any resolved decisions back to the ticket (`gh issue comment`) so the
record outlives the session.

## 3. Implement

Once approved, implement per the step-2 decision. Either way:

- **Work in this session's working tree** so the diff can be reviewed in place. (If multiple agents
  are implementing in parallel, they need isolated worktrees — but that is a different flow, and
  parallel implementers sharing one tree will collide.)
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
