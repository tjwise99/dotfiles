---
description: Turn a discovery brief into a scoped, approved plan — decomposed into work-items, with the implementation shape and PR ownership decided, reviewed for completeness and overbuild by paired independent reads, then gated by plan-mode approval before any code.
argument-hint: <issue-number | task description>  (run /discover first)
---

# Plan

Input: **`$ARGUMENTS`**, plus the discovery brief `/discover` produced — the surface map and your
answered decisions. Plan *from that brief*; do not re-run discovery.

**Enter plan mode.** The plan is a contract, not a sketch: it fixes scope, so the implementer builds
exactly this and escalates anything outside it rather than inventing. Runs in orchestrator mode —
delegate any reading still needed; do not open files here. **The plan does not go to approval until an
independent read confirms it settles every decision it requires, and a second confirms it specifies
nothing the ticket does not need** (§4) — an author cannot see its own holes or its own excess, so
approval of a plan the author only *feels* is complete and lean is where invented decisions and
unneeded work enter.

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
- **Test-first pairing (TDD).** For any work-item that produces testable behaviour, pair a `test-first`
  teammate with the `code-monkey` implementer: `test-first` writes the failing tests that encode the
  item's contracts **before** `code-monkey` writes code, and `code-monkey` makes them green without
  modifying them (its standing rule). Default to **batch red-then-green per work-item** — `test-first`
  commits the failing tests as a RED checkpoint, then hands off — and note the item where an
  **interleaved** test↔code loop is wanted instead. A work-item with **no meaningful test surface**
  (pure docs or config) skips the pairing, but the plan **states that skip explicitly** — an unrecorded
  skip is how TDD quietly lapses. Both are named teammates so the red→green handoff and any test↔code
  contract dispute run over `SendMessage`, escalating to the human when the spec does not decide.
- **Who opens the PR.** Decide explicitly — `/pr-ready` needs one to exist. Either the implementer
  opens it (brief it to) or this thread does after implementation.
- **How review will run — settle it now, as an approved part of the plan.** The plan must scope far
  enough into `/pr-ready` to state three things, so the review loop is decided here and not improvised
  when the diff lands:
  - **The feedback path — who reviews, and how findings reach the implementer.** This is the one that
    keeps getting skipped: name the **three reviewers** (a content reviewer, a comment/documentation-
    discipline reviewer, and a test-quality reviewer using the `testing-architect` agent — `/pr-ready`
    §6 fixes this split, cite it rather than re-deriving it), name the **implementer teammate(s) that
    stay alive to receive their findings**, and state the **channel** — each reviewer takes findings
    *straight to the implementer* by `SendMessage`; they settle between themselves any mechanical or
    readability finding, restructures included, whose fix changes no interface, contract, shared value,
    abstraction, or decision the plan made, the implementer returning each fix to the raising reviewer
    for a re-read; a finding whose class is likely to recur also carries a recommendation for a tool
    that would check it automatically, which goes to the human to ticket or take in scope; any
    ambiguity, any design decision, anything that touches a contract, a shared value, an abstraction, or
    the plan itself escalates to the human. A plan that does not name this leaves the implementer with
    no defined way to get its review feedback, which is the exact failure this step exists to prevent.
    **On a TDD-paired item, name where a test-quality finding on a `test-first`-authored test goes** —
    not to `code-monkey`, which cannot edit tests. If the finding says the test wrongly encodes or omits
    a spec'd contract, it is a requirement question and escalates to the human; if it is mechanical
    post-code test repair, it belongs to `test-writer-fixer` (the after-code test agent). `test-first`
    is gone by review time, so it is never the owner.
  - **The briefing row** — which row of `/pr-ready` §6's briefing table applies, **cited, not restated
    here**; that table stays the single definition of the briefing logic, and the plan only records the
    row. For the `/work-ticket` flow the row is already fixed: code is written by a subagent from a plan
    this thread wrote, and orchestrator mode runs the review as a reviewer–implementer team regardless —
    so the three reviewers are fresh-context teammates (e.g. two `independent-reviewer` teammates — one
    briefed for content and one for documentation discipline — plus a `testing-architect` teammate
    briefed for test quality and spawned review-only, no edit tools), told to treat the plan itself as
    suspect, feeding the implementer teammate(s) `/implement` leaves running.
  - **The ticket-specific criteria** the review must verify — the checks particular to *this* change (a
    contract it must not break, an observable it must preserve, an edge case discovery surfaced), on top
    of `/pr-ready`'s generic checklist. **They are a floor beneath the content reviewer's two questions
    (`/pr-ready` §6), never its mandate.** **Each criterion cites an authority outside this plan** — the
    ticket, a contract discovery found in the tree, an edge case discovery surfaced. An item whose
    honest source is "the plan decided it" is a ruling, not a criterion, and stays out: the reviewer
    already checks rulings against the plan itself, and §2's contracts restated here turn the content
    review into a compliance audit.

  These review params are approved with the plan in §5; `/pr-ready` consumes them rather than
  re-deciding the briefing row or re-deriving the loop.

## 4. Review the plan: completeness and overbuild

Before approval, the plan gets two independent reads, run as a pair — the move `/pr-ready` runs on the
diff, one level up and an order of magnitude cheaper, because no code exists yet. Neither asks whether
the plan is *good*. The **completeness read** asks whether it is *whole*: **what does this plan require
the implementer to build that the plan does not decide?** The **overbuild read** asks whether it is
*lean*: **what does this plan specify that the ticket does not need?** The two pull in opposite
directions, which is why they are separate reviewers and not one brief.

- **Delegate both to fresh contexts.** Hand each reviewer (e.g. `independent-reviewer`) the ticket, the
  discovery brief, the drafted plan, and its own read's question and bullets below copied into the
  brief — **not your account of why it is complete or lean.** Briefed with the inputs alone, a reviewer
  falls back to its own code-review checklist, which asks neither question. An author cannot find its
  own holes or its own excess; independence is a property of context, not of instruction. Orchestrator
  mode makes these subagents regardless. This is the pr-ready review pattern, moved one level up — the
  same reliability, applied to the plan instead of the diff.
- **Run them as a pair, not in sequence.** Name both so they cross-examine directly: a completeness
  hole in an item the overbuild read would cut is moot if the cut stands, and a cut that would open a
  hole goes to the completeness reviewer to confirm. Where they still disagree, both positions go to
  the human.

**The completeness read:**

- **One adversarial question.** What will the implementer have to invent because the plan left it
  open? Every observable the plan does not pin to an authority, every choice handed to implementer
  discretion, anything settled only by *the code already does it* or *I would build it this way* —
  those are open decisions, not made ones. Default to unsettled when unsure.
- **The review params (§3) are in scope for this read, not just implementer-facing holes.** The feedback
  path is an orchestration decision the implementer does not build, so the adversarial question above
  would walk past a half-specified one — check it explicitly: are all three reviewers named, the live
  implementer teammate(s) named, the channel and the escalation boundary stated? Does every
  ticket-specific criterion cite an authority outside the plan, or is any of them a ruling restated? A
  missing or vague feedback path is the failure §3 exists to prevent, and the author's own §3 is where
  it hides — so the independent read, not author self-assessment, must confirm it. **Confirm the TDD
  pairing the same way:** does every work-item with a test surface name a `test-first` teammate ahead of
  its implementer, and does every item that omits one carry an explicit recorded skip? A silent omission
  reads identically to a decision, which is exactly how test-first coverage lapses unnoticed.
- **Thoroughness is a method, not a resolve:** enumerate the properties the plan must settle, check
  each against the real plan text and the ticket's intent, not a fixture, hunt the class behind the
  instance, and flag where the plan does not yet name how a property will be proven durably.

**The overbuild read:**

- **One adversarial question.** What could this plan drop and still close the ticket? Ask it of every
  work-item, abstraction, option and proof; for each, name what the ticket needs that would break
  without it. If nothing would, it is a cut.
- **Engineering nobody asked for** — an abstraction with one caller, configuration or extension points
  no requirement names, a general mechanism where the ticket needs one case, hardening of scaffolding
  before the loop it serves has run once.
- **Tests that prove the same thing twice** — one contract pinned several ways (unit, integration and
  snapshot tests of the same behaviour; a case per input variant where one case settles the contract),
  tests of the tooling rather than the change, and tests of behaviour no contract in the plan names.
  One proof per contract, able to fail on the wrong behaviour; anything beyond that is a cut. Each of
  these is its own contract, not a repeat of one: a changed boundary or failure path, the real-thing
  check that backs a test double, and the seeded-defect and valid-variant cases that prove a check can
  fail.
- **An authority licenses the what, not the how.** An authority outside the plan — the ticket, a
  contract discovery found in the tree, a decision the human answered in discovery — protects what an
  item must *do*, never, on its own, how it is built: a ticket asking for a configurable timeout does
  not license a layered config loader.

**Both reads surface, they do not resolve.** Holes and cuts come back as open calls — the options and
what is at stake — never a recommendation dressed as a finding, the contract discovery already holds.
A cut changes scope, so the human makes it.

**The reads are a cycle, not a gate.** Resolve each hole and cut **with the human, in conversation**, and
fold the answers into the plan. Then the revised plan goes back to **both** reviewers — the same named
teammates, so they hold their earlier findings — for a **full re-read of the whole revised plan**
against the ticket, not a check of the parts you point them at. Where `/pr-ready` sends a fix back for
a pass scoped to that fix, a plan gets the whole re-read: it is small, and every settlement is new plan
text that can move the other axis — a hole settled by adding behaviour is where overbuild enters, and a
cut can open a hole. Repeat until a round comes back empty: no hole or cut the human has not already
answered. The one earlier stop: a round whose findings all come from the previous round's settlements,
once the human has answered them and calls it. A settlement one reviewer keeps reopening is a
disagreement — both positions go to the human. Anything still open is escalated, never invented. Only
then does the plan go to approval — a clean yes on a complete, lean plan rather than a prompt to
adjudicate what the plan skipped or overbuilt.

## 5. Approve, then record

- **Do not propose the plan while any question is open.** The `ExitPlanMode` call *is* the proposal —
  it must not fire until every open decision from discovery (§1) and every hole or cut the §4 reads
  turned up has been answered by the human, review params (§3) included. Plan-mode entry fires no
  hook, so this cannot be gated mechanically; it holds as an instruction, and an unanswered decision
  blocks the proposal, no exceptions. Presenting a plan with an "open question" or "TBD" still in it is
  the failure this step exists to prevent.
- **Exit plan mode for approval before any code is written.** Approval of the plan is not approval of
  a decision buried inside it, so the approval message *leads* with a "Decisions you are approving"
  list — one line each for anything that adds a document (an ADR especially), a dependency, a gate or
  CI job, a requirement or tree change, a numeric threshold, a repo setting, or a scope extension into
  shared code — and the mechanism prose stays short beneath it. A decision left sitting among file
  names and flag values gets approved without being seen.
- For a ticket, post the approved plan itself back with `gh issue comment` — the work-items with their
  scope boundaries, contracts and proofs, the resolved decisions, and the review params — so the record
  outlives the session; the content reviewer reads the ticket with this plan attached.
- **The plan is not a repo file.** It lives as the plan-mode contract (ExitPlanMode), the `gh issue
  comment` record, and the brief you hand each implementer from this context — `/implement` reads it
  from that brief, not from disk. Do not write a `PLAN.md` into the tree; orchestrator mode denies it,
  and delegating that write to a subagent only launders the gate. If you need a scratchpad, the scratch
  tree (`/tmp/claude-1000/…`) is writable inline.

The deliverable is an approved, decomposed plan — with its review params settled (§3) — the brief the
implementation and review steps both consume.
