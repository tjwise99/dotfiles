# Agents

Curated subagent definitions for solo software work with an AI agent. The working method these
support is documented in [`~/PROJECT_PLAYBOOK.md`](../../PROJECT_PLAYBOOK.md).

Originally seeded from the *Contains Studio* agent pack. That pack was written for a multi-person
studio running six-day product sprints — most of it did not apply, and the surplus was noise in the
selection space. What remains has been kept deliberately; the rest is in `~/.claude/agents-archive/`
(moved, not deleted — restore with `mv`).

**The archive is per-host and outside version control**, so it differs between machines and nothing
here describes it. `gnc-engineer` — guidance, navigation and control — lives there rather than in the
table below; restoring it means copying it into `claude/agents/engineering/` and adding its row,
which `tools/check-manifest.py` then enforces in both directions.

## Current agents

### engineering/

| Agent | Model | Use for |
|---|---|---|
| **independent-reviewer** | opus | Adversarial review of a diff against its specification, in a context that did not write it. Reports findings; **no edit tools by design** |
| **code-monkey** | sonnet | Implementing a settled specification **without making design decisions** — halts and asks when the spec is ambiguous rather than inventing plausibly |
| **software-architect** | opus | Turning vague requirements into concrete architecture and decision records |
| **systems-requirements-engineer** | opus | Translating problem descriptions into testable requirements; auditing requirement sets for gaps and conflicts |
| **backend-architect** | inherit | Server-side structure for small self-hosted services: API shape, boundaries, config and secret handling |
| **frontend-developer** | inherit | Svelte-first UI implementation, component structure, layout for long-running displays |
| **devops-automator** | inherit | CI gates, container builds, publishing, repo scaffolding for solo container deployments |
| **testing-architect** | inherit | Verification strategy: tier structure, what each tier guarantees, requirement-to-test traceability. Designs the map; does not write the tests |
| **test-writer-fixer** | inherit | Tests that encode requirements; suite repair. Does not chase coverage |
| **technical-documentation-writer** | sonnet | User-facing documentation: structure, guides, references, diagrams |
| **frontend-architect** | inherit | Client-side structure: component boundaries, the boundary schema the UI consumes, state and data flow, render and failure behaviour |

### operations/

| Agent | Model | Use for |
|---|---|---|
| **remote-system-operator** | inherit | Changing or diagnosing a live system that is expensive to reach — appliances, embedded boards, headless hosts. Classifies changes by recoverability, guards the lifeline, measures the device rather than the release notes |

### design/

| Agent | Model | Use for |
|---|---|---|
| **ui-designer** | — | Interface and component design, visual structure |

### management/

| Agent | Model | Use for |
|---|---|---|
| **project-manager** | inherit | GitHub project management via `gh` — issues, labels, milestones, Projects boards, PR/review workflow. Does the work and explains it; assumes git fluency but no GitHub project-layer knowledge |

### learning/

| Agent | Model | Use for |
|---|---|---|
| **codebase-tutor** | inherit | Teaching an inherited codebase or toolchain using that tree as the worked example — lessons sequenced from what the repository contains, artifact shown before it is explained, checkins answerable from what has been taught |

## When to use the reviewer

`independent-reviewer` exists because **independence is a property of context, not instruction** — an
agent cannot review its own work by being told to be critical. The mode is chosen by *who wrote the
code*: a context that had no part in writing it reviews inline, while a context reviewing its own
work must delegate.

**`~/.claude/commands/pr-ready.md` holds the authoritative table** — it is the executable copy, and
this paragraph is a description of it, not a second source. If the rule changes, change it there.

## The two structural agents

`independent-reviewer` and `code-monkey` attack the same problem from opposite ends, and are the two
worth understanding as a pair.

The problem: an agent that generates plausible structure faster than a human can audit it. Where does
unauditable structure come from? **Decisions the agent made that nobody specified and nobody
reviewed.**

- **`code-monkey` prevents it at the input.** It refuses to decide anything observable outside the
  code it is writing — interface names, payload shapes, failure behaviour, thresholds, new files.
  Ambiguity becomes a halt and a question, not a plausible invention. It is also a **spec quality
  test**: frequent halts mean the specification was incomplete, which a helpful agent otherwise hides
  by filling gaps well.
- **`independent-reviewer` catches it at the output.** Fresh context, reviews against the spec, has no
  edit tools so it cannot become a second author.

Use `code-monkey` when the design is settled. Do *not* use it for exploration or debugging with an
unknown cause — it will halt immediately, and correctly.

## Conventions

- **Model assignment is mostly unnecessary.** Subagents inherit the parent model, which is usually
  right. It earns its keep in two cases only: **pinning up** (`independent-reviewer` should stay
  strong even when you are running something cheap) and **pinning down** (`code-monkey` does
  mechanical work and should not cost architecture rates). Everything advisory wants the good model
  anyway — leave it inherited.
- **Keep descriptions short.** Every agent's `description` sits in context whenever delegation is
  considered. A short `<example>` block or two is a legitimate selection aid; several fabricated
  multi-turn dialogues are not, and the borrowed pack ran 1,400–3,400 characters each.
- **Scope tools to the role**, for agents whose role forbids authorship. `independent-reviewer` has no
  editing tools. Note the limit of this: **Bash can write**, so where an agent needs Bash for
  inspection the restriction is stated in its prompt as well, and is only as strong as the agent's
  compliance. Advisory agents that legitimately produce documents (`software-architect`,
  `technical-documentation-writer`, `systems-requirements-engineer`) are unscoped deliberately.
- **Several agents are shaped by one project.** `frontend-developer` (Svelte, unattended displays),
  `backend-architect` (small self-hosted services), and `devops-automator` (single-host containers)
  encode one project's context. Their descriptions declare that scope, so selection stays honest —
  but re-tune them rather than treating their content as universal engineering advice.
- **Architect/doer pairs split design from implementation.** `frontend-architect`↔`frontend-developer`
  and `testing-architect`↔`test-writer-fixer` are the same division: the architect decides the
  structure and hands the doer a settled map to fill in. Reach for the architect when the question is
  *how should this be shaped*, the doer when the shape is already decided.
- **Parallel implementers need isolated worktrees.** Agents sharing one working tree collide.
- **Tune before adding.** A borrowed agent matching your real work is worth editing; a new one
  duplicating an existing role is worth skipping.

## Related

- `~/.claude/commands/` — `pr-ready` (merge-readiness checklist) and `work-ticket` (ticket → plan →
  implementation → pr-ready)
- `~/.claude/skills/` — `repo-health` (security and best-practices audit)
- `~/PROJECT_PLAYBOOK.md` — the method all of the above serves
