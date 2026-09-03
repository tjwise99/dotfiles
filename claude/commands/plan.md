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

- **The premise must be confirmed sound first.** Discovery verifies the ticket's problem is real
  against today's tree (`/discover` §1). If the brief does not carry that confirmation — the premise was
  never checked, or came back shaky — send it back for verification rather than planning against an
  assumption; a plan is the most expensive place to discover the ticket was never needed. If the brief
  reports the premise *failed*, do not re-verify or plan: that is a close-or-rescope call for the human.
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
- **How review will run — settle it now, as an approved part of the plan.** The plan must scope far
  enough into `/pr-ready` to state three things, so the review loop is decided here and not improvised
  when the diff lands:
  - **The feedback path — who reviews, and how findings reach the implementer.** This is the one that
    keeps getting skipped: name the **two reviewers** (a content reviewer and a comment/documentation-
    discipline reviewer — `/pr-ready` §6 fixes this split, cite it rather than re-deriving it), name the
    **implementer teammate(s) that stay alive to receive their findings**, and state the **channel** —
    each reviewer takes findings *straight to the implementer* by `SendMessage`; they settle mechanical
    findings between themselves; anything that touches a contract, a shared value, an abstraction, or the
    plan itself escalates to the human. A plan that does not name this leaves the implementer with no
    defined way to get its review feedback, which is the exact failure this step exists to prevent.
  - **The briefing row** — which row of `/pr-ready` §6's briefing table applies, **cited, not restated
    here**; that table stays the single definition of the briefing logic, and the plan only records the
    row. For the `/work-ticket` flow the row is already fixed: code is written by a subagent from a plan
    this thread wrote, and orchestrator mode runs the review as a reviewer–implementer team regardless —
    so the two reviewers are fresh-context teammates (e.g. two `independent-reviewer` teammates, one
    briefed for content and one for documentation discipline), told to treat the plan itself as suspect,
    feeding the implementer teammate(s) `/implement` leaves running.
  - **The ticket-specific criteria** the review must verify — the checks particular to *this* change (a
    contract it must not break, an observable it must preserve, an edge case discovery surfaced), on top
    of `/pr-ready`'s generic checklist.

  These review params are approved with the plan in §5; `/pr-ready` consumes them rather than
  re-deciding the briefing row or re-deriving the loop.

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
- **The review params (§3) are in scope for this read, not just implementer-facing holes.** The
  feedback path is an orchestration decision the implementer does not build, so the adversarial
  question above would walk past a half-specified one — check it explicitly: are both reviewers named,
  the live implementer teammate(s) named, the channel and the escalation boundary stated? A missing or
  vague feedback path is the failure §3 exists to prevent, and the author's own §3 is where it hides —
  so the independent read, not author self-assessment, must confirm it.
- **It surfaces, it does not resolve.** Holes come back as open calls — the options and what is at
  stake — never a recommendation dressed as a finding, the contract discovery already holds.

Resolve each hole **with the human, in conversation**, and fold the answers into the plan; anything
still open is escalated, never invented. Only once the plan settles every decision it requires — each
cited to an authority or answered by the human — does it go to approval. That is what keeps the next
step a clean yes on a complete plan rather than a prompt to adjudicate what the plan skipped.

## 5. Approve, then record

- **Do not propose the plan while any question is open.** The `ExitPlanMode` call *is* the proposal —
  it must not fire until every open decision from discovery (§1) and every hole the completeness read
  turned up (§4) has been answered by the human, review params (§3) included. Plan-mode entry fires no
  hook, so this cannot be gated mechanically; it holds as an instruction, and an unanswered decision
  blocks the proposal, no exceptions. Presenting a plan with an "open question" or "TBD" still in it is
  the failure this step exists to prevent.
- **Exit plan mode for approval before any code is written.** Approval of the plan is not approval of
  a decision buried inside it — call out any decision the plan assumes so it is approved on its own.
- For a ticket, post the approved approach and resolved decisions back with `gh issue comment` so the
  record outlives the session.
- **The plan is not a repo file.** It lives as the plan-mode contract (ExitPlanMode), the `gh issue
  comment` record, and the brief you hand each implementer from this context — `/implement` reads it
  from that brief, not from disk. Do not write a `PLAN.md` into the tree; orchestrator mode denies it,
  and delegating that write to a subagent only launders the gate. If you need a scratchpad, the scratch
  tree (`/tmp/claude-1000/…`) is writable inline.

The deliverable is an approved, decomposed plan — with its review params settled (§3) — the brief the
implementation and review steps both consume.
