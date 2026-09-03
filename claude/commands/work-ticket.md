---
description: Take a ticket from scope → mandatory plan → implementation → /pr-ready. Human-gated at planning and merge.
argument-hint: <issue-number>
---

# Work a ticket

Input: issue number **`$ARGUMENTS`**.

**The split of labour.** The main thread (this session) owns scoping and planning and acts solely as
an orchestrator — it performs no file work itself. Typing `/work-ticket` turns orchestrator mode ON
automatically, enforcing this mechanically: main-thread `Read`/`Edit`/`Write`, the `Grep`/`Glob`
tools, and content-dumping `Bash` are denied with a reminder to delegate (`/orchestrate off` to
suspend). Discovery, implementation, review, and applying review fixes all run in subagents; the
thread plans the work and routes decisions back to you. Keeping implementation churn out of the
planning and review context is the reason to delegate, and the only reason.

**Always open with a planning pass**, however small the ticket looks. The plan _is_ the implementer's
brief, so there is no straight-to-implementation escape hatch.

## 1. Discover

- Run **`/discover $ARGUMENTS`** — it pulls the ticket, fans out read-only recon, and brings the open
  decisions up to you *before* anything is planned. Discovery done late, mid-implementation, is the
  failure this flow exists to prevent; do not shortcut it.
- **Its first job is to verify the ticket's premise** — that the problem is real against today's tree.
  If discovery reports the premise does not hold (the tree already handles it, the defect won't
  reproduce), the ticket ends here: take it to the human to close or rescope, and do not proceed to
  planning. This is the cheapest possible place to catch a ticket that never needed building.
- Its output — a surface map and your answered decisions — is the plan's input. Confirm from it the
  **base branch** (a milestone ticket usually targets its epic's integration branch, a standalone
  improvement the default branch) and any **blockers or dependencies**.

## 2. Plan

Run **`/plan $ARGUMENTS`** — it plans from the discovery brief, decomposes the work into items,
decides the implementation shape (one implementer vs a team of implementers in isolated worktrees) and
PR ownership, and **settles the review parameters as part of the plan** — the two reviewers (content
and comment/documentation-discipline), the implementer teammate(s) that stay alive to receive their
findings, the feedback channel between them, the briefing row, and the ticket-specific criteria — so
how an implementer gets its review feedback is decided here, not improvised at `/pr-ready`. It gates on
plan-mode approval before any code. **The plan is not proposed for approval while any decision — from
discovery or from the plan's own completeness read — is still open.** Do not plan inline; `/plan` owns
it, carrying the base branch confirmed in step 1. `/plan` records the approved approach back to the
ticket.

## 3. Implement

Run **`/implement $ARGUMENTS`** — it executes the approved plan: one implementer in this tree by
default, or a team of implementers in isolated worktrees converging on one PR when the plan
decomposed. Implementers escalate any decision the plan does not settle instead of inventing, commit
per work-item, and open the PR early so CI runs. The implementer does not run `/pr-ready` or merge.

## 4. Hand off to /pr-ready

The PR is open with CI running. Run **`/pr-ready`**, which owns the rest: verification, the code
review, the documentation sweep, memory housekeeping, and PR hygiene.

**Point it at the plan's review params** — the two reviewers, the live implementer teammate(s), the
feedback channel, the briefing row, and the ticket-specific criteria were all settled in step 2.
`/pr-ready` **consumes them, it does not re-decide the briefing row or re-derive the feedback loop**;
the briefing table it holds is the menu the plan already selected from. Do not re-derive the answer
here — that is how the review loop the plan pinned down gets replaced with an improvised one.

Relay its verdict.

**Do not merge unless the user explicitly asks.** The merge is the irreversible, human-gated step,
and in a repo that publishes artifacts from its default branch it is also a release.

**Orchestrator mode is still on** (it has an 8h expiry). When the ticket is done, tell the human the
mode is still active and offer `/orchestrate off` so an ordinary conversation is not left gated.
