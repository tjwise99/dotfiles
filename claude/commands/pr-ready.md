---
description: Run the merge-readiness checklist for the current PR branch (scope, verify, docs sweep, code review, housekeeping). Works on any repo and any code, whoever wrote it.
---

# Get this PR merge-ready

Work through the steps below for the current branch, in order. **Do the work** — run the commands,
make the doc edits — don't just report on it. Report a short pass/fail summary per section at the
end, and stop to flag anything needing a human decision.

This command is **source-agnostic**: it runs the same way whether the human wrote the code, an agent
wrote it in another context, or you wrote it yourself in this session. The one thing that changes is
the review mode in step 6 — see the table there.

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

**If orchestrator mode is on** (the `/work-ticket` flow leaves it on through this step), you cannot
read the diff or edit on this thread — `git diff …`, `Read`, and `Edit` are gated. **Delegate the
review to a fresh-context reviewer** (e.g. `independent-reviewer`): give it the diff range and the
spec, not your account of the work; have it write findings to its deliverable file; read those back
to decide. This is not a downgrade — for the `/work-ticket` case (a plan you wrote, code a subagent
wrote) an independent read was the right mode anyway, so orchestrator mode only makes mandatory what
the table below already recommends. The table still governs *who* reviews; the mode forces it off
this thread.

**First establish who wrote the code**, because it determines whether you are capable of reviewing
it independently:

| Who wrote it | Your independence | Review mode |
|---|---|---|
| **The human**, or an agent in a session you had no part in | Full — no authorship stake | **Review inline, here.** No subagent needed; spinning one up adds cost and no independence you lack |
| **An agent in another context, from a plan you wrote** (e.g. the `/work-ticket` flow) | Partial — you specified it but didn't write it | **Review inline**, but treat the plan itself as suspect too: you share its blind spots. Verify against the ticket's intent, not just the plan |
| **You, in this session** | **None** — you would be reviewing your own work | **Spawn a fresh-context reviewer.** Give it the diff and the spec, *not* your account of what you did. An agent reviewing its own output reviews its own intent, which is precisely what needs independent checking |

Whatever the mode: **verify prior claims, don't trust them.** An implementer's self-report is a
starting point, never evidence.

Check for:

- **Correctness** against the stated intent.
- **Scope discipline** — nothing beyond the ticket; no drive-by refactors.
- **Idiom match** — naming, comment density, and structure consistent with surrounding code.
- **Shared-contract consistency** — any value that must agree across a boundary is defined once or
  tested for agreement, never kept in sync by a comment.
- **Abstraction with no second consumer** — new extension points, registries, or indirection built
  for a case that does not exist yet.
- **Comments state mechanism, not reason.** What the code does or how it does it stays; a statement
  of why, of history, or of evaluative judgment belongs in whichever doc the repo's map assigns it,
  with the comment citing that home instead.
- **A citation cites rather than restates.** Strip the identifier from the sentence — if any
  assertion still stands without it, the comment restated the source rather than pointing at it, and
  the repo now holds the same fact twice.
- **A new dependency does work the standard library cannot reasonably do.** Ask it once per added
  dependency, at the moment it is cheapest to answer; nothing downstream will.
- **Orphaned references** — deletions leave nothing dangling. Grep for the removed names.
- **Tests that assert something.** A new test that cannot fail is a false signal.

Lean on CI for the gate exactly as in step 3 — cite `gh pr checks <n>` rather than re-running the
suite. Reserve local runs for a targeted check of a specific concern the diff raises.

### Applying findings

**Under orchestrator mode, apply every fix through a subagent** — `Edit`/`Write` are gated on this
thread — and the second-pass rule below (a fix touching what the finding was about goes back to the
reviewer) still holds.

**In the first two modes, fix findings inline.** You hold the full review context, so patching a
finding yourself is the cheap path; resuming an implementer subagent re-runs a fresh inference pass
over its entire transcript. Bounce back only for a **large, cohesive chunk of new implementation** a
finding exposes — not a normal review nit.

**In the third mode — you wrote the code and delegated review — applying the fixes yourself puts
unreviewed changes back into your own work, downstream of the only independent read.** CI passing is
not a substitute; CI never reviewed anything. So:

- **Mechanical fixes** (a rename, a missing null check, a doc correction) — apply them and say you
  did.
- **A fix touching what the finding was about** — a boundary contract, a shared value, an
  abstraction the reviewer questioned, error handling it flagged — **goes back to the reviewer for a
  second pass** on that fix. This is the class of defect the review existed to catch; re-introducing
  it while patching is the specific risk. Size is not the test here; subject matter is.

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
