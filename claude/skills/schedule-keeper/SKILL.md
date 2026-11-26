---
name: schedule-keeper
description: >-
  Keep a session's schedule.json (the self-hosted-status-page format) true to its job records with no
  agent in the loop: `sync` applies START/END lines that the job runners append to an events file, so a
  record's start and end reach the schedule the minute they land; `check` finds what the page or an
  owner would trip on (outcome words outside the vocabulary, an owner priority with no open job and no
  reason, an idle hold with no cause or one that overlaps an open job, an event naming no job).
  Invoke when setting up a long multi-job session, when a schedule keeps going stale because an agent
  has to remember to write it, or before reporting the schedule to anyone.
---

# Schedule keeper

Two commands over one `schedule.json` in the format the self-hosted-status-page skill's `INPUTS.md`
defines. The scheduling algorithm (what runs next, what is late or stalled) is the job-scheduler
skill's; this skill never orders jobs.

```sh
python3 ~/.claude/skills/schedule-keeper/schedule_keeper.py --schedule S --events E sync
python3 ~/.claude/skills/schedule-keeper/schedule_keeper.py --schedule S [--events E] check
```

## The events contract

Whatever runs a job (a chain script, a runner hook) appends one line per event to the events file:

```
HH:MM:SS START <job-id> [record=<id>]
HH:MM:SS END <job-id> <result> [record=<id>] [why=<text to the end of the line>]
```

- `<job-id>` is the schedule's job `id`, exactly. `check` reports an event whose id names no job, so a
  typo is seen, not silently dropped.
- `<result>` is one of the page's words: passed, failed, failed as designed, void, stopped, not
  proven, dropped, cut. `failed` and `stopped` close the job as `failed`, `dropped` and `cut` as `cut`,
  and every other word as `done`. The detail goes in `why`.
- Any other line is ignored, so the same file can carry free text for people.

## What `sync` does, and does not

- It changes only an **open** job (waiting or running). A job someone closed by hand keeps that
  person's outcome, and replaying the whole file changes nothing. A second START for a running job
  keeps the first start time.
- It writes atomically (a temporary file, then a rename) and only when something changed.
- It does not run on a clock. Trigger it on the events file changing: a systemd `.path` unit with
  `PathModified=` on the events file and a oneshot service that runs `sync`, under `flock` on a lock
  beside the schedule when anything else writes it too.

## Checks (`check`, exit 1 on any)

| Finding | Fires when | A valid variant that does not fire |
|---|---|---|
| `VOCAB` | a job's `outcome.result` is not a page word (the page draws it as an unknown state) | the word in `result`, the detail in `why` |
| `PRIORITY` | an `owner_priorities` entry is not done, none of its `jobs` is open, and it has no `no_job_reason` | an open job listed, or a reason given |
| `HOLD` | an `idle_reasons` hold has no `cause`, or a cause that names neither a job nor a ruling in `rulings_cited` | a cause naming the blocking job, or a ruling |
| `HOLD` | a hold overlaps an open job's planned window on the same resource (`uses`, else the lane) | windows that touch end to start |
| `EVENT` | an events line names a job id not in the schedule | the exact id |
| `IDLE` | between now and `final_start`, a resource has a gap of `--gap` minutes (default 10) with no open job and no hold | a job placed, or a hold with its cause |

Holds and jobs carry a `day`; a window whose end is before its start runs past midnight. The
resources checked for `IDLE` are the schedule's `resources` keys, else every name in the jobs'
`uses`; declare `resources` so lanes that are not machines are not reported. A running job past its
planned end still holds its resource. `--now` and `--today` fix the clock for tests.

## Prove it

`test_schedule_keeper.py` has one case per behaviour above and its valid variant. Each check was seeded
(the defect put in the code, the suite seen failing) before it was trusted. Run
`python3 -m unittest test_schedule_keeper` in this directory.
