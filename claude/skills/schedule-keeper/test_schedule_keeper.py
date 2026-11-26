"""Constructed cases for schedule_keeper: each check has a case that must fire and a valid variant that must not."""
import contextlib
import io
import json
import os
import tempfile
import unittest

import schedule_keeper as sk

DAY = "2026-01-15"


def schedule(**top):
    doc = {"date": DAY, "jobs": [
        {"id": "build", "state": "waiting", "uses": ["lock"], "planned": ["10:00", "11:00"], "day": DAY},
        {"id": "test", "state": "waiting", "uses": ["board"], "planned": ["11:00", "11:30"], "day": DAY},
        {"id": "old", "state": "done", "outcome": {"result": "passed", "why": "by hand", "record": "r0"}},
    ]}
    doc.update(top)
    return doc


class Case:
    def __init__(self, doc, events=""):
        self.dir = tempfile.mkdtemp()
        self.sched = os.path.join(self.dir, "schedule.json")
        self.events = os.path.join(self.dir, "events.log")
        self.now = f"{DAY}T10:00"
        with open(self.sched, "w") as fh:
            json.dump(doc, fh)
        with open(self.events, "w") as fh:
            fh.write(events)

    def run(self, cmd):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = sk.main(["--schedule", self.sched, "--events", self.events, "--today", DAY,
                          "--now", self.now, cmd])
        return rc, out.getvalue()

    def job(self, jid):
        with open(self.sched) as fh:
            return {j["id"]: j for j in json.load(fh)["jobs"]}[jid]


class Sync(unittest.TestCase):
    def test_start_then_end_closes_the_job(self):
        c = Case(schedule(), "10:02:00 START build record=r1\n10:40:10 END build passed record=r1 why=image built\n")
        rc, out = c.run("sync")
        self.assertEqual(rc, 0)
        j = c.job("build")
        self.assertEqual((j["state"], j["actual"]), ("done", ["10:02", "10:40"]))
        self.assertEqual(j["outcome"], {"result": "passed", "why": "image built", "record": "r1"})

    def test_failure_words_map_to_failed_state(self):
        for word, state in (("failed", "failed"), ("stopped", "failed"), ("void", "done"), ("cut", "cut")):
            c = Case(schedule(), f"10:00:00 START build\n10:05:00 END build {word}\n")
            c.run("sync")
            self.assertEqual(c.job("build")["state"], state, word)

    def test_replay_changes_nothing(self):
        c = Case(schedule(), "10:02:00 START build\n10:40:00 END build passed\n")
        c.run("sync")
        with open(c.sched) as fh:
            before = fh.read()
        rc, out = c.run("sync")
        with open(c.sched) as fh:
            self.assertEqual((rc, out, fh.read()), (0, "", before))

    def test_second_start_keeps_the_first_start(self):
        c = Case(schedule(), "10:02:00 START build\n10:09:00 START build\n")
        c.run("sync")
        self.assertEqual(c.job("build")["actual"], ["10:02", None])

    def test_closed_job_keeps_its_hand_outcome(self):
        c = Case(schedule(), "12:00:00 END old failed\n")
        c.run("sync")
        self.assertEqual(c.job("old")["outcome"]["result"], "passed")

    def test_free_text_and_off_vocabulary_lines_ignored(self):
        c = Case(schedule(), "10:00:00 img build started by hand\n10:05:00 END build maybe\n")
        self.assertEqual(c.run("sync"), (0, ""))
        self.assertEqual(c.job("build")["state"], "waiting")


class Check(unittest.TestCase):
    def test_valid_schedule_is_clean(self):
        doc = schedule(owner_priorities=[{"id": "P1", "what": "x", "jobs": ["build"], "done": False}],
                       idle_reasons=[{"resource": "board", "from": "10:00", "to": "11:00", "day": DAY, "cause": "build"}])
        self.assertEqual(Case(doc).run("check"), (0, "clean\n"))

    def test_outcome_word_outside_vocabulary(self):
        doc = schedule()
        doc["jobs"][2]["outcome"]["result"] = "passed (cut)"
        rc, out = Case(doc).run("check")
        self.assertIn("VOCAB    old:", out)

    def test_priority_with_no_open_job(self):
        p = {"id": "P1", "what": "x", "jobs": ["old"], "done": False}
        rc, out = Case(schedule(owner_priorities=[p])).run("check")
        self.assertIn("PRIORITY P1:", out)
        p["no_job_reason"] = "waits on the owner"
        self.assertEqual(Case(schedule(owner_priorities=[p])).run("check"), (0, "clean\n"))

    def test_hold_without_cause(self):
        h = {"resource": "board", "from": "09:00", "to": "10:00", "day": DAY}
        _, out = Case(schedule(idle_reasons=[h])).run("check")
        self.assertIn("no cause", out)
        h["cause"] = "R12"
        self.assertEqual(Case(schedule(idle_reasons=[h], rulings_cited=["R12 the owner"])).run("check"), (0, "clean\n"))

    def test_hold_overlapping_an_open_job(self):
        h = {"resource": "lock", "from": "10:30", "to": "12:00", "day": DAY, "cause": "test"}
        _, out = Case(schedule(idle_reasons=[h])).run("check")
        self.assertIn("overlaps open job build", out)
        h["from"] = "11:00"
        self.assertEqual(Case(schedule(idle_reasons=[h])).run("check"), (0, "clean\n"))

    def test_hold_across_midnight(self):
        doc = schedule()
        doc["jobs"][0].update(planned=["00:30", "01:00"], day="2026-01-16")
        h = {"resource": "lock", "from": "23:00", "to": "00:45", "day": DAY, "cause": "test"}
        _, out = Case(dict(doc, idle_reasons=[h])).run("check")
        self.assertIn("overlaps open job build", out)

    def test_idle_gap_before_final_start(self):
        doc = schedule(final_start="11:30")
        _, out = Case(doc).run("check")
        self.assertIn("IDLE     board: 10:00 to 11:00", out)
        self.assertIn("IDLE     lock: 11:00 to 11:30", out)
        doc["idle_reasons"] = [{"resource": "board", "from": "10:00", "to": "11:00", "day": DAY, "cause": "build"},
                               {"resource": "lock", "from": "11:00", "to": "11:30", "day": DAY, "cause": "test"}]
        self.assertEqual(Case(doc).run("check"), (0, "clean\n"))

    def test_short_gap_is_not_idle(self):
        doc = schedule(final_start="11:30")
        doc["jobs"][1]["planned"] = ["10:05", "11:30"]
        doc["jobs"][0]["planned"] = ["10:00", "11:25"]
        self.assertEqual(Case(doc).run("check"), (0, "clean\n"))

    def test_event_for_unknown_job(self):
        _, out = Case(schedule(), "10:00:00 START bulid\n").run("check")
        self.assertIn("EVENT    bulid:", out)


if __name__ == "__main__":
    unittest.main()
