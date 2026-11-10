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
  - **The briefing row** — which row of `/pr-ready` §6's authorship table applies, recorded as its
    `authorship:` value, **cited, not restated here**; each review mandate defines what that value tells
    its reviewer to distrust, and the plan only records the row. For the `/work-ticket` flow the row
    is already fixed: code is written by a subagent from a plan this thread wrote, and orchestrator
    mode runs the review as a reviewer–implementer team regardless —
    so the row is `authorship: agent-from-lead-plan` and the three reviewers are fresh-context
    teammates (e.g. two `independent-reviewer` teammates on the `pr-content` and `pr-docs-discipline`
    mandates, plus a `testing-architect` teammate on `pr-test-quality`, spawned review-only, no edit
    tools), feeding the implementer teammate(s) `/implement` leaves running.
  - **The ticket-specific criteria** the review must verify — the checks particular to *this* change (a
    contract it must not break, an observable it must preserve, an edge case discovery surfaced), on top
    of `/pr-ready`'s generic checklist. **They are a floor beneath the content reviewer's two questions
    (`~/.claude/reviews/pr-content.md`), never its mandate**, and reach the reviewers in this plan, not
    restated in a spawn prompt. **Each criterion cites an authority outside this plan** — the
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

- **Delegate both to fresh contexts, and do not write their briefs.** Each read's question and method
  live in a mandate file the reviewer reads itself — `~/.claude/reviews/plan-completeness.md` and
  `~/.claude/reviews/plan-overbuild.md`. The spawn prompt is the mandate path and the inputs that file
  lists, one per line, and nothing else:

  ```
  mandate: ~/.claude/reviews/plan-completeness.md
  ticket: <issue number or task text>
  discovery: <path to the /discover brief>
  plan: <path to the drafted plan>
  pair: <the other reviewer's name>
  report: <path, unless the harness assigns a deliverable>
  ```

  Write the mandate path with `~` expanded — the reviewer's Read tool takes only absolute paths.

  **No framing, no emphasis, no focus list** — not "be especially sharp on X", not your account of why
  the plan is complete or lean. A list of what to look at is a list of what you already suspected:
  it aims the adversarial read at the parts you have already examined and waves the rest through. An
  author cannot find its own holes or its own excess; independence is a property of context, and the
  spawn prompt is context. Orchestrator mode makes these subagents regardless.
- **Run them as a pair, not in sequence.** Name both so they cross-examine directly, as their mandates
  describe. Where they still disagree, both positions go to the human.
- **Your suspicions go in after the blind pass, not before.** If you have them, write them to the
  scratch tree before you spawn — so they are on record and cannot be rewritten to match the result —
  and send them to each reviewer only once its report exists, asking for each whether its report
  already covers it. A suspicion the blind pass missed is a finding about the review as well as the
  plan; say so to the human.

Resolve each hole and cut **with the human, in conversation**, and fold the answers into the plan;
anything still open is escalated, never invented. Only once the plan settles every decision it
requires — each cited to an authority or answered by the human — and every cut is answered by the
human does it go to approval. That is what keeps the next step a clean yes on a complete, lean plan
rather than a prompt to adjudicate what the plan skipped or overbuilt.

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
