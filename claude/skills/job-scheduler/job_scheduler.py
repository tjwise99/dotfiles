#!/usr/bin/env python3
"""job-scheduler: an agent's reference for what to run next, on which resource, in what order.

Usage:
  job_scheduler.py --adapter ADAPTER.py plan    [--now YYYY-MM-DDTHH:MM] [--json]
  job_scheduler.py --adapter ADAPTER.py status  [--now YYYY-MM-DDTHH:MM] [--json]

The adapter is a project's Python file with `problem(now) -> Problem`, built from the project's own files.
It may set `STATE_PATH` (where earliest planned ends are remembered, so a re-plan cannot hide a late job).

  plan    what runs now and until when; then the order: each job, the resources it takes, its start and end by simulation; "now" marks
          what can start at once; then the jobs that can never be placed and why
  status  LATE (an open job past its planned end), STALLED (a running job whose progress has not
          moved for 10 min), IDLE (a free resource with a ready job: start it); exit 1 when any

The order is greedy list scheduling, work-conserving. At each moment every ready job is offered the
resources in order: priority list first, then shortest first, then id. A job takes one resource from
each of its needs, all at once, and only when all of them are free. A free resource is never left
idle while a ready job could use it.
"""
import argparse
import datetime as dt
import importlib.util
import json
import os
import sys
from dataclasses import dataclass, field

STALL = dt.timedelta(minutes=10)
OVERRUN_STEP = dt.timedelta(minutes=1)


@dataclass
class Job:
    """A job. `needs` is a list of alternatives lists: one resource from each, held together.
    `state` is waiting, running or done. A running job names the resources it `holds`, its estimated
    end (`ends`), and when its own progress last moved (`last_progress`)."""
    id: str
    needs: list
    minutes: float
    after: list = field(default_factory=list)
    state: str = "waiting"
    planned_end: dt.datetime | None = None
    holds: list = field(default_factory=list)
    ends: dt.datetime | None = None
    last_progress: dt.datetime | None = None


@dataclass
class Problem:
    """`resources` maps each resource to when it is next available (None: free now, apart from running jobs)."""
    now: dt.datetime
    resources: dict
    jobs: list
    priority: list = field(default_factory=list)


@dataclass
class Assignment:
    job: str
    resources: list
    start: dt.datetime
    end: dt.datetime


@dataclass
class Schedule:
    next: list
    plan: list
    unplaceable: dict


def hm(when):
    return when.strftime("%H:%M") if when else "--:--"


def schedule(problem):
    """Greedy, work-conserving list scheduling by event simulation from `now`."""
    now = problem.now
    known = set(problem.resources)
    free_at = {r: max(now, until or now) for r, until in problem.resources.items()}
    finished = {}
    for job in problem.jobs:
        if job.state == "done":
            finished[job.id] = dt.datetime.min
        elif job.state == "running":
            end = job.ends if job.ends and job.ends > now else now + OVERRUN_STEP
            finished[job.id] = end
            for r in job.holds:
                if r in free_at:
                    free_at[r] = max(free_at[r], end)
    rank = {job_id: i for i, job_id in enumerate(problem.priority)}
    ids = {j.id for j in problem.jobs}
    unplaceable = {}
    pending = []
    for job in problem.jobs:
        if job.state != "waiting":
            continue
        missing = [alts for alts in job.needs if not set(alts) & known]
        unknown = [a for a in job.after if a not in ids]
        if missing:
            unplaceable[job.id] = f"needs one of {missing[0]}, which no resource provides"
        elif unknown:
            unplaceable[job.id] = f"follows {unknown[0]}, which is not in the plan"
        else:
            pending.append(job)
    pending.sort(key=lambda j: (rank.get(j.id, len(rank)), j.minutes, j.id))
    plan = []
    t = now
    while pending:
        placed = []
        for job in pending:
            if not all(a in finished and finished[a] <= t for a in job.after):
                continue
            chosen = []
            for alternatives in job.needs:
                pick = next((r for r in alternatives if r in free_at and free_at[r] <= t and r not in chosen), None)
                if pick is None:
                    break
                chosen.append(pick)
            else:
                end = t + dt.timedelta(minutes=job.minutes)
                for r in chosen:
                    free_at[r] = end
                finished[job.id] = end
                plan.append(Assignment(job.id, chosen, t, end))
                placed.append(job)
        pending = [j for j in pending if j not in placed]
        later = [x for x in list(free_at.values()) + list(finished.values()) if x > t]
        if not pending or not later:
            break
        t = min(later)
    for job in pending:
        unplaceable[job.id] = "never fits: it follows an unplaceable job or a cycle, or needs more resources at once than exist"
    return Schedule(next=[a for a in plan if a.start == now], plan=plan, unplaceable=unplaceable)


def status(problem, result, remembered):
    """(kind, text) per finding. `remembered` maps job id to the earliest planned end ever seen, and is updated."""
    now = problem.now
    found = []
    for job in problem.jobs:
        if job.state == "done":
            remembered.pop(job.id, None)
            continue
        if job.planned_end:
            seen = remembered.get(job.id)
            earliest = min(job.planned_end, dt.datetime.fromisoformat(seen)) if seen else job.planned_end
            remembered[job.id] = earliest.isoformat()
            if earliest < now:
                found.append(("LATE", f"{job.id}: planned end {hm(earliest)} has passed and it has not ended"))
        if job.state == "running" and job.last_progress and now - job.last_progress > STALL:
            found.append(("STALLED", f"{job.id}: no progress since {hm(job.last_progress)}"))
    for a in result.next:
        found.append(("IDLE", f"{'+'.join(a.resources)} free and {a.job} is ready: start it"))
    return found


def plan_json(result, problem=None):
    def row(a):
        return {"job": a.job, "resources": a.resources, "start": a.start.isoformat(timespec="minutes"), "end": a.end.isoformat(timespec="minutes")}
    running = [{"job": j.id, "resources": j.holds,
                "start": (j.ends - dt.timedelta(minutes=j.minutes)).isoformat(timespec="minutes") if j.ends else None,
                "end": j.ends.isoformat(timespec="minutes") if j.ends else None}
               for j in (problem.jobs if problem else []) if j.state == "running"]
    return {"running": running, "next": [row(a) for a in result.next], "plan": [row(a) for a in result.plan], "unplaceable": result.unplaceable}


def load_adapter(path):
    spec = importlib.util.spec_from_file_location("adapter", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(argv=None):
    parser = argparse.ArgumentParser(description="What to run next, on which resource, in what order.")
    parser.add_argument("--adapter", required=True, help="the project's adapter: a Python file with problem(now)")
    parser.add_argument("command", choices=("plan", "status"))
    parser.add_argument("--now", type=dt.datetime.fromisoformat, default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    adapter = load_adapter(args.adapter)
    now = args.now or dt.datetime.now().replace(second=0, microsecond=0)
    problem = adapter.problem(now)
    result = schedule(problem)
    if args.command == "plan":
        if args.json:
            print(json.dumps(plan_json(result, problem), indent=1))
        else:
            for job in problem.jobs:
                if job.state == "running" and job.holds:
                    print(f"running      {job.id:<20} on {'+'.join(job.holds)} until about {hm(job.ends)}")
            for a in result.plan:
                print(f"{hm(a.start)}-{hm(a.end)}  {a.job:<20} on {'+'.join(a.resources) or '(no resource)'}{'   <- now' if a.start == now else ''}")
            for job_id, why in result.unplaceable.items():
                print(f"never placed  {job_id}: {why}")
        return 0
    state_path = getattr(adapter, "STATE_PATH", None)
    remembered = {}
    if state_path and os.path.exists(state_path):
        with open(state_path) as f:
            remembered = json.load(f)
    found = status(problem, result, remembered)
    if state_path:
        with open(f"{state_path}.tmp", "w") as f:
            json.dump(remembered, f, indent=1)
        os.replace(f"{state_path}.tmp", state_path)
    if args.json:
        print(json.dumps([{"kind": k, "text": t} for k, t in found], indent=1))
    else:
        for kind, text in found:
            print(f"{kind:<8} {text}")
        if not found:
            print("clean")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
