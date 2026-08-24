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

Run **`/implement $ARGUMENTS`** — it executes the approved plan: one implementer in this tree by
default, or a team of implementers in isolated worktrees converging on one PR when the plan
decomposed. Implementers escalate any decision the plan does not settle instead of inventing, commit
per work-item, and open the PR early so CI runs. The implementer does not run `/pr-ready` or merge.

## 4. Hand off to /pr-ready

The PR is open with CI running. Run **`/pr-ready`**, which owns the rest: verification, the code
review, the documentation sweep, memory housekeeping, and PR hygiene.

**Tell it who wrote the code** — whether implementation ran inline on this thread or in a subagent,
and whether this thread wrote the plan. That is the only input it needs from you: `/pr-ready` owns
the review-mode decision and holds the single copy of that table. Do not re-derive the answer here.

Relay its verdict.

**Do not merge unless the user explicitly asks.** The merge is the irreversible, human-gated step,
and in a repo that publishes artifacts from its default branch it is also a release.
