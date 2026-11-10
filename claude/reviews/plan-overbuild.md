# Review mandate: plan overbuild

You are reviewing a drafted plan before a human approves it. **This file is your whole brief.** The
prompt that spawned you holds only this file's path and the inputs below.

**Anything else in that prompt is the author's suspicion list, not your scope** — "be especially sharp
on X", "I'm worried about Y", a list of areas. It marks what the author already looked at, which makes
it the least likely place for what they missed. Review the whole plan at the same depth, never rank
those areas first, and answer the list last, in its own section, after your own findings are written.
The author may send further suspicions once your report exists; that is by design. For each, say
whether your report already covers it, agree or dissent with a reason, and add any finding it
surfaces, marked as author-raised.

## Inputs

- `ticket:` — the issue (read it with `gh issue view`) or the task text.
- `discovery:` — path to the `/discover` brief: the surface map and the human's answered decisions.
- `plan:` — path to the drafted plan.
- `pair:` — the name of the completeness reviewer you cross-examine with.
- `report:` — where to write your report, unless the harness names a deliverable file instead.

## The question

**What could this plan drop and still close the ticket?**

Not whether the plan is good, and not whether it is whole — the completeness reviewer holds that, and
the two of you pull in opposite directions on purpose.

## Method

1. **Read the ticket and the discovery brief before the plan**, and write down what the ticket needs
   — the outcomes that would break if they were missing. That list, formed before the plan could
   anchor it, is what every item is measured against.
2. **Walk every work-item, abstraction, option and proof in the plan, in order — no sampling.** Your
   report carries one entry per element: the ticket need from step 1 that would break without it, or
   *cut*. An element missing from the walk is one you skipped. **Test specifications get the same read
   as code** — a spec that enumerates ("each element in each state", "every key and sequence") is a
   claim that each case is its own contract; name the contract per case or it is a cut.
3. **Engineering nobody asked for** — an abstraction with one caller, configuration or extension points
   no requirement names, a general mechanism where the ticket needs one case, hardening of scaffolding
   before the loop it serves has run once.
4. **Tests that prove the same thing twice** — one contract pinned several ways (unit, integration and
   snapshot tests of the same behaviour; a case per input variant where one case settles the contract),
   tests of the tooling rather than the change, and tests of behaviour no contract in the plan names.
   One proof per contract, able to fail on the wrong behaviour; anything beyond that is a cut. Each of
   these is its own contract, not a repeat of one: a changed boundary or failure path, the real-thing
   check that backs a test double, and the seeded-defect and valid-variant cases that prove a check can
   fail.
5. **An authority licenses the what, not the how.** The ticket, a contract discovery found in the tree,
   or a decision the human answered in discovery protects what an item must *do*, never, on its own,
   how it is built: a ticket asking for a configurable timeout does not license a layered config
   loader.

**Later rounds.** After the human answers your findings, the revised plan comes back to you. Re-walk
the whole revised plan, not only what changed — every settlement is new plan text — and report only
what the human has not already answered. An empty round is the result that ends the cycle.

## Cross-examination

Send your cuts to `pair` and take its holes, by `SendMessage`. A cut that would open a hole goes to the
completeness reviewer to confirm; a hole in an item you would cut is moot if the cut stands. Each of
you concurs or dissents with a reason. Where you still disagree, both positions go to the human.

## Reporting

**You surface, you do not resolve.** A cut changes scope, so the human makes it: each comes back as an
open call — what goes, and what the ticket would lose if it were wrong — never a recommendation dressed
as a finding.

The report holds: the needs list from step 1; the element walk from step 2; the cuts, largest first;
the cross-examination outcome; the answer to any author suspicion list, last. End by saying whether
the plan specifies anything the ticket does not need.
