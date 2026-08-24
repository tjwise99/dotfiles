---
description: Turn a discovery brief into a scoped, approved plan — decomposed into work-items, with the implementation shape and PR ownership decided, gated by plan-mode approval before any code.
argument-hint: <issue-number | task description>  (run /discover first)
---

# Plan

Input: **`$ARGUMENTS`**, plus the discovery brief `/discover` produced — the surface map and your
answered decisions. Plan *from that brief*; do not re-run discovery.

**Enter plan mode.** The plan is a contract, not a sketch: it fixes scope, so the implementer builds
exactly this and escalates anything outside it rather than inventing. Runs in orchestrator mode —
delegate any reading still needed; do not open files here.

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
  change → one implementer, or inline on this thread. **Name the agent by fit, not by
  topic-matching** — an architect-flavoured agent chosen by topic will re-make design decisions the
  plan settled on purpose. Where the plan settles the design, an implementer that builds without
  deciding and halts on ambiguity (e.g. `code-monkey`) is the right fit. Match the model to the work;
  do not default to the heaviest for mechanical implementation.
- **Who opens the PR.** Decide explicitly — `/pr-ready` needs one to exist. Either the implementer
  opens it (brief it to) or this thread does after implementation.
- **How review will run.** `/pr-ready` owns this — see its review-mode table. Note the consequence
  now: implementation inline on this thread means this session cannot review its own work, so a
  fresh-context reviewer becomes mandatory, not optional.

## 4. Approve, then record

- **Exit plan mode for approval before any code is written.** Approval of the plan is not approval of
  a decision buried inside it — call out any decision the plan assumes so it is approved on its own.
- For a ticket, post the approved approach and resolved decisions back with `gh issue comment` so the
  record outlives the session.

The deliverable is an approved, decomposed plan — the brief the implementation step consumes.
