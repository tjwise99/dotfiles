# Project playbook — building software with an AI agent

A portable working method, distilled from a project run end-to-end with Claude. Domain-free: it
assumes a solo developer, an agent doing most of the typing, and no second human reviewer, ever.

Evidence for every claim here lives in that project's retrospective. Where this document states a
rule, the retrospective states what it cost to learn.

---

## The premise

**Generation cost collapsed. Review capacity did not move.**

One agent produced, in ten days, more than the preceding two years had: a full security programme,
successive passes stripping and then replacing an inherited framework, an end-to-end language
rewrite, ten architecture decision records, and a documentation architecture. Output scaled by
roughly two orders of magnitude. The ability to read that output stayed exactly where it was.

Every tool in the standard workflow — code review, pull requests, coverage, linting — was designed
around the assumption that *writing* code is the expensive step. That assumption is now false, and
nothing in the toolchain has caught up. **The whole method below follows from making review, rather
than production, the thing the process is built around.**

The corollary that governs everything else: an unreviewed change is not a fast change. It is an
unverified one.

---

## Operating model

Five commitments. Everything else is implementation.

| # | Commitment | Because |
|---|---|---|
| 1 | **Write the requirements before any code** | Nothing in a solo project re-asserts what it is for. Work silently optimises for the most recent technical question |
| 2 | **Document the design before implementing it** | The document is what the agent implements against and what review is conducted against. Without it, review degenerates to "does this look plausible?" |
| 3 | **Size every change by what you can actually read** | Not by feature, not by milestone. A slice you cannot read has not been reviewed and will carry defects past every later pass |
| 4 | **Gate mechanically on invariants** | Automated constraints are the review function when there is no second reader |
| 5 | **Record decisions with their expiry condition** | A decision recorded as a conclusion cannot be re-examined when its premise moves |

---

## Phase 0 — before any code

The phase that gets skipped, and the one that pays for everything downstream.

### Requirements

Write down, in prose:

- **What the thing is**, and what it is explicitly not.
- **Who operates it** — and if that is ever someone other than you, treat this as the dominant
  constraint. It changes failure handling from hygiene into product surface.
- **Deployment model** — where it runs, how it is configured, how it is updated.
- **Use cases, ranked**, with a stated effort budget for the low-priority ones. *"Support this only
  while it costs nearly nothing; if it starts requiring architecture, it has exceeded its budget"*
  is a complete and enforceable requirement.
- **Non-goals.** Longer than feels necessary. Most accidental architecture arrives as an unstated
  "maybe someday."

> **Shipping to another person is the only external gate a solo project naturally has.** Someone
> else's deployment is a constraint you cannot rationalise away. If the project has a real user who
> is not you, their experience is the requirements discipline. If it does not, you have to supply
> that discipline deliberately, because nothing else will.

### Separate the learning track from the delivery track

Personal projects usually carry both, and conflating them makes both unjudgeable — work justified as
learning gets measured as delivery, delivery work gets excused as learning, and neither gets an
honest verdict.

State which is primary. If the goal is learning a tool, say so, and accept that the delivery answer
may have been "this already works, stop." That is not a failure. It is the point, and naming it
prevents an expensive rewrite from having to be retroactively justified as necessary.

### Decide the architecture's shape, not its details

Enough to constrain: the transport, where state lives, what crosses which boundary. Specifically
determine **the access pattern before the transport** — a live channel for data that refreshes every
ten minutes is indirection bought against a requirement that does not exist.

---

## Phase 1 — scaffolding and gates

Mechanical, repetitive, and the same on every project. **Automate this** (see
[Agent infrastructure](#agent-infrastructure)).

### Gate invariants immediately

Set on day one, because they encode what must always be true of the product and no rewrite can
invalidate them:

- Lint, in CI, blocking
- Static analysis / code scanning
- Dependency and container image scanning
- Secret-free CI — key-dependent checks run locally, CI never holds a credential
- Line-ending enforcement
- Build provenance, SBOM, artifact signing
- Automated dependency updates, grouped so they do not drown the log

### Repository scaffolding

- Decision-record directory and template
- Contributor documentation and agent instructions **as separate files** — durable facts belong in
  documents a human would also read; the agent file holds only working rules layered on top
- Security policy
- Code ownership, branch protection, a single merge strategy
- Local recipes that run **exactly** what CI runs, containerised so they do not depend on local
  toolchain state. This removes an entire class of false pass

### What not to gate on

Implementation-bound thresholds — anything encoding what is currently true of the code rather than
what must always be true of the product. They are a tax while the shape moves and get deleted with
the code they measured.

**Coverage specifically is diagnostic, never evidence — and that does not change once the project
matures.** Real case: a defect sat in fully covered code. The line was tested, the assertion passed,
and the actual invariant — that two implementations of the same formula agree — was untestable by
construction. A high coverage number bought confidence it had not earned.

Report coverage, read it to find untested areas, and gate instead on obligations that name what must
be proven (see [Test architecture](#test-architecture)).

---

## Phase 2 — design before implementation

**The rule: nothing gets implemented that has not been written down first.**

This is not documentation as courtesy. It is documentation as the mechanism that makes the rest work:

- **It constrains the agent.** A written design is a specification to implement against, rather than
  a shape the agent invents and you discover afterwards.
- **It arms the reviewer.** A reviewer with a large diff and no specification can only ask *"does
  this look plausible?"* — a question that duplicated logic, unnecessary abstraction, and
  silent-failure modes all pass. With a specification, the question becomes *"does this match?"*,
  answerable in seconds.
- **It preserves you as a contributor.** When generated code exceeds what you can read, consistent
  documented patterns are the comprehension mechanism — not a layer on top of comprehension. This
  matters most in a language you are still learning, which, with an agent, is common.

**Documentation-first and no-human-reviewer are the same lesson.** Without a second reader, the
written design *is* the reviewer's reference.

### Decision records, with expiry conditions

For every decision with a real rejected alternative, record: context, decision, **alternatives and
why not**, consequences — plus the premise, stated as *what would have to become true for this to be
worth reopening*.

The rejected alternatives routinely carry more information than the decision. And a decision without
a stated premise never gets revisited, because it never fails — it just quietly stops being the best
answer while continuing to look correct.

---

## Phase 3 — build in reviewable slices

### Size by reviewability — then make sure something reviews it

Practical test: **if you cannot review the diff attentively in one sitting, it is too big** —
regardless of how coherent the feature is or how easily the agent produced it.

This costs time the agent did not need to spend. That is the trade: slicing is the price of the
change being verifiable at all.

**But slicing is the enabler, not the control**, and this is where the source project's evidence is
counter-intuitive. It sliced correctly — a large rewrite ran as five milestone pull requests of
17–65 files each, every one readable. The silent-failure defect that outlived three later passes over
the code entered in a twenty-five-file, thousand-line PR. Across the whole repository, 47 of 56
merged pull requests carried **zero reviews**.

The constraint was never slice size. **No review function existed at any size.**

> A reviewable diff that nobody reads is exactly as unverified as an unreadable one. It just looks
> responsible.

So the rule has two halves and the second is the load-bearing one: size changes by what can be read
in one sitting, **then guarantee something actually reads them.** With no second human, that means
building the reviewer — see [Agent infrastructure](#agent-infrastructure). Slicing without a reviewer
buys the appearance of rigour and none of the substance.

One corollary about evidence: **squash-merging collapses reviewable slices into a single enormous
commit on the default branch.** The unit that was reviewable and the unit that survives in history
become different objects, and the log will misrepresent how the work was actually done — in both
directions.

### Boundary contracts

**When the same value must be correct on both sides of a boundary, it gets one definition.** Share
the code, or generate both sides from one schema, or test that they agree. Never a comment saying
"keep this in sync."

The failure mode is silent. Two implementations of a formula, in separate packages, agreement
maintained by prose — they diverge, everything succeeds, and the data never arrives. No error, no
crash, no failing healthcheck. It survived a full rewrite because it arrived inside an unreviewable
diff.

If the architecture makes sharing impossible, **that is a finding about the architecture**, not a
reason to write the comment.

### Abstraction requires a second consumer

Build for cases that exist. A plugin system with no plugins, an extension point with one
implementation, a transport chosen before the access pattern — each is generality bought against a
future that may never arrive.

The cost is not the code. It is that everything downstream must accommodate it — a dynamic plugin
API fighting the type system ends up dictating annotations in every single handler.

> **If something exists to support a case that does not exist yet, it should not exist yet.**

### Rewrites reproduce the shape they replace

A rewrite that takes the current implementation as its specification will reproduce it in the new
language. One project rewrote its inherited framework three separate times and each pass carried the
ancestor's shape forward, because each asked *"how would this look rewritten?"* rather than *"does
this indirection earn its keep?"*

Write the specification from requirements. Then implement.

---

## Test architecture

**Tests resist deletion more strongly than code does.** Removing one feels like a regression even
when it proves nothing, so a half-considered early suite quietly becomes permanent architecture
nobody revisits. In the source project, production code was demolished three times; the test suite
was never once subjected to a design review.

### Write it as a specification, before tests exist

Define: what tiers exist, what each **guarantees**, what a new component is **required** to prove,
and where a check belongs in the repository.

A strategy written first is enforceable. One reverse-engineered from existing tests is a
description, and it will ratify whatever accumulated.

### Standing obligations

Gate on obligations that name what must be proven, not on a coverage number:

- Every value crossing a boundary is generated from one definition or covered by an agreement test
- Every component supplies unit tests for its pure logic and a render/integration test for its wiring
- Every input schema rejects at least one realistic malformed input, in a test
- Repo-wide checks live at repo level — not inside whichever package happened to have a test runner
  first
- **Every test file is wired into CI.** A test that has never run is worse than no test: it is a
  false signal

### Review it on a schedule

Whenever a component is added, whenever the transport changes. The review that code gets
automatically must be scheduled for tests, because it will not arise naturally.

---

## Security

**Prefer controls that cannot be forgotten over controls that must be remembered.**

| Pattern | Verdict |
|---|---|
| Secret resolved server-side, structurally unable to reach the client | Sound — absent by construction |
| Denylist of secrets stripped before delivery | Fails open. Adding a secret and forgetting the list is silent |
| Access control based on a value the deployment environment rewrites | Inert. Verify controls **function where deployed**, not where designed |

Any control depending on a future contributor remembering something will eventually fail — silently,
and worse than not having it, because its presence also removes the pressure to build the real thing.

---

## Agent infrastructure

Tooling is not overhead here. It is how the operating model gets enforced instead of merely
intended, and it is where token efficiency comes from.

### Inventory before adding

Take stock before writing anything new. The gaps that turned up in one real setup, as a guide to
where to look:

- **A borrowed agent pack**, mostly untuned — persona agents for roles the work does not involve.
- **Workflow commands scoped to a single project**, battle-tested over months, that would have died
  with the repository.
- **No reviewer agent at all**, despite review being the identified bottleneck.
- **No scaffolding automation**, so every project reacquired its gates by hand.

Three lessons generalise:

- **Borrowed agent packs are a starting point, not a configuration.** Most of a generic suite will be
  irrelevant to what you actually build. The few that match deserve tuning; the rest are noise in
  the selection space.
- **Workflow assets scoped to one repository die with it.** Promote to user scope once they have
  proven themselves twice. This is easy to miss precisely because a project-scoped command works
  perfectly right up until the project ends.
- **Generalizing a command means replacing hardcoded facts with discovery**, not deleting them. A
  checklist that assumed one repo's branch name, task runner, and CI job names becomes portable by
  instructing the agent to *find* the default branch, read the repo's contributor docs for its gate
  commands, and locate its doc map. The knowledge is retained as a question rather than an answer.

### Independence is a property of context, not instruction

The principle that governs how review actually gets wired up:

> **An agent cannot review its own work by being told to be critical.** Independence comes from not
> having written the thing. Telling a context that just produced a diff to now scrutinise it asks it
> to re-examine its own intent — which is exactly the thing that needs outside checking, and exactly
> the thing it cannot supply.

So review mode is not a stylistic preference. It is determined by **who wrote the code**, and the
determination has to be made explicitly, because the default — "whoever is here reviews it" — is
silently wrong in the one case that matters most:

| Who wrote it | Independence | Correct mode |
|---|---|---|
| The human, or an agent in a session this context had no part in | Full | **Review inline.** A subagent adds cost and supplies no independence that is lacking |
| An agent in another context, from a plan this context wrote | Partial | **Review inline**, but treat the plan as suspect too — a reviewer that wrote the spec shares its blind spots |
| **This context, in this session** | **None** | **Delegate to a fresh context.** Hand it the diff and the specification, never the narrative of what was done |

The middle row is the subtle one, and the top row matters for cost: reflexively spawning a reviewer
for human-written code buys nothing, because the reviewing context was already independent.

### The reviewer agent

If review capacity is the binding constraint, a dedicated adversarial reviewer addresses it
directly. It is the most commonly missing piece, because ad-hoc *"open a fresh context and ask it to
review"* feels like it already covers the need. It does not: it is unrepeatable, unspecified, and
the first thing dropped under time pressure.

A reviewer agent should:

- **Run in a fresh context**, per the independence rule above.
- **Review against the specification**, not against plausibility. Give it the design document. Without
  one it can only ask "does this look reasonable?", which duplicated logic and silent-failure modes
  both pass.
- **Carry a standing checklist derived from your own defect history.** Generic review advice finds
  generic problems. Yours should name the specific things that have actually bitten you — for this
  playbook: cross-boundary values kept in sync by comment, abstraction with one consumer, controls
  that do not function where deployed, tests that assert nothing, scope creep beyond the ticket.
- **Be adversarial by construction** — instructed to find what is wrong, not to summarise. A reviewer
  reporting "looks good" has provided no signal. It should also be permitted to say a diff is clean
  rather than manufacturing findings to appear useful; both failure directions are real.
- **Sit non-optionally in the merge path**, so it cannot be skipped when moving fast.

### Workflows worth defining as commands

Two that earn their keep and generalise. Both work best as checklists the agent **executes** rather
than reports on — the instruction "do the work, don't describe it" is load-bearing.

- **Merge-readiness checklist** — rebase onto the moved base, confirm the diff is scoped to intended
  files only, verify via CI rather than re-running the gate locally, sweep documentation for claims
  the change invalidated, run review in the mode the independence table dictates, housekeeping, PR
  hygiene. Merge prep is exactly where surrounding work gets forgotten, which is why it pays to be a
  checklist rather than a habit.
- **Ticket-to-PR flow** — scope, a mandatory planning pass (no straight-to-implementation escape
  hatch, however small the ticket looks), implementation either inline or delegated, then the
  merge-readiness checklist. Human-gated at plan approval and at merge.

Two design notes learned from generalizing these:

- **Keep the merge-readiness checklist source-agnostic.** It should run identically on human-written
  code, agent-written code, and code from another session — with only the review mode differing. A
  checklist that assumes it is always running after a particular implementation flow will silently
  mishandle every other case.
- **Let the two commands compose rather than duplicate.** The ticket flow hands off to the
  merge-readiness checklist and tells it who wrote the code; the checklist owns everything from
  verification onward. Review logic living in one place means it stays consistent when it changes.

### Bootstrap skill

Everything in [Phase 1](#phase-1--scaffolding-and-gates) is mechanical, identical across projects,
and tedious enough to be skipped under enthusiasm. It should be one command: CI workflows, scanning,
dependency automation, branch protection, merge strategy, decision-record scaffolding, the
contributor/agent documentation split, security policy, line-ending enforcement, containerised local
recipes matching CI.

Automating it means a new project starts *with* its gates rather than acquiring them once problems
appear.

### The non-deciding implementer

The counterpart to the reviewer, attacking the same problem from the other end.

Unauditable structure comes from **decisions the agent made that nobody specified and nobody
reviewed.** A helpful agent encountering an underspecified requirement fills the gap plausibly — and
a plausible invention is the worst possible outcome, because it reviews as normal code while
encoding a choice no human ever made.

An implementer agent constrained to **not decide** converts those silent decisions into visible
blocked questions. The design turns entirely on where the halt threshold sits:

> It may decide anything invisible outside the code it is writing. It may not decide anything another
> file, another developer, or a user could observe.

So: local names, private helpers, and loop structure are free. Interface names, payload shapes,
config keys, failure behaviour, thresholds, new files, and new dependencies are halts. When genuinely
unsure which side a question falls on, halt — an unnecessary question costs one exchange, an
unnecessary decision costs a defect that reviews as normal code.

Two implementation details make it usable rather than infuriating: it surveys the whole task and
reports **all** questions at once rather than halting repeatedly, and it proposes an answer for each
so unblocking costs one word — while never acting on its own proposal.

The second benefit is diagnostic. **It is a specification quality test.** Frequent halts mean the
spec was incomplete — information a helpful agent actively conceals by covering gaps well.

### Model and tool scoping

**Model assignment matters less than it appears.** Subagents inherit the parent model, which is
usually the right answer. Explicit assignment earns its keep in exactly two cases: **pinning up**, so
review and architecture stay strong even when you are running something cheap, and **pinning down**,
so high-volume mechanical work does not cost architecture rates. Everything advisory wants the strong
model anyway; annotating it is noise.

**Tool scoping is the one that carries real weight**, because it enforces roles structurally rather
than by instruction. A reviewer with edit tools becomes a second author whose later judgments cover
its own work. Remove the tools and the guarantee holds without depending on the agent's restraint.

**Description length is a live token cost.** Every agent's description sits in context whenever
delegation is considered. A short example or two aids selection; several fabricated multi-turn
dialogues are pure overhead — borrowed packs routinely ship 1,400–3,400 characters per agent where
250 would select just as well.

### Isolate parallel work

Agents working simultaneously in one working tree collide. Give each an isolated worktree. This is
learned expensively and exactly once.

### When the environment fights you, stop

Root-owned files, permission errors, toolchain oddities: run one diagnostic, then stop and fix it
directly. Do not let an agent chain workarounds. A session can burn a large fraction of its budget
improvising around a problem a human resolves in one command.

---

## Anti-patterns

| Anti-pattern | Rule |
|---|---|
| Big-bang generated changes | Size by reviewability, not by feature |
| Comment-enforced cross-boundary invariants | One definition, or a test of agreement |
| Plugin systems with no plugins | Abstraction requires a second consumer |
| Transport chosen before access pattern | Determine the access pattern first |
| Rewrites specified by the current implementation | Specify from requirements |
| Security by denylist or by vigilance | Prefer controls that cannot be forgotten |
| Coverage thresholds as proof | Coverage is diagnostic, never evidence |
| Tests accumulated rather than designed | Test architecture is a specification, reviewed on a schedule |
| Config keys that are not operator-tunable | If turning it breaks the deployment, it is a constant |
| Decisions recorded without their premise | Record the expiry condition |
| Workflow assets scoped to one repository | Promote to user scope once proven |
| An agent reviewing what it just wrote | Independence comes from context, not instruction — delegate to a fresh one |
| Spawning a reviewer for human-written code | The reviewing context is already independent; the subagent buys nothing |

---

## Starting checklist

```
Phase 0 — before code
  [ ] Requirements written: what it is, what it is not, who operates it
  [ ] Operator identified; if not you, failure handling is product surface
  [ ] Use cases ranked, low-priority ones given an explicit effort budget
  [ ] Non-goals written down
  [ ] Learning track vs delivery track named
  [ ] Architecture shape decided; access pattern determined before transport
  [ ] First decision record written, with its expiry condition

Phase 1 — scaffolding (automate this)
  [ ] Invariant gates: lint, scanning, secret-free CI, signing, line endings
  [ ] Dependency automation, grouped
  [ ] Decision-record directory and template
  [ ] Contributor docs and agent instructions, as separate files
  [ ] Branch protection, single merge strategy
  [ ] Local recipes that run exactly what CI runs
  [ ] No implementation-bound thresholds yet

Phase 2 — design
  [ ] Test architecture written as a specification, before tests
  [ ] Boundary contracts have exactly one definition each
  [ ] Design documented before each component is implemented

Phase 3 — build
  [ ] Slices sized by what you can read in one sitting
  [ ] Review mode chosen by who wrote the code, not by habit
  [ ] Reviewer runs against the spec, in a context that did not write the diff
  [ ] Test architecture reviewed when components are added
  [ ] Decision records updated as premises move

Agent infrastructure (once, then carried between projects)
  [ ] Existing agents/skills/commands inventoried before adding more
  [ ] Proven workflow commands promoted to user scope, generalized by discovery
  [ ] Reviewer agent defined: fresh context, spec-driven, own defect checklist
  [ ] Models and tool scopes assigned deliberately per agent
  [ ] Scaffolding automated as a skill
```

---

## The one-line version

**Write it down, slice it small, gate it mechanically, and build the reviewer you do not have.**
