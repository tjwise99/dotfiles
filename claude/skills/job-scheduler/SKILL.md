---
name: job-scheduler
description: >-
  An agent's reference for what to run next, on which resource, in what order, and which jobs are
  late or stalled. It is a small CLI over a pure scheduling algorithm: greedy, work-conserving list
  scheduling with dependencies, multi-resource jobs, alternative resources and a priority order. Each
  project supplies a one-function adapter that turns its own files into the scheduler's inputs.
  Invoke when an agent coordinates several jobs over shared boards, runners or locks; when a job ends
  or a decision changes the plan; when asked "what's next" or "what's idle"; or when adopting it in a
  new project.
---

# Job scheduler

`job_scheduler.py` answers two questions from a project's current state:

- **`plan`**: what is running now, and until when. Then the order that follows: each job, the
  resources it takes, and its start and end by simulation, with `<- now` on what can start at once.
  Last, the jobs that can never be placed, and why.
- **`status`**: `LATE` (an open job past its planned end), `STALLED` (a running job whose own
  progress has not moved for 10 min), and `IDLE` (a free resource with a ready job: start it). It
  exits 1 when it finds any, and prints `clean` and exits 0 when it finds none.

It is a reference that an agent runs. It is not a daemon. It starts nothing, arms no timer and
dispatches nothing. Acting on the answer is the agent's job.

## When to run it

- **When a job ends**: run `status`, then `plan`. The freed resource's next job is the `<- now` line.
- **After any decision that changes the plan** (a job added, cut, re-ordered or re-estimated): run
  `plan` before you tell anyone the new order.
- **Before you report progress or answer "what's next"**: run `status`. A `LATE` cannot be planned
  away. The earliest planned end it has seen is remembered in `STATE_PATH`.
- **Not on a clock.** Each run reads the project's files fresh. Nothing in between needs it.

```sh
python3 ~/.claude/skills/job-scheduler/job_scheduler.py --adapter <project>/adapter.py status
python3 ~/.claude/skills/job-scheduler/job_scheduler.py --adapter <project>/adapter.py plan [--json] [--now 2026-01-15T09:25]
```

## How it orders

- **Readiness.** A job is ready when every job in its `after` list is done, or its simulated end
  has passed.
- **Order.** At each moment, every ready job is offered resources in order: the priority list first
  (in its order), then shortest first, then by id.
- **Placement.** A job takes one resource from each of its `needs`, and all of them at once, only
  when all of them are free. "A board and the build lock" is two needs: `[["board-a", "board-b"],
  ["build"]]`.
- **Work-conserving.** A ready job that fits is always placed. A higher-priority job that cannot fit
  yet never holds a free resource back from one that can. The seeded cases prove this.
- **Running jobs.** A running job holds its resources until its estimated end. Once that end has
  passed, it holds them for one more minute on each run.

## Adopt it in a project

1. Copy `example_adapter.py` into the project, and change `problem(now)` to read the project's own
   files. It returns `job_scheduler.Problem(now, resources, jobs, priority)`:
   - **`resources`**: `{name: None | datetime}`. `None` means free now. A datetime is a hold, a
     maintenance window, or a resource held by something outside the plan.
   - **`jobs`**: `job_scheduler.Job(id, needs, minutes, after, state, planned_end, holds, ends,
     last_progress)`.
     - Take `state` from the job's **record** (its log, its result file, its runner's queue), not
       from what someone last wrote down.
     - Take `last_progress` from the job's **own output**: the newest write to its record, or its
       progress counter's last move.
   - **`priority`**: the job ids that go first, in order.
   - **`STATE_PATH`** (optional, module level): where earliest planned ends are remembered.
2. Write the project's special cases in the adapter, never in the core. Examples:
   - a test's log that goes quiet while the test is still working;
   - a build lock that `/proc/locks` cannot see;
   - a hold that stops counting once its cause has stopped running;
   - a record that names its job by a stamp in free text.
3. Give the adapter its own constructed cases. Build an on-disk copy of the project's layout, and for
   each special case write one case that must change the plan and one variant that must not.
   Seed-test them the way `seed.py` does for the core.
4. Run `status` and `plan` once on the project's real state, and read the output against what you
   know is running.

## Prove the core

```sh
cd ~/.claude/skills/job-scheduler
python3 -m unittest -v test_job_scheduler
python3 seed.py        # every case fails on a defective copy of the core; output as in seed-output.txt
```

The cases cover:
- dependencies respected;
- never placed on a resource the job cannot use;
- an alternative taken when it is free;
- a two-resource job waits for both;
- priority order kept, and shortest first after it;
- a free resource with an eligible ready job is never left idle;
- a running job keeps what it holds;
- LATE, including after a re-plan;
- STALLED, and a variant that is not;
- the status exit code and its output.

## Reporting into the status page

The `self-hosted-status-page` skill's rebuild runs `plan --json` and `status --json` when
`SCHEDULER_ADAPTER` names this project's adapter, and draws its Schedule gantt chart from them (its INPUTS.md,
`plan-out.json`). Both commands take `--json`; `status --json` prints the findings as `[{"kind","text"}]`
and still exits 1 when it finds any.

## What it is not

- **Not a watchdog.** Stop conditions, memory floors, reachability and process guards are
  monitoring, which is a separate concern. A project that wants them unattended runs its own timer
  beside this.
- **Not a dispatcher.** It never queues or starts a job.
- **Not an estimator.** `minutes` and `ends` come from the adapter. Correct a running job's `ends`
  from its own progress counter (e.g. ninja's `[n/N]`, taken over the last few minutes), not from
  the plan.
