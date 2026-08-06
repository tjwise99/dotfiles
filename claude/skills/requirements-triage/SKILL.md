---
name: requirements-triage
description: >-
  Decide which requirements earn their place in a specification, and rewrite the ones that stay.
  Applies a repeatable test — does this state a want, or does it restate its own decomposition,
  an ethos, a premise, or a tool we happen to run? Produces merges, demotions and deletions that
  provably lose no obligation. Invoke when a spec has grown unreviewable, when asked to "trim",
  "condense", "clean up" or "review" a requirements set, when a tier has too many items to hold in
  one head, or when a requirement "feels like a list" / "feels lame" / "reads like a preference".
  Spec-tool-agnostic — works on Doorstop, DOORS, a spreadsheet, or Markdown.
---

# Requirements triage

A requirements set becomes unreviewable long before it becomes wrong. The usual cause is not
sloppiness but accretion: each item was defensible when written, and nobody has since asked whether
the set as a whole says anything a person can hold.

This skill is the asking. It is **judgement work with mechanical guardrails** — the guardrails prove
you lost nothing, they do not tell you what to cut.

## The governing rule

**A requirement states a want. Everything else has a different home.**

Most bad requirements are not wrong, they are misfiled. Before deleting anything, know where the
content goes — a deletion whose content has no home is a loss, and the owner will reject the pass
for it.

| What it actually is | Where it belongs |
|---|---|
| A product premise ("the operator is not the author") | The product README — prose, where it can be read |
| A settled decision with a rejected alternative | A decision record / ADR |
| A design preference ("prefer the standard library") | A working-practices doc, or nowhere |
| A tool we run (a lint rule, a scanner) | Verification tier, or tool configuration |
| A specification of a check | The verification tier, as a check |
| A feature nobody has committed to | A ticket, with a reopen path recorded |
| A reason | The `rationale` of the requirement it justifies |

## Before the items: settle what a requirement is

Two questions decide the shape of the whole pass, and answering them item by item costs far more than
answering them once.

**Does this set contain obligations about the repository rather than the product?** House rules —
branch naming, line endings, comment style, whether a link resolves, which scanner runs — accrete into
requirement sets because each was defensible when written and nothing routed them elsewhere. They are
recognisable by one test: **nothing the software does can violate them.**

The expensive mistake is trying to *classify* them. On the pass that produced this section, two review
rounds went into building a discriminator that would sort repository obligations from product ones,
two amendments to that discriminator were drafted and both rejected as bolted-on, and the answer
turned out to be that the question was wrong. **Move them out of the specification entirely, into
their own document, and there is nothing left to classify.** The checks still run and still block;
what changes is that adding or retiring one becomes a document edit rather than a specification
change.

Expect the objection that this loses traceability. Ask what the traceability was buying — a lint rule
tracing to a requirement is ceremony, and a check's continued existence is usually guaranteed by
whatever invokes it.

**Second: if the pass needs a rule to classify a family of items, write that rule first, as its own
pass.** A discriminator written mid-flight is applied before it is examined. On this pass one was
drafted after four items had already been decided by it — in conversation, unrecorded — and was found
too wide the next day, by which point it silently reached seven more. Expect the first draft to
over-reach: a one-line rule that sounds decisive is usually not, and what transfers is a taxonomy plus
worked cases rather than the sentence.

## Phase 1 — Read the tier as a set

Do not start item by item; you will defend each one and cut nothing. Get the whole tier in front of
you, then look for **shape**:

- **What is this tier about?** If a third of it is about the repository rather than the product, the
  need tier has been colonised by house rules.
- **Which items share a subject?** Items elicited in different rounds routinely say the same thing
  in different postures. Four "don't leak secrets" requirements is one want, filed four times.
- **Fan-out.** An item with one child is a prompt to read the pair, not a verdict. An item whose
  children restate it is a hat.

## Phase 2 — The tells

Each of these is a reliable signal. None is proof; each is a reason to read the item closely.

**It enumerates its own children.** *"…shall be hardened: it shall run as non-root, pin its base by
digest, and exclude dev material."* Three clauses, three children. The need is a table of contents.
→ *Fix:* state the want; let the children carry the specifics.

**Its child restates it verbatim.** The obligation exists once, at two tiers.
→ *Fix:* usually the parent goes (the child is the testable form), unless the parent states a want
the child only implements.

**It is a philosophy.** *"No check shall claim more than it settles."* Nothing can be failed against
it — and the concrete version is usually already in a child.
→ *Fix:* replace with the falsifiable predicate; move the philosophy to `rationale`.

**It is a premise.** *"The system shall be operable by a non-technical operator."* True, load-bearing,
unverifiable. Its own justification often admits this.
→ *Fix:* move to the product doc. **Then watch for the consequences** — obligations that existed only
to serve the premise will surface homeless, one at a time.

**It is an ethos.** *"No abstraction without a second consumer."* A taste rule; its decidable slice
lives in a child.
→ *Fix:* drop the parent, keep the slice, or drop both if the slice is also taste.

**It forbids a case that does not exist.** *"No dynamic module loading, no module discovery, no
runtime registry, no third-party extension API."* Generality against a case nobody proposed —
inverted.
→ *Fix:* strike the prohibition. If the case is foreseeable, record a **reopen premise** in
`rationale` instead: *"Reopen if X, because Y."*

**It is a check specification.** *"Comments shall be at most N lines."* That is a lint rule written
into the spec, and a threshold you may want to tune without a spec change.
→ *Fix:* demote it to the verification tier as a check.

**It constrains the repository, not the software.** *"A branch shall be named `type_number-name`."*
Nothing about the running system changes if a branch is misnamed. Ask the question directly — **is
this an obligation on the software, or a convention of the repository that builds it?** A convention
is a check if a machine decides it and a review habit if not. Neither is a requirement.
→ *Fix:* mechanical ones demote to the verification tier; the rest go to a review checklist.

**It is a good sentence with prohibitions bolted on.** *"The frontend shall build to a static bundle.
It shall emit no server-rendered markup, contain no routing library and no meta-framework runtime."*
The first sentence is the requirement. The rest are failure modes the author imagined, and they age
badly: one is entailed by the positive statement, one is orthogonal to it, and one uses a term
nobody else can define.
→ *Fix:* keep the positive sentence. Strike the tack-ons individually, each with its own reason.

**Its content is one instance.** A requirement naming one module, one endpoint, one file.
→ *Fix:* it is implementation detail. Move it to that component's work.

**It states a fact about somebody else's environment.** *"The backend container shall run on a
Docker-capable amd64 or arm64 host."* Nothing there is ours to require — a host's capabilities are
the operator's. The obligation hiding underneath is *we run on both*.
→ *Fix:* restate as what the system does. **And check how it got that way:** this one became a
premise when its obligation half — *"and the image shall be published for both architectures"* — was
struck earlier in the same pass. **Striking a clause can leave the remainder unfalsifiable.** Re-read
any item you cut a clause from, as a whole sentence, before moving on.

**It over-specifies a positive.** *"For each source, the backend shall expose a stateless endpoint
`GET /api/<source>`."* Not a prohibition, so the forbids-a-case-that-doesn't-exist tell misses it —
but it pins a route template and, quietly, a **cardinality**. A module needing two upstream calls is
forbidden by a clause written for neither purpose, and the literal path declares an interface that is
defined elsewhere.
→ *Fix:* ask of each specific in a positive statement — *what would break if this were different, and
did anyone decide it?* Keep coverage and behaviour; give shape and count back to whatever owns the
interface.

**Header, text and rationale disagree.** Three claims about one obligation, and they drift apart
whenever text is rewritten and the others are not. One item's header announced a TTL cache its text
had stopped obliging; another's rationale claimed *"any deployment-specific content"* while its text
said only *"no configuration file."*
→ *Fix:* read all three as one claim. Then use the disagreement: a rationale broader than its text is
evidence the **text is too narrow**, and a header naming a mechanism the text does not oblige is
evidence the **header is stale**. This is the cheapest defect detector in the set and it costs one
read.

## Phase 2b — Rewriting the ones that stay

A requirement that survives usually still needs rewriting. Three heuristics do most of the work.

**State the obligation, not the failure mode.** A clause that resists rewriting — where every attempt
comes out long, metaphorical, and still vague — is almost always naming what must not happen instead
of what must. Watch for a sequence like this:

> *"shall never act as an unbounded relay"* → *"shall not be drivable as a relay"* → *"shall decide
> what it requests, never a client"* → **"shall issue only the requests its configuration calls
> for"**

The first three describe the failure; the last describes the obligation, and is the shortest of the
four. Flipping it also fixed a mis-trace: a child that looked unrelated under the negative wording
(it read as being about error responses) traced directly under the positive one, because the positive
form named the thing the child constrains.

**If the reader has to ask what a phrase means, it failed.** Not a matter of taste — a phrase whose
meaning has to be supplied by its author cannot be checked by anyone else. "Drivable as a relay",
"claim no more than it settles", "where the operator looks" all read as precise to the person who
wrote them and as noise to everyone else.

**Beware the phrase that is not merely vague but false.** "Never a client" survived two rounds of
review before someone noticed the frontend *is* a client and legitimately triggers the behaviour being
forbidden. Vague wording hides; false wording actively misleads a future implementer.

**Put the obligation in the requirement and the mechanism in the check.** *"The backend shall build as
a statically linked binary with cgo disabled, demonstrating that no dependency requires a native
toolchain"* states a want and one way of establishing it, welded together. The want is the second
half. Split them and the requirement stops pre-deciding how it is verified — which matters most when
the code does not exist yet, because the mechanism is chosen by whoever writes it, not by whoever
wrote the spec first.

The same split applies to a threshold: a duration, a sampling interval, a tolerance, a percentage
belong in the check, where they can be tuned without a specification change. A requirement whose text
begins *"Verification shall…"* is announcing that it has swallowed its own check.

## Phase 3 — Dispositions

Every candidate lands on exactly one. Nothing is "cleaned up".

1. **Keep** — a distinct want no other item states.
2. **Merge** — its obligation folds into another as a clause. Name the target and give the resulting
   text.
3. **Demote** — it states a *shall* an implementer codes, or a check a tool runs. It moves down a
   tier.
4. **Demote to a check** — a convention a machine decides. The requirement dies and its verification
   item survives, re-parented to whichever requirement obliges checks to run. Nothing is lost: the
   check still runs and still blocks. What you give up is the spec *saying* the convention exists, so
   adding or retiring one becomes a check edit rather than a specification change. That is usually
   the right amount of ceremony.
5. **Move to a review checklist** — the obligation is real, no machine decides it, and it constrains
   an author rather than the software. This is not a soft deletion. **It is the disposition that
   creates an activation path**, which is the thing whose absence justifies deleting a
   judgement-based item in the first place: an inspection nobody is prompted to perform is a dead
   letter, one a review flow walks on every change is not.
6. **Drop** — no obligation, or wholly carried elsewhere.

**The discriminator for demotion and deletion: name the surviving clause that carries the
obligation, and quote it.** If nothing carries it, you have deleted a want, not condensed one.

**When the discriminator is contested, name what breaks.** Enumerate the concrete failure the item
forbids, then ask what catches it now. Three outcomes, and each settles the item:

- **Something already catches it**, perhaps later but reliably — the item is redundant. A build-mode
  requirement fell this way once its failure was shown to break a multi-architecture publication
  check that already existed.
- **Nothing catches it and nothing ever did** — the item was protecting a property no one measures.
- **The failure cannot occur** — check the tooling before believing the item's own account of its
  threat. One requirement guarded against a code generator emitting runtime validators; the pinned
  generator has no such mode, so its stated reason for existing was false.

## Phase 4 — Invariants, checked after every ruling

These are mechanical. Check them with a script, not by eye.

- **No orphans.** Every child still has a parent. Every parent still has a child.
- **Every obligation traces to a *clause*, not just to an item.** Item-level linking hides
  clause-level orphans, and merges are what manufacture them.
- **Method consistency** (if your tool carries verification methods): a parent sits at the
  least-decidable method among its children. Re-parenting a judgement-based child onto an
  automated parent silently weakens the parent.
- **Cascades are recorded.** Deleting a requirement orphans its verification items. List them.
- **Every clause traces to a recorded decision.** After authoring a tier, search the decision record
  for each distinctive phrase in it. A clause nobody can point at entered unruled — it reviews as
  ordinary content while encoding a choice nobody made, which is the defect this whole pass exists to
  catch, occurring inside the pass itself. This found a whole sentence of a locked, already-committed
  requirement whose wording appeared in none of the fifty-three rulings that produced the tier.

## The three traps

**Identifiers that moved.** Renumbering, merging or deleting changes what an identifier means, and
every spec tool updates its *link* structure while leaving identifiers written inside prose — a
requirement's text, its rationale, a citation in a design document — exactly as they were. Two
failure modes, and only one is findable by a checker:

- **Dangling** — names something that no longer exists. Any existence check finds these.
- **Re-pointed** — resolves cleanly to *the wrong requirement*, because that identifier now belongs
  to something else. **Nothing can detect this.** It reads perfectly. A verification item citing
  "the SRS026 rejection body" was flawless prose pointing at an item about client identity.

The only defence is a **map from old identifier to new**, and your tool will not give you one — build
it by matching item *text* across the change, before and after, and save it with the change that
caused it. Then read each reference in context: a citation written before the change means what it
meant then; one written after means what it says now, and no map can tell you which.

**A governing decision that contradicts itself.** When a decision record carries both a routing
mechanism (a table, a rule) and the rationale for it, check that both can hold. One here sent
conventions to the verification tier *because* it wanted them to stop being specification changes —
and the verification tier was inside the spec. Every downstream ruling inherited the contradiction,
and the reviewers who found the resulting mess kept attributing it to the rulings rather than to the
rule. **When a set of decisions all look slightly wrong, suspect the decision above them.**

**Stale re-parenting.** You re-home a child onto parent A; three rulings later you dissolve parent A;
nobody re-checks the child. This is the single most likely way to lose obligations in a long session,
and it is invisible in a summary document — the summary freezes the intermediate state and reads
fine. **After every ruling, re-verify the parentage of every child moved by an earlier one.**

**Count drift.** Running totals stated by increment go wrong. Recompute from the baseline set each
time and state the arithmetic.

## The artifact is the ledger

**Apply each ruling to the specification as it is taken, in the same act as recording it** — not in a
final write-up pass. This is the highest-leverage rule in this document, and most bookkeeping failures
trace to breaking it.

A decision log separated from the artifact for days produces a specific, repeatable set of failures:

- **A deleted item is still on disk, so it reads as surviving.** A later ruling cites it as a covering
  parent and nothing objects — not the tool, not a reviewer, not a citation checker, because the file
  resolves.
- **The count becomes arithmetic in prose**, and prose arithmetic drifts. Applied rulings make it a
  directory listing.
- **Orphan and method invariants cannot run**, so clause-level defects are found by eye or not at all.
- **Reviewers read the log instead of the specification.** A log is a narrative, and a narrative is
  re-derived rather than checked.

Renumbering is not a reason to defer. Deleting, merging and rewording need no renumber; identifier
assignment is a mechanical final step and should be the only thing left to it.

### Buy replay, not another reviewer

Across four independent review rounds on one specification, **every round found bookkeeping errors and
none found a reasoning error.** The merge reasoning survived every review it was given; the
bookkeeping failed every one.

That is an argument about where to spend. Before commissioning another reader, write the script that
replays the record against the artifact:

- every identifier cited in a ruling resolves to an item the pass keeps
- every ruling in the log has been applied
- every item the artifact still contains appears in the log
- the count claimed in the log equals the count on disk

Each of those caught a real defect in seconds that a human reviewer found in hours or missed.

## Process discipline

- **One decision at a time.** A tiered spec has threads that interleave; the owner cannot hold them
  in parallel. Present one question, with a recommendation and the count impact.
- **Record each ruling immediately, where it will outlive the conversation** — an issue comment, a
  decision log. Reasoning stated only in chat is lost, and it is the reasoning that has value.
- **State a recommendation.** "Here are three options" pushes the work back onto the owner. Give the
  lean and the reason; they will overrule you when they have context you lack, and that is the point.
- **Overturning a recorded decision is a finding, not a merge.** Say so explicitly and give the
  grounds, usually that the premises changed.
- **Validate mechanically first, independently second.** The context that made the decisions cannot
  audit them — it will re-derive its own reasoning and find it sound. But a reviewer is the expensive
  instrument: replay the record against the artifact before you commission one.
- **Record every decision inside the versioned artifact, never in a ticket.** A ticket thread cannot
  be checked by anything, fails no gate when it rots, is unreadable from a clone, and after any
  renumber describes a specification that no longer exists — one pass made a thread its authoritative
  record and hit all four. Note the asymmetry that pushes decisions out there: a surviving
  requirement carries its reasoning in its own `rationale`, permanently, while a *deleted* one leaves
  nothing behind. **So the commit that removes an item is where its reasoning goes** — what went,
  why, what covers the obligation now, and anything knowingly given up. That is retrievable from the
  absence (`git log -S '<phrase>'`), which is the direction that matters. A principle the pass
  established belongs in a decision record. A ticket holds scheduling, not decisions.

## Validating with an adversarial pair

One neutral reviewer produces one reading. Two reviewers with **opposed briefs** produce a
disagreement, and the disagreement is the finding. Run this when the pass is large enough that "we
agree on most of it" would otherwise go unchallenged.

**Brief them to the extremes and mean it.** One argues every item earns its place; the other that
every survivor is guilty until it proves it states a want no other item states. Neither is asked to
be balanced — you are, later. A reviewer told to be fair produces a shrug.

**They file blind.** Each writes its case without seeing the other's, against the primary record
rather than your summary. Cases written after reading each other converge prematurely on the loudest
argument.

**Make them check the record before filing.** The costliest single failure of the pass that produced
this section: three parties — both reviewers and the authoring session — independently concluded that
an obligation should *state the want and defer the mechanism*, which is verbatim what the pass had
ruled hours earlier, in a table row inside a comment none of them re-read. Brief every reviewer to
search the record for an item's identifier before filing anything about it. **A record that is written
but not consulted costs more than no record**, because everyone believes it is covering them.

**Anchor them to a stated commit, with every destination already committed.** Content routed out of
the specification — to a document, a ticket, a decision record — must have arrived there before the
review starts. Two reviewers on this pass each misread the repository once, in opposite directions,
because a concurrent documentation sweep was changing it underneath them. If other work must run in
parallel, give it a separate worktree.

**Then swap and force convergence into one document**, with every finding classified: **agreed**
(both now hold it), **contested** (both positions quoted verbatim, for the owner), **held by one
side** (the other does not dispute but will not endorse). One reviewer owns the file, the other signs
off or files disputes; it is not finished until both have signed.

**Two rules make it work.** Neither may characterise the other's position — quote it, because
paraphrase is how a finding gets softened into agreement. And **every withdrawal is recorded by name,
with the argument that moved it.** The withdrawals are the highest-density part of the document: on
the pass that produced this section, one reviewer withdrew fourteen findings and the other eight, and
a filed spread of 74 / 67 / 45 items reconciled to five open decisions.

**Give the owner the residue, not the debate.** A row a third party cannot decide without reading
both cases has not converged yet.

**Expect the pair to find things neither brief was aimed at.** Both are reading the corpus closely for
the first time, which is when unruled content, stale citations, and clause-level orphans surface —
and those outrank every count question in the document.

## The deliverable

Not a number. A set of requirements each stating one want, a decision log explaining every removal,
and a verified claim that no obligation was lost. If the count fell and the log is thin, the pass
was vandalism with good manners.
