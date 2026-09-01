---
description: Turn a discovery brief into a scoped, approved plan — decomposed into work-items, with the implementation shape and PR ownership decided, reviewed for completeness by an independent read, then gated by plan-mode approval before any code.
argument-hint: <issue-number | task description>  (run /discover first)
---

# Plan

Input: **`$ARGUMENTS`**, plus the discovery brief `/discover` produced — the surface map and your
answered decisions. Plan *from that brief*; do not re-run discovery.

**Enter plan mode.** The plan is a contract, not a sketch: it fixes scope, so the implementer builds
exactly this and escalates anything outside it rather than inventing. Runs in orchestrator mode —
delegate any reading still needed; do not open files here. **The plan does not go to approval until an
independent read confirms it settles every decision it requires** (§4) — an author cannot see its own
holes, so approval of a plan the author only *feels* is complete is where invented decisions enter.

## 1. Ground the plan in discovery

- Build only on the surface map and the **answered** decisions. A decision still open is a blocker —
  surface it and stop; do not plan past it.
- If planning reveals a fork discovery missed, treat it the same way: raise it to the human, never pick.
- Scale depth to the work — light for the trivial, thorough for the ambiguous — but never skip the
  pass. Where the ticket already locks the approach, this is fast: confirm the plan matches, note the
  scope boundaries, done.

## 2. Decompose into work-items

- Break the work into the smallest independent items that each finish a coherent piece. This
  decomposition *is* the implementer's brief and the unit of review.
- Each item states: what changes, the **scope boundary** (what it must not touch), the contract it
  must honour, and how it is proven.
- **Mark dependency between items.** Items touching disjoint files with no shared ordering can run in
  parallel; items sharing mutable state must be sequenced. This mark is what decides whether
  implementation fans out to a team or runs as one implementer.

## 3. Decide shape and ownership

- **Implementation shape.** Independent items, or churn-heavy work → a team of implementers, each in
  its **own worktree** (parallel implementers collide in a shared tree). A small, cohesive, sequential
  change → one implementer. Either way it runs in a subagent — orchestrator mode blocks inline edits
  on this thread, so there is no inline option. **Name the agent by fit, not by topic-matching** — an
  architect-flavoured agent chosen by topic will re-make design decisions the plan settled on purpose.
  Where the plan settles the design, an implementer that builds without deciding and halts on ambiguity
  (e.g. `code-monkey`) is the right fit. Match the model to the work; do not default to the heaviest
  for mechanical implementation.
- **Who opens the PR.** Decide explicitly — `/pr-ready` needs one to exist. Either the implementer
  opens it (brief it to) or this thread does after implementation.
- **How review will run.** `/pr-ready` owns this and holds the single copy of the review-mode table.
  Tell it implementation ran in a subagent from a plan this session wrote, and let it decide the mode;
  do not restate the table here.

## 4. Review the plan for completeness

Before approval, the plan gets an independent read — the move `/pr-ready` runs on the diff, one level
up and an order of magnitude cheaper, because no code exists yet. Its target is not whether the plan
is *good* but whether it is *whole*: **what does this plan require the implementer to build that the
plan does not decide?**

- **Delegate it to a fresh context.** Hand a reviewer (e.g. `independent-reviewer`) the ticket, the
  discovery brief, and the drafted plan — **not your account of why it is complete.** An author cannot
  find its own holes; independence is a property of context, not of instruction. Orchestrator mode
  makes this a subagent regardless. This is the pr-ready review pattern, moved one level up — the same
  reliability, applied to the plan instead of the diff.
- **One adversarial question.** What will the implementer have to invent because the plan left it
  open? Every observable the plan does not pin to an authority, every choice handed to implementer
  discretion, anything settled only by *the code already does it* or *I would build it this way* —
  those are open decisions, not made ones. Default to unsettled when unsure.
- **It surfaces, it does not resolve.** Holes come back as open calls — the options and what is at
  stake — never a recommendation dressed as a finding, the contract discovery already holds.

Resolve each hole **with the human, in conversation**, and fold the answers into the plan; anything
still open is escalated, never invented. Only once the plan settles every decision it requires — each
cited to an authority or answered by the human — does it go to approval. That is what keeps the next
step a clean yes on a complete plan rather than a prompt to adjudicate what the plan skipped.

## 5. Approve, then record

- **Exit plan mode for approval before any code is written.** Approval of the plan is not approval of
  a decision buried inside it — call out any decision the plan assumes so it is approved on its own.
- For a ticket, post the approved approach and resolved decisions back with `gh issue comment` so the
  record outlives the session.
- **The plan is not a repo file.** It lives as the plan-mode contract (ExitPlanMode), the `gh issue
  comment` record, and the brief you hand each implementer from this context — `/implement` reads it
  from that brief, not from disk. Do not write a `PLAN.md` into the tree; orchestrator mode denies it,
  and delegating that write to a subagent only launders the gate. If you need a scratchpad, the scratch
  tree (`/tmp/claude-1000/…`) is writable inline.

The deliverable is an approved, decomposed plan — the brief the implementation step consumes.
