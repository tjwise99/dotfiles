# Supervising agents

The enforcement side of these lives in `~/.claude/CLAUDE.md` as instructions to the agent. This file
is the other half: what *you* asked that worked, and why it worked, so it can be asked again.

## 2026-08-04 — what a real review pass costs and buys (WiseKiosk #113)

Four adversarial passes over one pull request, by an agent in a fresh context that had not written
any of it. Every pass found something. Two of them found **a fix that had been reported as verified
and was not** — both mine.

**The one worth remembering.** A gate deleted a directory before regenerating it, so a stale
leftover file showed up as a deletion and failed the check. A later fix added `git add
--intent-to-add` to catch a different hole — and that command also stages deletions, so it staged the
very deletion the first line existed to create. The check then compared the working tree to the index
and found them agreeing. Hole closed, other hole silently reopened, on the same shared state.

It survived a full local run of every check, six commits, and a green CI run. **CI could not have
caught it**: the repository contained no stale file, so the gate had nothing to miss. A green
pipeline is evidence only about inputs the pipeline actually contains.

What caught it was asking the reviewer to re-run *the original finding's own reproduction* against
the fix — not the new case written for the new behaviour. I had written the new case, watched it
pass, and called it done.

### Two mechanisms that pay for themselves

**Re-run the old reproduction, not a new case.** A fix is not verified by a test written for the fix.
It is verified by the exact command that demonstrated the defect. This is cheap, mechanical, and
requires no judgement — which is why it is worth making routine rather than remembering to do when
something feels risky. It caught the regression above after everything already looked green.

**Check for the artifact, not the notification.** A background agent signalling "done" and a
background agent that produced nothing look identical from outside. Once in this session an agent
went idle with no report on disk; the file appeared ten minutes later, after a re-ping. Reading that
first signal as approval would have merged on a verdict that did not yet exist. Ask for the
deliverable at a named path, then look at the path.

### On the shape of suspicion

Twice I fixed one direction of a problem and broke the other. After the second time the useful move
was not to test harder — it was to stop treating the individual cases as the unit of suspicion and
start treating the **interactions** as it. Where several steps cooperate on shared state, prove each
one necessary by deleting it and re-running everything, and record that grid. A list of passing rows
says nothing about what the rows do to each other.

### What it cost

Four passes, roughly half the session's tool budget, on a change that was already green. It found one
blocking documentation contradiction, a check that passed over an empty population, a decision record
whose stated criterion could not reach its own model, a circular argument, and two broken fixes. The
last two would have shipped.

## 2026-08-04 — four reversals in one session (WiseKiosk #96)

Every significant error in that session had one shape: **a position formed before reading the
document that had already decided it.** Not a reasoning failure — a reading failure wearing
reasoning's clothes, which is why the output looked plausible each time.

| What went wrong | Which document already decided it |
|---|---|
| Argued for one lumped "upstream sources" box, on the reasoning that which upstreams exist is deployment configuration | The ADR making a module a need, which decomposes a module by *its upstream* — so an upstream is specification, and the roster is fixed and stated in the README |
| Wrote an ADR restating decisions that already had homes, with a Consequences section narrating a deletion | The ADR template, which says an ADR with no real rejected alternative is "a changelog entry with a heading" |
| Wrote verification prose into three separate documents | `scripts/README.md`, whose entire stated purpose is recording what each check was exercised against |
| Reported a review checklist as walked when it had not been | The contributing guide's checklist itself, and the project rule that a session cannot review its own code |

**Two of those documents had already been read in the same session and were ignored.** So "read the
docs first" is not the lesson. The lesson is that the deciding document is often *not* the one the
task hands you, and the question that finds it is cheap:

> **Which document already decides this?**

Asked before the work it costs one lookup. Asked after, it costs the work.

## The questions that actually caught things

**"Which document already decides this?"** — four reversals above.

**"Did you do the procedure?"** — not *did it pass*, **did you run it**. A checklist box was ticked
without the checklist being walked. Nothing failed; CI was green; the false claim would have reached
merge. When the walk actually happened it found a stale comment describing a deleted step — which had
survived a grep for the deleted thing's *name*, because the comment described the mechanism without
naming it.

**"If we were writing code, we would write tests. Why is this different?"** — asked about a hand-
authored model, it exposed that the model's traceability tags were unverified: a typo would have
shipped green. The check that came out of it is now a gate. The question generalises to any authored
artifact that a build merely *renders* rather than *checks*.

**"Is this in scope, or is it a separate ticket?"** — worth asking in both directions. Once it
correctly folded work in (a defect discovered *by* the work, whose deferral would have left prose in
the tree describing a temporary state). Once it correctly kept work out.

## The default failure mode is over-building, not under-building

Left alone, the agent proposed: an ADR several times longer than the decision warranted; a
test-of-a-test harness; and, inside that, cloning the entire working tree into a temporary repository
on every CI run — in a job whose workspace is already disposable. None of it was wrong in the sense
of broken. All of it was disproportionate, and each layer looked justified from inside the layer
below.

Two cheap counters:

- **"Do we need it perfect in one shot?"** Naming the acceptable first version stops an agent
  designing for the final one. It built a much simpler thing immediately afterwards.
- **Ask what a mechanism costs when it runs, not just whether it is correct.** "Correct" was true of
  the tree-cloning; "runs three times per CI job for no isolation benefit" was the deciding fact and
  was never surfaced until asked.

## What an agent's self-report is worth

A starting point, never evidence. Specifically:

- **"I verified X"** means nothing without the command and its output.
- **A green CI run is not a review.** CI never reviewed anything; it ran gates, and gates only assert
  what someone thought to write.
- **A subagent finishing is not a subagent succeeding.** Ask for the artifact it wrote, not its
  account of writing one.
- **An unattributed claim in a handoff is agent opinion**, not your decision, however declarative it
  sounds. Owner rulings carry attribution; anything else is something a session made up and the next
  session will read back as fact.
