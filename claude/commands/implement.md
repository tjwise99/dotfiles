---
description: Execute an approved plan — one implementer in this tree by default, or a team in isolated worktrees converging on one PR when the plan decomposed. Implementers escalate decisions instead of inventing.
argument-hint: <issue-number | task description>  (run /plan first)
---

# Implement

Input: **`$ARGUMENTS`** and the approved, decomposed plan from `/plan` — the work-items, their scope
boundaries and dependency marks, the shape decision, and PR ownership. Build exactly the plan.

**Runs in orchestrator mode: you delegate implementation, you do not write code here.** Coordinate
through subagents, `SendMessage`, and `gh`; the gate blocks inline edits on this thread by design.

## 1. Shape

Follow the plan's shape decision:

- **Sequential (default).** One implementer works the items in dependency order, in this session's
  working tree, so the diff is reviewed in place. Most tickets are this.
- **Parallel (only when the plan marked items independent and chose a team).** One implementer per
  independent item, each in **its own worktree** on **its own branch off the base** — parallel
  implementers sharing a tree collide. They converge to **one PR**: as each finishes, the orchestrator
  integrates its branch onto the single PR branch and resolves any conflict. One review surface per
  ticket; the integration is the orchestrator's job, never a teammate's.

Either way, spawn implementers as **named teammates**, not one-shot subagents: a name makes each a team
member that can `SendMessage` — the channel §3's escalation and the `/pr-ready` review both ride — and
keeps it alive to answer a reviewer directly instead of routing findings back through you. Leave them
running when implementation finishes; `/pr-ready` reaches them for the review pass.

## 2. Brief each implementer

So it need not re-derive context:

- Ticket number and summary; the **base branch** — have it `git switch -c <branch> <base>` first (in
  its own worktree for the parallel case).
- Its **work-item(s)** from the plan: what changes, the **scope boundary** (ticket-only, no drive-by
  changes), the contract it must honour, and how it is proven.
- Repo conventions — match surrounding idiom, comment density, naming.
- The **escalation rule** (§3) and the return contract: **report what changed and the commit/PR refs
  in ≤10 lines; write anything longer to a file.** Fat reports re-pollute the context this delegation
  protects.
- The **review feedback loop the plan named**: it stays alive after implementing, receives the
  reviewer's findings **directly by `SendMessage`**, resolves mechanical ones with the reviewer, and
  escalates anything touching a contract, shared value, abstraction, or the plan (§3) rather than
  patching it. Consumed in the `/pr-ready` review pass.

## 3. Escalate, never invent

The rule every implementer carries, and the reason this flow exists:

**If you hit anything the plan does not settle — a fork, an ambiguity, a design decision, a change
needed outside your item's scope — STOP and `SendMessage` the orchestrator. Do not resolve it
yourself; do not invent an answer or scope.** A choice made because *the code already does it* or *I
would build it this way* is exactly the invented decision this flow exists to prevent. The orchestrator
surfaces the decision to the human and relays the answer back. Unblocked items keep moving meanwhile.

## 4. Run it

- **Open the PR at the start**, not the end — push the branch and `gh pr create --base <base>` so CI
  runs while implementation continues and results are ready for `/pr-ready`.
- **Commit per work-item** — a granular commit as each plan item finishes, with a clear message.
  Checkpoints survive a dead session and give a clean per-item history; squash-merge collapses them
  anyway, so there is no cost to committing often.
- **Verify checks CI-faithfully.** Where a repo documents a local check that diverges from CI —
  typically a package CI installs in isolation but which resolves from a parent directory locally — use
  the repo's CI-faithful recipe or read the CI job. Never sign off on the known-divergent local command.
- **The implementer does not run `/pr-ready` and does not merge.** It reports what changed and the PR
  URL, and stops.

Hand off to **`/pr-ready`** once the PR is open with CI running.
