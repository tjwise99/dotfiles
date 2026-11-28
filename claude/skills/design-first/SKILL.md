---
name: design-first
description: >-
  Design before any ticket or code. Invoke whenever a request changes how something is shaped —
  take stock and condense, consolidate duplicates, clean up, simplify, restructure, reorganise,
  redesign, or add a subsystem or tool — and whenever a ticket asks for a structure nobody has
  designed yet. An architect designs the target from a stock-take; independent reads check it for
  holes and overbuild; the human reviews it as C4 Before/After views in a tabbed page and rules on
  each open decision; only then is the ticket written from the approved design and handed to
  /work-ticket. Not for a ticket whose design is already settled — that goes to /work-ticket.
---

# Design first

Input: the request, in the human's words, or the issue that carries it.

**Design comes before the ticket, and the ticket comes before code.** A request to change how a system
is shaped — take stock and condense it, consolidate duplicates, restructure, simplify, add a subsystem
— is design work from its first message. Its output is an approved target design. A ticket is written
*from* that design; it never substitutes for one. A ticket that lists cuts and fixes without a target
shape leaves every structural question to be invented mid-build, and each one invented there has to be
reversed later.

Recon, design and review are delegated; the main thread briefs, relays and keeps the human's
decisions. It writes no design itself.

## 1. Take stock

Fan out read-only recon (one agent per slice, the agent whose expertise fits) for the **inventory the
architect needs**: what exists, who calls what, where things duplicate or conflict, which documents
already decide something, and what each piece costs. This is input to the design, not a deliverable to
the human — no findings dump, no question list. Each recon agent writes its findings to a file.

## 2. The architect designs

Spawn the architect whose domain fits (`software-architect` by default; a more specific architect when
one fits), on `opus`. Its brief is **the inputs and the question, never the lead's plan**:

- the request in the human's own words, the recon files, the current tree, and the documents that
  already decide anything;
- every ruling the human has made, marked as a fixed constraint;
- the question: *what should this become?*

The brief also carries these instructions, every time:

- **Do not take the current shape as given.** The number of files, the layout of a directory, the set
  of entry points — justify every structural element or remove it.
- **Every structural choice records the alternatives it rejected and why.**
- **Escalate, never invent.** Any fork the inputs do not settle — scope, anything irreversible, a
  capability someone uses — is listed for the human with its options and a lean. The architect does
  not decide it.

The architect writes the design to a file:

- C4 views as Mermaid C4 blocks (`C4Context`, `C4Container`, `C4Component`), each in a **Before**
  version (today) and an **After** version (the target): the L1 context, the L2 containers, and one
  L3 component view per container whose design changes;
- the structural choices with their rejected alternatives;
- the full inventory after the change: every entry point and every file, each with its one-line job;
- the open decisions.

### The owner's design preferences — the architect designs to these

- **Simplicity and clarity for a human come first.** A person must be able to hold the whole shape in
  their head. When two designs both work, the one with fewer things in it wins.
- **The first question about any piece is "can it be deleted?"**, before "what is wrong with it?".
- **Deletion beats relocation.** Never turn one thing into two: no wrapper around a single call, no
  new file for a body that has one caller, no second home for a fact.
- **A thing lives beside what it serves.** A helper that is useless without one component sits with
  that component, not in a shared grab-bag directory.
- **No brittle command-parsing scripts.** No check, guard or tool that parses shell, recipes or config
  with regex or awk. A one-line `git grep` is the ceiling. Prefer a structure that makes the defect
  impossible over a guard that looks for it.
- **Entry points are readable at a glance.** A task-runner recipe is its name, a one-line doc, and a
  short plain body that calls one tool. Logic lives in the tool, not in the recipe file. No comment
  blocks in recipe files.
- **CI is the gate; local hooks stay fast.** A pre-commit hook runs only what must stop a commit
  leaving the machine (secrets, identity) and finishes in about a second. Everything else runs in CI,
  one named step per check, every step running after any failure.
- **Tests live in the test tree.** No tests outside it, and no wrapper that exists only to run them.
- **Trade-study a tool before building it.** Survey what existing tools and the platform already cover.
  Build only what none fits, and say why.
- **Generality nobody needs is not built.** Build the smallest thing that does the job end to end.

## 3. Independent reads

Before the human sees the design, two reviewers read it **cold**, each spawned with only its mandate
file and the inputs. Use the plan mandates, with the design in the `plan:` slot and the recon files in
the `discovery:` slot:

- `~/.claude/reviews/plan-completeness.md` — what does the design leave undecided that the build would
  have to invent?
- `~/.claude/reviews/plan-overbuild.md` — what does the design contain that the request does not need?

They cross-examine each other's findings. The architect answers every finding or adds it to the open
decisions. Nothing reaches the human while a hole or a cut is unanswered.

## 4. The human reviews it as a page

The design goes to the human as **an artifact page, never as prose in the conversation**:

- **real C4**: L1 context, L2 containers, L3 components, drawn with Mermaid's C4 notation (Person,
  System, Container, Component, boundaries, relationships) — not flowcharts labelled as C4;
- **a Before/After toggle that switches every view** between today and the target, with headline
  counts that flip with it (entry points, files, lines);
- **one tab per view or concern**, and a final tab with the open decisions;
- the inventory tables are designed, not dumped: each row is a name, its job, and its verdict.

A `ui-designer` pass sets the page's visual hierarchy before it is published. The page is the design
record; the conversation only points at it.

Then **walk the open decisions conversationally**, one at a time, in the human's order. For each, give
honest pros and cons in prose, not an option menu, and a lean, and let the human call it. A minor fork
(naming, where a helper lives, a wording) is ruled by the matching engineering agent and recorded,
not handed up. Scope, anything irreversible, and changing a bound the tree already sets go to the
human. Each answer goes back into the page, and the page is republished.

## 5. Write the ticket from the approved design

Once every open decision is answered and the human approves the design:

- write the ticket (or rewrite an existing one) **from the design**: the target shape, the inventory
  after, and the rulings. A choice that took a real trade study becomes an ADR in the repo that owns it;
- link the design page from the ticket;
- hand off to **`/work-ticket <n>`**. Its discovery verifies the premise against the approved design;
  it does not reopen the design.

**Do not branch, commit or build anything before the design is approved.** A design question that
surfaces mid-build means this step was skipped. Stop the build and come back here.
