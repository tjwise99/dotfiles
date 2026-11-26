"""Constructed cases for job_scheduler.py: each property has a case that must hold and a variant that must not trip it.

Run: python3 -m unittest -v test_job_scheduler   (CORE_DIR selects the job_scheduler.py under test; seed.py uses it)
"""
import contextlib
import datetime as dt
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, os.environ.get("CORE_DIR", str(Path(__file__).resolve().parent)))
import job_scheduler as js  # noqa: E402

NOW = dt.datetime(2026, 1, 15, 2, 0)
RESOURCES = ("board-a", "board-b", "build")


def at(minutes):
    return NOW + dt.timedelta(minutes=minutes)


def problem(*jobs, busy=None, priority=()):
    resources = {r: None for r in RESOURCES}
    resources.update({r: at(m) for r, m in (busy or {}).items()})
    return js.Problem(now=NOW, resources=resources, jobs=list(jobs), priority=list(priority))


def placed(result, job_id):
    return next((a for a in result.plan if a.job == job_id), None)


def now_ids(result):
    return [a.job for a in result.next]


class Dependencies(unittest.TestCase):
    def test_a_job_starts_only_after_what_it_follows_ends(self):
        result = js.schedule(problem(js.Job("A", [["build"]], 30), js.Job("B", [["board-a"]], 10, after=["A"])))
        self.assertNotIn("B", now_ids(result))
        self.assertEqual(placed(result, "B").start, placed(result, "A").end)

    def test_a_job_following_a_done_job_starts_now(self):
        result = js.schedule(problem(js.Job("A", [["build"]], 30, state="done"), js.Job("B", [["board-a"]], 10, after=["A"])))
        self.assertIn("B", now_ids(result))


class Eligibility(unittest.TestCase):
    def test_never_placed_on_a_resource_it_cannot_use(self):
        result = js.schedule(problem(js.Job("J", [["board-b"]], 10), busy={"board-b": 20}))
        self.assertNotIn("J", now_ids(result))
        self.assertEqual((placed(result, "J").resources, placed(result, "J").start), (["board-b"], at(20)))

    def test_an_alternative_resource_is_taken_when_free(self):
        result = js.schedule(problem(js.Job("J", [["board-a", "board-b"]], 10), busy={"board-a": 20}))
        self.assertEqual([(a.job, a.resources) for a in result.next], [("J", ["board-b"])])

    def test_a_resource_no_one_provides_is_reported(self):
        result = js.schedule(problem(js.Job("J", [["gpu"]], 10)))
        self.assertIn("gpu", result.unplaceable.get("J", ""))


class TwoResources(unittest.TestCase):
    def test_a_two_resource_job_waits_for_both(self):
        result = js.schedule(problem(js.Job("J", [["board-a"], ["build"]], 15), busy={"build": 20}))
        self.assertNotIn("J", now_ids(result))
        self.assertEqual(placed(result, "J").start, at(20))

    def test_a_two_resource_job_with_both_free_starts_now(self):
        result = js.schedule(problem(js.Job("J", [["board-a"], ["build"]], 15)))
        self.assertEqual([(a.job, a.resources) for a in result.next], [("J", ["board-a", "build"])])


class Priority(unittest.TestCase):
    def test_priority_list_goes_first(self):
        result = js.schedule(problem(js.Job("P", [["build"]], 60), js.Job("S", [["build"]], 10), priority=["P"]))
        self.assertEqual(now_ids(result), ["P"])
        self.assertEqual(placed(result, "S").start, at(60))

    def test_shortest_first_without_a_priority(self):
        result = js.schedule(problem(js.Job("A-long", [["build"]], 30), js.Job("B-short", [["build"]], 10)))
        self.assertEqual(now_ids(result), ["B-short"])


class WorkConserving(unittest.TestCase):
    def test_a_free_resource_with_an_eligible_ready_job_is_never_idle(self):
        result = js.schedule(problem(js.Job("H", [["board-a"], ["build"]], 30), js.Job("L", [["build"]], 20),
                                     busy={"board-a": 30}, priority=["H"]))
        self.assertEqual(now_ids(result), ["L"])

    def test_a_running_job_keeps_what_it_holds(self):
        result = js.schedule(problem(js.Job("R", [["build"]], 30, state="running", holds=["build"], ends=at(15)), js.Job("J", [["build"]], 10)))
        self.assertEqual(placed(result, "J").start, at(15))


class Late(unittest.TestCase):
    def test_open_job_past_its_planned_end_is_late(self):
        p = problem(js.Job("W", [["build"]], 10, planned_end=at(-30)), busy={"build": 60})
        self.assertIn("LATE", [k for k, _ in js.status(p, js.schedule(p), {})])

    def test_job_inside_its_window_is_not_late(self):
        p = problem(js.Job("W", [["build"]], 10, planned_end=at(30)), busy={"build": 60})
        self.assertNotIn("LATE", [k for k, _ in js.status(p, js.schedule(p), {})])

    def test_done_job_is_not_late(self):
        p = problem(js.Job("W", [["build"]], 10, state="done", planned_end=at(-30)))
        self.assertNotIn("LATE", [k for k, _ in js.status(p, js.schedule(p), {})])

    def test_moving_the_planned_end_does_not_hide_late(self):
        remembered = {}
        first = problem(js.Job("W", [["build"]], 10, planned_end=at(-5)), busy={"build": 60})
        js.status(first, js.schedule(first), remembered)
        moved = problem(js.Job("W", [["build"]], 10, planned_end=at(90)), busy={"build": 60})
        self.assertIn("LATE", [k for k, _ in js.status(moved, js.schedule(moved), remembered)])


class Stalled(unittest.TestCase):
    def _running(self, quiet):
        p = problem(js.Job("R", [["build"]], 60, state="running", holds=["build"], ends=at(30), last_progress=at(-quiet)))
        return [k for k, _ in js.status(p, js.schedule(p), {})]

    def test_running_job_quiet_for_eleven_minutes_is_stalled(self):
        self.assertIn("STALLED", self._running(11))

    def test_running_job_quiet_for_three_minutes_is_not_stalled(self):
        self.assertNotIn("STALLED", self._running(3))


class AlertPath(unittest.TestCase):
    """The CLI an agent runs: status prints each finding and exits 1; a clean state prints clean and exits 0."""

    def _cli(self, body):
        with tempfile.TemporaryDirectory() as tmp:
            adapter = Path(tmp) / "adapter.py"
            adapter.write_text(f"import datetime as dt\nimport job_scheduler as js\n\ndef problem(now):\n{body}\n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = js.main(["--adapter", str(adapter), "status", "--now", NOW.isoformat()])
        return rc, out.getvalue()

    def test_a_free_resource_with_a_ready_job_is_reported_and_exits_1(self):
        rc, out = self._cli("    return js.Problem(now, {'build': None}, [js.Job('J', [['build']], 10)])")
        self.assertEqual((rc, out.split()[0]), (1, "IDLE"))

    def test_nothing_to_report_is_clean_and_exits_0(self):
        rc, out = self._cli("    return js.Problem(now, {'build': None}, [js.Job('J', [['build']], 10, state='done')])")
        self.assertEqual((rc, out.strip()), (0, "clean"))


class PlanJson(unittest.TestCase):
    def test_a_running_job_is_listed_with_its_resources_and_expected_end(self):
        p = problem(js.Job("run", [["build"]], 40, state="running", holds=["build"], ends=at(30)), js.Job("w", [["board-a"]], 5))
        doc = js.plan_json(js.schedule(p), p)
        self.assertEqual([(r["job"], r["resources"], r["end"]) for r in doc["running"]], [("run", ["build"], "2026-01-15T02:30")])
        self.assertEqual(doc["running"][0]["start"], "2026-01-15T01:50")

    def test_nothing_running_lists_none(self):
        p = problem(js.Job("w", [["board-a"]], 5))
        self.assertEqual(js.plan_json(js.schedule(p), p)["running"], [])


if __name__ == "__main__":
    unittest.main()
