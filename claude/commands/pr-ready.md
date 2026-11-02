---
description: Run the merge-readiness checklist for the current PR branch (scope, verify, docs sweep, code review, housekeeping). Works on any repo and any code, whoever wrote it.
---

# Get this PR merge-ready

Work through the steps below for the current branch, in order. **Do the work** — run the commands, make
the doc edits — don't just report on it. Report a short pass/fail summary per section at the end (step 6
reports the content reviewer's two verdicts instead), and stop to flag anything needing a human
decision.

This command is **source-agnostic**: it runs the same way whether the human wrote the code, an agent
wrote it in another context, or you wrote it yourself in this session. The review in step 6 always runs
as three dedicated reviewers; what changes with authorship is only how they are briefed — see step 6.

**Discover the repo's conventions; don't assume them.** Before starting, skim `CONTRIBUTING.md`,
`CLAUDE.md`, and any docs index (`docs/README.md`) for: the gate commands, the merge strategy, the
doc map, and any documented local-vs-CI divergences. A repo may also ship its own project-scoped
`pr-ready` that overrides this one — if so, that wins.

**If `CONTRIBUTING.md` carries a review checklist, walk it in step 6.** Its questions are additional
to the ones below, not a replacement — a repo's checklist covers what is specific to its artifacts
(a requirements tree, an architecture model), where step 6 covers what holds anywhere.

## 1. Pre-flight (branch & scope)

- Confirm the current branch and its intended base. Get the default branch from
  `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` rather than assuming `main` or
  `master`; a stacked branch's base may be another feature branch.
- `git fetch origin`, then **rebase onto the latest base**. Use
  `git rebase --onto origin/<base> <old-base> <branch>` when the base has moved. If the repo
  squash-merges, history is rewritten on merge, so a branch cut from a since-merged branch will
  otherwise carry duplicate commits.
- `git diff --stat origin/<base>...HEAD` — confirm the diff is **scoped to intended files only**.
  Watch for local/editor settings, credentials, build output, coverage reports, and anything
  matching the repo's `.gitignore` intent that slipped in anyway.

## 2. Resolve the PR (or open one)

Every later step cites `gh pr checks <n>`. Bind `<n>` now — do not assume a PR exists.

- `gh pr view --json number,state,baseRefName --jq '.number, .state, .baseRefName'` for the current
  branch.
- **If no PR exists** — the normal case when the human wrote the code locally and ran this command
  directly — push the branch and open one: `gh pr create --base <base>`. CI starts immediately and
  its results are ready by the time you reach the review. Draft a description from the actual diff.
- **If the branch is unpushed but a PR exists**, push before reading checks; you would otherwise be
  reading a stale run.
- Use the resolved number wherever this document writes `<n>`.

## 3. Verify — lean on CI, don't re-run the full suite locally

If CI runs the same gate on every push, **that is the authoritative proof**. Push the branch and read
the result (`gh pr checks <n>`) rather than reproducing it locally. Checking CI is nearly free; a
full local run is not, and running it in a subagent as well triples the cost for the same answer.

- **Push early — here, not at the end** — so CI runs while you do the docs sweep and review. Iterate:
  if a job is red, read its log, fix, push, re-check.
- **Local runs are for fast, targeted checks only:** one changed unit test, a type-check on touched
  files, a lint of the diff — or a sanity pass before the first push exists. Never the whole gate.
- **Watch for local checks that false-pass.** A package installed in isolation by CI but resolving
  dependencies from a parent directory locally can pass on your machine and fail in CI. Check the
  repo's docs for known cases and use whatever CI-faithful recipe it provides. **Never sign off on a
  check that is known to diverge locally** — read the CI job instead.
- If a push was skipped by path filters (e.g. docs-only), the authoritative run is the last push that
  included code. Say that, rather than reporting "no checks."
- Note which tiers are relevant to this change (runtime/browser, contract/API shape, integration) and
  confirm those specific jobs went green — you are **reading** their status, not re-running them.

## 4. Documentation sweep

Update every doc the change affects. Do not assume "code-only" — most changes touch a documented
fact somewhere.

- **Find the doc map first.** A repo with a docs index has one home for each kind of fact; put the
  update where it belongs rather than restating it wherever is convenient.
- **Architecture/design docs** — if the change altered how pieces fit together.
- **A decision with a genuinely rejected alternative gets a decision record**, not a prose paragraph
  buried in a history file. Record the context, the decision, the alternatives and **why not**, the
  consequences, and the premise that would justify reopening it.
- **Testing docs** — if tiers, gates, or what a component must prove changed.
- **Component/module READMEs** — if configuration or behaviour changed.
- **Task-runner recipes and their comments** — if commands or their behaviour changed.
- **Agent instructions** (`CLAUDE.md`) — only if a *working rule* changed. Durable facts belong in
  docs a human would also read.
- Then **grep the changed area's docs for stale claims** and fix them. **Drop point-in-time numbers**
  (coverage percentages, test counts, file counts) — document the mechanism a reader can re-derive
  the current number from, not a figure that rots.
- **Drop temporal phrasing** — "now", "currently", "no longer", "previously", "recently". Each states
  a fact relative to a moment the reader does not share, and goes stale without anything failing.
  State the timeless fact.

## 5. Housekeeping

- **Save/refresh memory** — record durable, non-obvious decisions or workflow feedback; update any
  memory this PR made stale (branch/PR status especially), and delete ones proven wrong.
- Confirm no secrets, credentials, or machine-specific paths are being committed.

## 6. Code review

Once code and docs are final, review the **full diff** (`git diff origin/<base>...HEAD`).

**Thoroughness is a method, not a resolve.** Enumerate the properties the artifact must hold; check
each against the real artifact with real data, not a fixture; hunt the class behind the instance;
leave each as a check that fails on regression. Not a quota — a clean diff is clean.

**Review runs as three separate reviewer agents, in every mode — never one combined pass, never a
review you hold only in your own head.** Comment/documentation discipline and test quality are each
the first thing a correctness-focused read skims past, so each gets its own reviewer with its own
mandate:

- A **content reviewer** — answers two questions, separately: is the code good, and did we build the
  right thing (the *Content reviewer* section below).
- A **comment & documentation-discipline reviewer** — comment and citation hygiene in the code *and*
  the state of the §4 documentation sweep (the *Documentation discipline* checklist below).
- A **test-quality reviewer** (the `testing-architect` agent, spawned review-only — no edit tools,
  the same restriction `independent-reviewer` carries by design) — whether the diff's tests
  meaningfully verify behaviour rather than merely execute lines for coverage (the *Test quality*
  checklist below).

All three read the same diff on disjoint mandates and report independently. Spawning three agents even
when you could read the diff yourself is deliberate: each lens is one that otherwise vanishes.

**If the plan supplied review params** (the `/work-ticket` flow settles them in `/plan` §3) **use them,
do not re-derive them — before you choose or spawn anything.** The plan already names the three
reviewers, the implementer teammate(s) that stay alive to receive findings, the feedback channel, the
briefing row, and the ticket-specific criteria; apply that, and add its criteria to each brief as a
floor beneath the reviewer's mandate — never in place of it. Deriving your own reviewer or loop here is
exactly how the plan's pinned-down review loop gets silently replaced.

**If orchestrator mode is on** (the `/work-ticket` flow leaves it on through this step), you cannot
read the diff or edit on this thread — `git diff …`, `Read`, and `Edit` are gated. **Run the review as
a team, not a relay.** The implementer(s) `/implement` left running are named teammates; spawn **all
three reviewers** as teammates too, and give each the diff range, the spec, and its mandate — not your
account of the work. The content reviewer's mandate is the two questions below, the first quoted
verbatim — not a list of the plan's rulings to confirm; its spec is the ticket with the approved plan
attached. The test-quality teammate is spawned review-only (no edit tools), the same restriction the
`independent-reviewer` teammates carry by design. Each reviewer takes its findings **straight to the
implementer** by `SendMessage`; they settle loop findings (below) between themselves and you neither
sit in that loop nor re-dispatch fixes. What reaches **you** is only what must: an escalation (below), a
tool recommendation, or a short readiness digest carrying the content reviewer's final two verdicts
word for word, noting any *send back* that was reworked.

**One carve-out, on a TDD-paired item: a test-quality finding on a `test-first`-authored test does not
go to the `code-monkey` implementer** — it cannot edit tests, and `test-first` is gone by review time.
If the finding questions whether the test correctly encodes or omits a spec'd contract, it escalates to
you like any contract finding; if it is mechanical test repair, spawn `test-writer-fixer` to apply it.
This is the routing `/plan` §3 already names for the pairing — apply it, do not re-derive it.

**The peer loop is bounded to fixes that change no interface, contract, shared value, abstraction, or
decision the plan made.** Within that bound the reviewer and implementer resolve directly any
mechanical finding — a local rename, a missing null check, a doc fix, a comment that states a reason
instead of a mechanism, a test that asserts nothing — and **any readability finding, restructures
included**, the implementer returning each fix to the raising reviewer for a re-read. A finding whose
fix would cross the bound is a plan finding and escalates. A finding
whose class is likely to recur also carries a recommendation for a tool that would check it
automatically — a linter rule, a formatter, a gate — and that recommendation comes to you for the human,
who decides whether it becomes a ticket or lands in scope. **Everything else escalates to you, and you
take it to the human: any ambiguity, any design decision, any finding that questions a contract, a
shared value, an abstraction, or the plan itself.** Neither teammate resolves such a finding between
themselves and neither invents an answer — that is the exact defect the review exists to catch. Keep a
running digest on the shared task list so the human can watch the exchange without being its
switchboard.

**Brief each reviewer by who wrote the code** — it does not change *whether* they are spawned (always
three, always fresh context) but *what they are told to distrust*:

| Who wrote it | What the reviewers are briefed to distrust |
|---|---|
| **The human**, or an agent in a session you had no part in | Verify against the ticket's stated intent; no plan to treat as suspect |
| **An agent in another context, from a plan you wrote** (e.g. the `/work-ticket` flow) | Treat the **plan itself as suspect too** — it shares your blind spots; verify against the ticket's intent, not just the plan |
| **You, in this session** | The reviewers are your only independent read — give them the diff and the spec, *not* your account of what you did |

In every case: **verify prior claims, don't trust them.** An implementer's self-report is a
starting point, never evidence.

**Content reviewer — two questions, answered separately:**

1. **Is the code good?** *Would a senior engineer intimately familiar with this language and this
   project accept this change as it stands, with an explicit focus on human readability?*
2. **Did we build the right thing?** Against the ticket, read with the approved plan attached to it
   (`/plan` §5 posts it there) — a ticket's scope often moves during planning. Where the ticket and the
   plan disagree, report it: the plan's recorded, approved decisions govern, and a divergence the plan
   does not record escalates.

Both are answered, each with its own verdict, and neither stands in for the other. In the thoroughness
paragraph above, *the properties the artifact must hold* are, for the first question, the properties
that engineer holds code to — not the plan's decisions.

Brief it with:

- **Both questions, the first quoted verbatim.**
- **The ticket with the approved plan attached** — the authority for the second question. With no
  plan (the human wrote the code), the ticket alone.
- **The ticket-specific criteria**, each citing an authority outside the plan (`/plan` §3). The plan's
  own rulings are checked under the second question, from the plan itself; restated as criteria they
  turn the brief into a compliance audit, the failure this section exists to stop.
- **The method and checks below, copied in** — whichever agent reviews, the bar travels in the brief,
  not in that agent's definition.

It reviews by:

- **Reading the ticket and plan first**, so its expectation of what should exist comes from intent
  rather than from the code — that is what catches an omission.
- **Paraphrasing each changed unit as its next maintainer would.** For each unit the change adds or
  alters, say in one sentence what it does; the paraphrases go in the reviewer's report file, not the
  digest, as the evidence the read happened. Anything that had to be read twice to say is a finding,
  named with the misreading it invites — *"the next editor takes `retry` for idempotent and calls it
  twice"* — not "this is unclear." Prompts for that read, not a list to tick: names that say what the
  thing is in this project's vocabulary; control flow that reads top to bottom; one thing per unit at
  one level of abstraction; the construct a fluent writer of the language reaches for, not clever or
  needlessly general code; no checks for states the types or callers already rule out — handling at a
  real boundary is expected, not noise.
- **Holding findings to what the change introduced or left harder to read.** Pre-existing debt in a
  unit the change touches may be fixed when the fix is minimal — tidying the docstring of the function
  being changed is encouraged; rewriting every docstring in the file is not. "Works, but restructure
  it" is a legitimate blocking finding when the restructure is what makes the change maintainable; it is
  settled in the peer loop when its fix changes no interface, contract, shared value, abstraction, or
  decision the plan made, and escalates as a plan finding when it would.
- **Naming the tool when a finding's class is likely to recur** — a linter rule, a formatter, a gate
  that would catch it automatically. The recommendation goes to the human, who decides whether it
  becomes a ticket or lands in scope.
- **Reporting a ruling that produced code that engineer would reject as a finding against the plan**,
  which escalates like any plan finding. "The plan said to" settles the second question, never the
  first.
- **Ending with both verdicts.** For the first, *accept as-is*, *accept after the listed fixes*, or
  *send back*, argued from the code; a *send back* is reworked in the peer loop. For the second,
  whether the change builds what the ticket and plan ask, with any gap or excess listed; a gap the plan
  already settles is fixed in the loop, one that questions the plan or the ticket escalates.

**What that engineer also catches** — standing checks in service of the questions, none a substitute
for them:

- **Correctness** against the stated intent.
- **Scope discipline** — nothing beyond the ticket; no drive-by refactors. A minimal cleanup inside a
  unit the change touches is not one.
- **Idiom** — the language's idiom wins over local habit unless the project hard-documents the
  convention (a style guide, `CONTRIBUTING.md`, a linter config).
- **Shared-contract consistency** — any value that must agree across a boundary is defined once or
  tested for agreement, never kept in sync by a comment.
- **Abstraction with no second consumer** — new extension points, registries, or indirection built
  for a case that does not exist yet.
- **A new dependency does work the standard library cannot reasonably do.** Ask it once per added
  dependency, at the moment it is cheapest to answer; nothing downstream will.
- **Orphaned references** — deletions leave nothing dangling. Grep for the removed names.
- **Tests that assert something.** A new test that cannot fail is a false signal.

**Comment & documentation-discipline reviewer — check for:**

- **Comment density is an absolute bar, not calibrated to surrounding code** — minimal: a comment
  appears only where the code cannot be read on its own without it, where it states a mechanism, or
  where it is the language's or tool's own documentation standard (a docstring, godoc, JSDoc). No
  narrative blocks. Existing sibling comments are legacy density to trim within the unit the change
  touches, never the standard to match; a reviewer who calibrates to neighbours passes what the owner
  rejects.
- **Comments state mechanism, not reason.** How the code does something it cannot show on its own
  stays; a statement
  of why, of history, or of evaluative judgment belongs in whichever doc the repo's map assigns it,
  with the comment citing that home instead.
- **A citation cites rather than restates.** Strip the identifier from the sentence — if any
  assertion still stands without it, the comment restated the source rather than pointing at it, and
  the repo now holds the same fact twice.
- **The §4 documentation sweep landed** — every doc the change affects updated, each fact in the one
  home the repo's doc map assigns it, no restatement across docs.
- **No point-in-time numbers** — coverage percentages, test counts, file counts; document the
  mechanism a reader re-derives the current number from, not a figure that rots.
- **No temporal phrasing** — "now", "currently", "no longer", "previously", "recently"; state the
  timeless fact.
- **A decision with a genuinely rejected alternative has a decision record**, not a prose paragraph
  buried in a history file.

**Test-quality reviewer (testing-architect) — check for:**

- **Tests assert behaviour, not execution.** A test that runs a code path but carries no assertion
  capable of failing on a wrong result is coverage padding, not verification — name it as such.
- **Coverage-padding patterns** — an assertion on a trivial invariant (a function returned *something*,
  a mock was called), a snapshot test with no reviewed expectation, or a test shaped to move a number
  rather than pin a fact.
- **Defensive or error-handling code deleted to make a diff coverable**, rather than exercised by a
  test that reaches it. This is the specific inversion the reviewer exists to catch: the code got
  easier to test by getting worse, not the tests got better.
- **Boundary and failure-path coverage** — a changed boundary or a changed failure path (empty input,
  timeout, malformed data) has a test able to fail on the wrong behaviour, not only exercise the happy
  path.
- **Test doubles stand on a backed contract** — a mock's behaviour is proven to match the real thing
  somewhere, or the diff introduces an unbacked assumption.

Lean on CI for the gate exactly as in step 3 — cite `gh pr checks <n>` rather than re-running the
suite. Reserve local runs for a targeted check of a specific concern the diff raises.

### Applying findings

All three reviewers' findings converge on the same diff; apply them the same way.

**Under orchestrator mode, fixes happen in the implementer teammate, not on this thread** —
`Edit`/`Write` are gated here, and each reviewer sends its findings straight to the implementer, so you
neither apply fixes nor relay them. The second-pass rule below holds as a direct reviewer↔implementer
exchange, not a round-trip through you. **Exception, TDD-paired item:** a test-quality fix on a
`test-first`-authored test is not the `code-monkey` implementer's to apply — a spec/contract question
escalates to you, and mechanical test repair goes to a `test-writer-fixer` teammate spawned for it
(`/plan` §3's routing), since `code-monkey` cannot edit tests and `test-first` does not live into review.

**Running standalone (no orchestrator mode):**

- **Mechanical fixes** — a local rename, a missing null check, a doc correction, a comment reworded to
  state mechanism — apply them and say you did.
- **A fix touching what a finding was about** — a boundary contract, a shared value, an abstraction the
  content reviewer questioned, a doc-map placement or decision record the discipline reviewer flagged,
  a readability restructure the content reviewer asked for, or a test the test-quality reviewer found
  to be coverage-padding or built on deleted defensive code —
  **goes back to the reviewer that raised it for a second pass** on that fix. This is the class of
  defect the review existed to catch; re-introducing it while patching is the specific risk. Size is
  not the test here; subject matter is.
- **If you wrote the code yourself**, do not apply subject-matter fixes without that second pass —
  patching them yourself puts unreviewed changes back downstream of your only independent read. CI
  passing is not a substitute; CI never reviewed anything.

Commit fixes as their own review-fix commit(s), push, and re-confirm the affected CI job.

A clean diff is a clean diff — say so plainly rather than inventing issues to look thorough. **A
passing review is not authorization to merge** (step 7).

## 7. PR hygiene

- Branch pushed with the **final** commits (the branch was pushed in step 2; push again if the docs sweep
  or review fixes added any).
- **PR description matches the final state**, not an earlier draft, and the **base branch is
  correct**.
- **CI all-green on the final commit** via `gh pr checks <n>`, including any expected bot comments
  (coverage reports and similar).
- Only then is it merge-ready. **Do not merge unless explicitly asked** — the merge is the
  irreversible, human-gated step. If the repo protects its default branch, an admin override bypasses
  a governance control and needs its own explicit go-ahead.
