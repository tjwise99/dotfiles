#!/usr/bin/env python3
"""Show each case failing on a defective copy of job_scheduler.py.

For each defect: copy the core, apply one textual mutation (it must match exactly once), run the named
cases against the copy (they must fail on an assertion, not an error) and against the real core (they
must pass). Exit 1 when any of that does not hold.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

DEFECTS = [
    ("dependencies ignored",
     "            if not all(a in finished and finished[a] <= t for a in job.after):\n                continue\n",
     "",
     ["Dependencies.test_a_job_starts_only_after_what_it_follows_ends"]),
    ("a done dependency still blocks",
     '        if job.state == "done":\n            finished[job.id] = dt.datetime.min\n',
     '        if job.state == "done":\n            pass\n',
     ["Dependencies.test_a_job_following_a_done_job_starts_now"]),
    ("any free resource will do",
     "                pick = next((r for r in alternatives if r in free_at and free_at[r] <= t and r not in chosen), None)",
     "                pick = next((r for r in free_at if free_at[r] <= t and r not in chosen), None)",
     ["Eligibility.test_never_placed_on_a_resource_it_cannot_use"]),
    ("only the first alternative is tried",
     "                pick = next((r for r in alternatives if r in free_at and free_at[r] <= t and r not in chosen), None)",
     "                pick = next((r for r in alternatives[:1] if r in free_at and free_at[r] <= t and r not in chosen), None)",
     ["Eligibility.test_an_alternative_resource_is_taken_when_free"]),
    ("an unknown resource is not reported",
     "        if missing:\n            unplaceable[job.id] = f\"needs one of {missing[0]}, which no resource provides\"\n        elif unknown:",
     "        if unknown:",
     ["Eligibility.test_a_resource_no_one_provides_is_reported"]),
    ("one free need is enough",
     "                if pick is None:\n                    break\n                chosen.append(pick)",
     "                if pick is None:\n                    continue\n                chosen.append(pick)",
     ["TwoResources.test_a_two_resource_job_waits_for_both"]),
    ("a second need is never met",
     "            for alternatives in job.needs:",
     "            for alternatives in job.needs + [[]]:",
     ["TwoResources.test_a_two_resource_job_with_both_free_starts_now"]),
    ("priority list ignored",
     "    pending.sort(key=lambda j: (rank.get(j.id, len(rank)), j.minutes, j.id))",
     "    pending.sort(key=lambda j: (j.minutes, j.id))",
     ["Priority.test_priority_list_goes_first"]),
    ("shortest first lost",
     "    pending.sort(key=lambda j: (rank.get(j.id, len(rank)), j.minutes, j.id))",
     "    pending.sort(key=lambda j: (rank.get(j.id, len(rank)), j.id))",
     ["Priority.test_shortest_first_without_a_priority"]),
    ("strict priority: the head job blocks the rest",
     "        for job in pending:\n            if not all(",
     "        for job in pending[:1]:\n            if not all(",
     ["WorkConserving.test_a_free_resource_with_an_eligible_ready_job_is_never_idle"]),
    ("a running job's resources offered to others",
     "            for r in job.holds:",
     "            for r in []:",
     ["WorkConserving.test_a_running_job_keeps_what_it_holds"]),
    ("late never raised",
     "            if earliest < now:",
     "            if earliest < now - dt.timedelta(days=1):",
     ["Late.test_open_job_past_its_planned_end_is_late"]),
    ("late from any planned end",
     "            if earliest < now:",
     "            if True:",
     ["Late.test_job_inside_its_window_is_not_late"]),
    ("a done job can be late",
     '        if job.state == "done":\n            remembered.pop(job.id, None)\n            continue\n',
     "",
     ["Late.test_done_job_is_not_late"]),
    ("a re-plan hides late",
     "            earliest = min(job.planned_end, dt.datetime.fromisoformat(seen)) if seen else job.planned_end",
     "            earliest = job.planned_end",
     ["Late.test_moving_the_planned_end_does_not_hide_late"]),
    ("stall never raised",
     '        if job.state == "running" and job.last_progress and now - job.last_progress > STALL:',
     '        if job.state == "waiting" and job.last_progress and now - job.last_progress > STALL:',
     ["Stalled.test_running_job_quiet_for_eleven_minutes_is_stalled"]),
    ("stall with no window",
     '        if job.state == "running" and job.last_progress and now - job.last_progress > STALL:',
     '        if job.state == "running" and job.last_progress:',
     ["Stalled.test_running_job_quiet_for_three_minutes_is_not_stalled"]),
    ("idle capacity not reported",
     "    for a in result.next:\n        found.append(",
     "    for a in []:\n        found.append(",
     ["AlertPath.test_a_free_resource_with_a_ready_job_is_reported_and_exits_1"]),
    ("status exits 0 on findings",
     "    return 1 if found else 0",
     "    return 0",
     ["AlertPath.test_a_free_resource_with_a_ready_job_is_reported_and_exits_1"]),
    ("clean state not said",
     '        if not found:\n            print("clean")',
     '        if not found:\n            print("")',
     ["AlertPath.test_nothing_to_report_is_clean_and_exits_0"]),
]


def run_cases(core_dir, cases):
    env = dict(os.environ, CORE_DIR=str(core_dir), PYTHONPATH=str(core_dir), PYTHONDONTWRITEBYTECODE="1")
    done = subprocess.run([sys.executable, "-m", "unittest", *[f"test_job_scheduler.{c}" for c in cases]],
                          cwd=HERE, env=env, capture_output=True, text=True)
    if done.returncode == 0:
        return "passes"
    return "FAILS" if "failures=" in done.stderr and "errors=" not in done.stderr else "ERRORS"


def main():
    source = (HERE / "job_scheduler.py").read_text()
    bad = 0
    print(f"{'defect':<48} {'seed':<7} {'defective':<10} real")
    for name, old, new, cases in DEFECTS:
        landed = source.count(old) == 1 and source.replace(old, new) != source
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "job_scheduler.py").write_text(source.replace(old, new))
            on_defect = run_cases(tmp, cases) if landed else "not run"
        on_real = run_cases(HERE, cases)
        ok = landed and on_defect == "FAILS" and on_real == "passes"
        bad += not ok
        print(f"{name:<48} {'landed' if landed else 'MISSED':<7} {on_defect:<10} {on_real}  {', '.join(cases)}")
    print("all seeds landed; every case fails on its defect and passes on the real core" if not bad else f"{bad} seed(s) not shown")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
