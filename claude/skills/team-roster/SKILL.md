---
name: team-roster
description: >-
  Read a Claude Code agent team's state from disk without waking any agent: who is working, idle,
  stopped or silent mid-turn; who was messaged after being closed, and by whom; which standing roles
  have a stale handover; which stopped agents left no retro; which idle task agents to close; and the
  tokens and context size of each agent. Prints proposals for the lead to act on and sends nothing.
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
- **`CLOSE?`**: a task agent (not in `standing`, not in `hold_open`) has been idle for
  `close_after_minutes`. The proposal says whether to ask for its retro first.
- **`HANDOVER`**: a standing role has no handover on disk, or its handover is older than
  `handover_stale_minutes`.
- **`SILENT`**: as the state above.
- **`REFRESH?`**: a standing role's context (`ctx k`) is at or over `refresh_context_k`. Propose a
  fresh one after it brings its handover current. Off unless the key is set.

`roster` also prints each agent's total tokens and `ctx k`: the prompt size of its newest model call,
which is how full its context is. A standing role with a large `ctx` is the one to refresh first.

## What it cannot tell you

These are not on disk; only an agent (or the person) can say them.

- **Whether a task is finished.** The transcript shows that an agent went idle, not whether its task
  is done. `CLOSE?` is a proposal; the lead confirms before closing.
- **Whether a `stopped` in-process teammate's runtime has ended.** In-process teammates share the
  lead's process, so there is no per-agent process to check. A `TaskStop` with no later write is the
  only record.
- **What an agent is waiting on, or what it intends next.** That is in its context, not on disk.
- **Who is "on the roster" by the team's own rules.** The script lists every agent that ever ran in
  the lead's sessions. Which ones the team still counts is a project decision: say it with
  `standing`, `hold_open` and `ignore`.

## Config (one JSON file per session; keep it with the session, never in this skill)

| Key | Meaning |
|---|---|
| `team` | the `teamName` in the teammates' `.meta.json` |
| `projects_dir` | the Claude Code projects directory for the repo |
| `lead_transcripts` | the lead's session `.jsonl` files; their basenames are the sessions read |
| `lead_name` | the name the lead's own messages carry (default `team-lead`) |
| `docs_dir`, `handover`, `retro` | where handovers and retros live, and their names (`{name}` is replaced) |
| `handover_aliases`, `retro_aliases` | `{agent: name used in the doc file}` when the two differ |
| `standing` | roles that live across tasks: refreshed, never proposed for close |
| `hold_open` | task agents kept open on purpose (a later task is already theirs) |
| `ignore` | names never reported (the lead) |
| `idle_minutes`, `close_after_minutes`, `handover_stale_minutes` | thresholds (defaults 10, 30, 120) |
| `refresh_context_k` | context size, in thousands of tokens, at which a standing role is proposed for refresh (off if absent) |

## When to run it

On an event, never on a clock: a teammate's message, a job ending, before a shift change or a close,
and before messaging an agent you are not sure is open. A script on a timer may run `check` and
raise its output to the lead; no agent should be woken just to run it.

## Prove it

`test_team_roster.py` builds a team on disk for each finding: one case that must raise it and one valid
variant that must not. Run `python3 -m unittest test_team_roster` in this directory. Each check was
also seeded (the defect put in the code, the suite seen failing) before it was trusted.
