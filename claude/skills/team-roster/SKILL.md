---
name: team-roster
description: >-
  Read a Claude Code agent team's state from disk without waking any agent: who is working, idle,
  stopped or silent mid-turn; who was messaged after being closed, and by whom; which stopped agents
  left no retro; which idle agents to close; which agents are too old or too full to keep and should
  be replaced by a fresh one; and the tokens and context size of each agent. Prints proposals for the lead to act on and sends nothing.
  Invoke when coordinating a team of teammates, before any shift change or close, before messaging an
  agent you are not sure is open, and when reporting what a team cost.
---

# Team roster

`team_roster.py` reads three things Claude Code keeps on disk, and nothing else:

1. **Teammate transcripts.** `<projects_dir>/<lead session>/subagents/agent-*.jsonl`, each with a
   `.meta.json` that carries the teammate's `name`, `teamName` and `model`. A teammate respawned under
   the same name gets a new transcript; the newest one is its current life.
2. **The lead's transcripts.** The lead's `TaskStop` calls (when each teammate was closed), its
   `Agent` calls (spawns) and its `SendMessage` calls.
3. **The project's docs directory.** Whether `handover-<name>.md` and `retro-<name>.md` (or the
   patterns you give) exist, and when each handover was last written.

Every agent is a task agent: one agent per task, closed when the task ends, replaced by a fresh one
when it has run too long. No config key exempts an agent from a proposal, and no threshold can be
raised past its ceiling.

```sh
python3 ~/.claude/skills/team-roster/team_roster.py --config <session>/team.json roster  # one row per agent
python3 ~/.claude/skills/team-roster/team_roster.py --config <session>/team.json check   # findings; exit 1 if any
python3 ~/.claude/skills/team-roster/team_roster.py --config <session>/team.json cost    # tokens per agent
```

## What each state and finding means

- **States** (`roster`): `working` (its turn is open and it wrote within `idle_minutes`), `idle` (its
  last model turn ended without a tool call: it is waiting for a message), `stopped` (the lead closed
  it; a message sent after that resumes it for one turn, which `WOKEN` reports, and it stays closed),
  `silent mid-turn` (its turn is open but nothing was written for
  `idle_minutes`: hung, or stopped with no `TaskStop` on record).
- **`WOKEN`**: a message was *sent* to an agent after the lead closed it, and the agent received it.
  It names the sender and the time. A message sent before the close and delivered after is not
  counted. A woken agent rereads its whole context, so each one is a cost someone should not have paid.
- **`NO-RETRO`**: a stopped agent left no retro on disk.
- **`CLOSE?`**: an agent has been idle for `close_after_minutes`. The proposal says whether to ask
  for its retro first.
- **`SILENT`**: as the state above.
- **`REFRESH?`**: an agent that is not stopped has a context (`ctx k`) at or over
  `refresh_context_k`, or its current life began `refresh_age_minutes` or more ago. Propose a fresh
  one in its place. The proposal names its handover and when it was written, or says there is none
  to ask for; how current the handover is, the lead judges.

`roster` also prints each agent's total tokens and `ctx k`: the prompt size of its newest model call,
which is how full its context is.

## Ceilings

Each threshold's default is its ceiling. A config may set a lower value; a higher one is clamped to
the ceiling with a warning on stderr, so a large number cannot mute a proposal.

| Threshold | Ceiling | Why |
|---|---|---|
| `idle_minutes` | 10 | an open turn with no write for longer than this is reported `silent mid-turn`, not `working` |
| `close_after_minutes` | 30 | an idle agent whose task is done costs a context reread on every message; half an hour is enough for the lead to send the next step of the same task |
| `refresh_context_k` | 250 | a fresh teammate starts near 70k (system prompt, instructions, memory); 250k leaves about 180k for one task, and single-task agents measured on one team finished under 300k |
| `refresh_age_minutes` | 120 | single-task agents measured on one team mostly finished within 90 min; past two hours an agent is carrying more than one task |

## What it cannot tell you

These are not on disk; only an agent (or the person) can say them.

- **Whether a task is finished.** The transcript shows that an agent went idle, not whether its task
  is done. `CLOSE?` is a proposal; the lead confirms before closing.
- **Whether a `stopped` in-process teammate's runtime has ended.** In-process teammates share the
  lead's process, so there is no per-agent process to check. A `TaskStop` with no later write is the
  only record.
- **What an agent is waiting on, or what it intends next.** That is in its context, not on disk.
- **Who is "on the roster" by the team's own rules.** The script lists every agent that ever ran in
  the lead's sessions.

## Config (one JSON file per session; keep it with the session, never in this skill)

| Key | Meaning |
|---|---|
| `team` | the `teamName` in the teammates' `.meta.json` |
| `projects_dir` | the Claude Code projects directory for the repo |
| `lead_transcripts` | the lead's session `.jsonl` files; their basenames are the sessions read |
| `lead_name` | the name the lead's own messages carry (default `team-lead`) |
| `docs_dir`, `handover`, `retro` | where handovers and retros live, and their names (`{name}` is replaced) |
| `handover_aliases`, `retro_aliases` | `{agent: name used in the doc file}` when the two differ |
| `idle_minutes`, `close_after_minutes`, `refresh_context_k`, `refresh_age_minutes` | thresholds, each a positive number no higher than its ceiling (see Ceilings) |

`standing`, `hold_open`, `ignore` and `handover_stale_minutes` were removed. A config that still
carries one is refused with exit 2, naming the key: ignoring it would leave its author believing an
agent is exempt.

## When to run it

On an event, never on a clock: a teammate's message, a job ending, before a shift change or a close,
and before messaging an agent you are not sure is open. A script on a timer may run `check` and
raise its output to the lead; no agent should be woken just to run it.

## Prove it

`test_team_roster.py` builds a team on disk for each finding: one case that must raise it and one valid
variant that must not. Run `python3 -m unittest test_team_roster` in this directory. Each check was
also seeded (the defect put in the code, the suite seen failing) before it was trusted.
