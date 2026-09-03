---
description: Front-load discovery for a ticket or task — fan out read-only recon, surface the real surface area and every open decision, and stop for human answers before any plan or code.
argument-hint: <issue-number | task description>
---

# Discover

Input: **`$ARGUMENTS`** — an issue number, or a task in prose.

Move discovery *before* planning, so unknowns surface now — while they are cheap — instead of
mid-implementation, where they get resolved by guessing or by inventing scope no one asked for. This
command ends by handing decisions **up to the human**. It does not plan, branch, or write code.

**Runs in orchestrator mode** — `/discover` turns it on automatically. Recon is delegated so the
orchestrating context stays lean; the gate enforces it. Your job is to slice the work, brief the
agents, and synthesize what returns — not to open files yourself.

## 1. Frame the surface

Read the ticket to frame the work — `gh issue view $ARGUMENTS` is a thin, allowed call; a prose task
needs no pull. Everything past the ticket text — opening files, tracing callers — is a subagent's job.

**Verify the premise before anything else — this is the first slice, and it can end the ticket.** A
ticket asserts a problem: a bug that misbehaves, a gap that is missing, a need that is unmet. Before
tracing how to fix it, confirm the problem is *real against today's tree* — reproduce the asserted
defect, find the missing thing actually absent, confirm the need is not already met by code that landed
since the ticket was filed. **That a new check would fire is not evidence the check was needed.** If the
premise does not hold, the ticket is done here (§4) — do not plan, do not build. This is the slice that
keeps an evening from being spent building something the tree already handles.

Cut what else must be understood into independent slices. Typical slices, adapted to the task rather
than run by rote:

- **The premise** — reproduce the problem the ticket asserts against the current tree; report whether
  it holds, and if not, what already handles it. Everything below matters only if this one passes.
- **The change site** — the code the task edits, and how it works today.
- **Callers and dependents** — what relies on what will change; the blast radius.
- **Patterns to match** — how the codebase already solves this shape, so the plan conforms instead of
  inventing a new one.
- **Contracts and tests** — the boundaries the change must honour, and what proves them.
- **Prior decisions** — any ADR, spec, or requirement that already decides part of this. Find the
  document that already decides it before treating anything as open.

## 2. Fan out read-only recon

Spawn one agent per slice, and **choose the agent whose expertise fits the slice — do not default to
a generic searcher.** Match the whole roster to the work: a requirements or spec slice to the
requirements engineer, a test-strategy slice to the testing architect, a backend or frontend surface
to the matching architect, a live-system question to the operator that knows it, a pure file-or-name
search to a search agent, open-ended reasoning to a general one. A custom agent that knows the domain
surfaces what a generic search walks past. When several fit, prefer the most specific.

Brief each with the task, its slice, and the output contract:

- **Write findings to the deliverable file it is assigned.** A hook hands each subagent a path under
  `~/.claude/deliverables/…` and will not let it finish until that file is non-empty; its chat reply stays
  ≤10 lines pointing at it. Brief it on *what* to capture — findings plus open questions. Fat chat
  returns re-pollute the context this delegation exists to protect.
- **Read-only. Change nothing.**
- **Surface ambiguity; do not resolve it.** Anything the ticket leaves open, any place the codebase
  offers two patterns, any missing spec — report it as an open question, never pick.

Run them in parallel — one-shot subagents, each writes its deliverable and stops (that is what the
deliverable hook enforces). You *can* instead drive this with agent-team teammates that message you
the moment a slice raises a decision; note teammates coordinate by message, not the deliverable file,
and are not deliverable-enforced — see the README's orchestrator-mode section.

## 3. Synthesize

Work from what the agents returned — each ≤10-line reply states its verdict and decisions. `grep` or
`head` a deliverable under `~/.claude/deliverables/…` only to pull a specific detail a reply did not
carry; **never full-`Read` a deliverable** — that re-ingests every agent's payload into the
orchestrator and is the largest single source of context accretion. If synthesis genuinely needs
several deliverables' full content at once, delegate that synthesis too. Collect the result into two
artifacts:

- **A surface map** — what this work actually touches, its blast radius, the patterns it must match.
- **An open-decisions list** — every ambiguity, missing spec, scope boundary, or fork discovery
  turned up, each framed as a decision *you* cannot make for the human: the options and the tradeoff,
  not a recommendation dressed as a finding.

Dedup across agents — a decision two slices raise is one decision.

## 4. Escalate, then stop

**If the premise slice came back failed — the problem is not reproducible, or the tree already handles
it — that is the headline, not a footnote.** Bring it to the human first, as its own call: the ticket
appears unnecessary because *X*, so the options are close it, rescope it, or (if you believe the premise
still holds) show why. Do not plan, do not branch — a premise that does not hold ends the ticket here,
and confirming that with the human is the whole return of this run.

Otherwise, bring the open-decisions list **to the human** and stop. Do not plan, do not branch, do not
write code. State the rule every downstream step inherits, because it is the one this command exists to
enforce:

**Anything not settled by an answered decision is escalated, never invented.**

The deliverable is the surface map plus the answered decisions — the brief a planning pass consumes.
