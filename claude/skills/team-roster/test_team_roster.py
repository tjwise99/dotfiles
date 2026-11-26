"""Constructed cases for team_roster: each finding has a case that must raise it and a valid variant that must not."""
import contextlib
import datetime as dt
import io
import json
import os
import tempfile
import unittest

import team_roster

TEAM, LEAD = "t1", "lead-sess"
NOW = "2026-01-15T12:00:00Z"


def at(minute):
    """Minutes after 11:00; NOW is minute 60. Negative minutes are before 11:00."""
    return (dt.datetime(2026, 1, 15, 11, tzinfo=dt.timezone.utc) + dt.timedelta(minutes=minute)) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")


def assistant(minute, *content, mid=None):
    return {"type": "assistant", "timestamp": at(minute),
            "message": {"id": mid or f"m{minute}-{len(content)}", "content": list(content),
                        "usage": {"input_tokens": 10, "output_tokens": 5}}}


def big(minute, context):
    row = assistant(minute, text("ok"))
    row["message"]["usage"]["cache_read_input_tokens"] = context
    return row


def text(t):
    return {"type": "text", "text": t}


def tool(name, **args):
    return {"type": "tool_use", "name": name, "input": args}


def inbound(minute, sender):
    return {"type": "user", "timestamp": at(minute),
            "message": {"content": f'<teammate-message teammate_id="{sender}">hi</teammate-message>'}}


class Fixture:
    def __init__(self):
        self.dir = tempfile.mkdtemp()
        self.proj = os.path.join(self.dir, "proj")
        self.docs = os.path.join(self.dir, "docs")
        os.makedirs(os.path.join(self.proj, LEAD, "subagents"))
        os.makedirs(self.docs)
        self.lead_rows, self.n = [], 0

    def agent(self, name, rows):
        self.n += 1
        base = os.path.join(self.proj, LEAD, "subagents", f"agent-{self.n}")
        json.dump({"name": name, "teamName": TEAM, "model": "m"}, open(base + ".meta.json", "w"))
        with open(base + ".jsonl", "w") as f:
            f.writelines(json.dumps(r) + "\n" for r in rows)

    def stop(self, minute, name):
        self.lead_rows.append(assistant(minute, tool("TaskStop", task_id=name)))

    def doc(self, name):
        open(os.path.join(self.docs, name), "w").write("x")

    def run(self, cmd="check", **extra):
        lead = os.path.join(self.proj, LEAD + ".jsonl")
        with open(lead, "w") as f:
            f.writelines(json.dumps(r) + "\n" for r in self.lead_rows)
        cfg = {"team": TEAM, "projects_dir": self.proj, "lead_transcripts": [lead], "docs_dir": self.docs,
               "handover": "handover-{name}.md", "retro": "retro-{name}.md"}
        cfg.update(extra)
        path = os.path.join(self.dir, "cfg.json")
        json.dump(cfg, open(path, "w"))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = team_roster.main(["--config", path, "--now", NOW, cmd])
        self.err = err.getvalue()
        return rc, out.getvalue()


class Findings(unittest.TestCase):
    def test_clean_team_is_clean(self):
        f = Fixture()
        f.agent("a", [assistant(55, text("done"))])
        self.assertEqual(f.run(), (0, "clean\n"))

    def test_stopped_without_retro(self):
        f = Fixture()
        f.agent("a", [assistant(10, text("done"))])
        f.stop(11, "a")
        rc, out = f.run()
        self.assertEqual(rc, 1)
        self.assertIn("NO-RETRO  a: stopped at", out)
        self.assertIn("with no retro-a.md on disk", out)
        f.doc("retro-a.md")
        self.assertEqual(f.run(), (0, "clean\n"))

    def test_woken_after_stop(self):
        f = Fixture()
        f.agent("a", [assistant(10, text("done")), inbound(20, "b"), assistant(21, text("ok"))])
        f.agent("b", [assistant(19, tool("SendMessage", to="a", message="x"))])
        f.doc("retro-a.md")
        f.stop(11, "a")
        rc, out = f.run()
        self.assertIn("WOKEN     a: closed at", out)
        self.assertIn("woken by b", out)
        self.assertNotIn("CLOSE?", out)  # a woken closed agent is still closed, not idle

    def test_message_sent_before_stop_is_not_a_wake(self):
        f = Fixture()
        f.agent("a", [assistant(10, text("done")), inbound(12, "b"), assistant(12, text("ok"))])
        f.agent("b", [assistant(9, tool("SendMessage", to="a", message="x"))])
        f.doc("retro-a.md")
        f.stop(11, "a")
        _, out = f.run()
        self.assertNotIn("WOKEN", out)

    def test_idle_task_agent_proposed_for_close(self):
        f = Fixture()
        f.agent("a", [assistant(5, text("done"))])
        rc, out = f.run()
        self.assertIn("CLOSE?    a: idle 55 min", out)
        self.assertIn("ask for its retro", out)
        f2 = Fixture()
        f2.agent("a", [assistant(35, text("done"))])
        self.assertEqual(f2.run(), (0, "clean\n"))

    def test_silent_mid_turn(self):
        f = Fixture()
        f.agent("a", [assistant(20, tool("Bash", command="x"))])
        _, out = f.run()
        self.assertIn("SILENT    a:", out)
        f2 = Fixture()
        f2.agent("a", [assistant(55, tool("Bash", command="x"))])
        self.assertEqual(f2.run(), (0, "clean\n"))

    def test_refresh_on_context_size(self):
        f = Fixture()
        f.agent("a", [big(55, 300000)])
        _, out = f.run()
        self.assertIn("REFRESH?  a: context 300k", out)
        f2 = Fixture()
        f2.agent("a", [big(55, 200000)])
        self.assertEqual(f2.run(), (0, "clean\n"))
        _, out = f2.run(refresh_context_k=150)
        self.assertIn("REFRESH?  a: context 200k", out)

    def test_refresh_on_age(self):
        f = Fixture()
        f.agent("a", [assistant(-70, text("start")), assistant(55, text("ok"))])
        _, out = f.run()
        self.assertIn("REFRESH?  a: 130 min old", out)
        f2 = Fixture()
        f2.agent("a", [assistant(-50, text("start")), assistant(55, text("ok"))])
        self.assertEqual(f2.run(), (0, "clean\n"))
        _, out = f2.run(refresh_age_minutes=60)
        self.assertIn("REFRESH?  a: 110 min old", out)

    def test_refresh_names_handover(self):
        f = Fixture()
        f.agent("a", [big(55, 300000)])
        _, out = f.run()
        self.assertIn("no handover-a.md on disk: ask for one, then spawn a fresh one", out)
        f.doc("handover-b.md")
        _, out = f.run(handover_aliases={"a": "b"})
        self.assertIn("handover written", out)
        self.assertNotIn("no handover", out)

    def test_refresh_whatever_the_state(self):
        working = big(55, 300000)
        working["message"]["content"] = [tool("Bash", command="x")]
        silent = big(20, 300000)
        silent["message"]["content"] = [tool("Bash", command="x")]
        for row, state in ((working, "working"), (silent, "SILENT")):
            f = Fixture()
            f.agent("a", [row])
            _, out = f.run()
            self.assertIn("REFRESH?  a: context 300k", out, state)

    def test_refresh_skips_stopped(self):
        f = Fixture()
        f.agent("a", [big(10, 300000)])
        f.doc("retro-a.md")
        f.stop(11, "a")
        self.assertEqual(f.run(), (0, "clean\n"))

    def test_raised_threshold_is_clamped(self):
        f = Fixture()
        f.agent("a", [assistant(5, text("done"))])
        _, out = f.run(close_after_minutes=600)
        self.assertIn("CLOSE?    a: idle 55 min", out)
        self.assertIn("close_after_minutes 600 is over the ceiling 30", f.err)
        f2 = Fixture()
        f2.agent("a", [big(55, 300000)])
        _, out = f2.run(refresh_context_k=10000, refresh_age_minutes=10000, idle_minutes=10000)
        self.assertIn("REFRESH?  a: context 300k", out)
        for key in ("refresh_context_k", "refresh_age_minutes", "idle_minutes"):
            self.assertIn(key, f2.err)
        f3 = Fixture()
        f3.agent("a", [assistant(20, tool("Bash", command="x"))])
        _, out = f3.run(idle_minutes=10000)
        self.assertIn("SILENT    a:", out)
        _, out = f3.run(idle_minutes=5)
        self.assertEqual(f3.err, "")

    def test_bad_threshold_fails(self):
        f = Fixture()
        f.agent("a", [assistant(55, text("ok"))])
        for bad in ("30", 0, -1, None, True, float("nan")):
            rc, _ = f.run(close_after_minutes=bad)
            self.assertEqual(rc, 2, bad)
            self.assertIn("close_after_minutes", f.err)

    def test_removed_keys_fail(self):
        for key in ("standing", "hold_open", "ignore", "handover_stale_minutes"):
            f = Fixture()
            f.agent("a", [assistant(55, text("ok"))])
            rc, out = f.run(**{key: []})
            self.assertEqual((rc, out), (2, ""), key)
            self.assertIn(f"'{key}' was removed", f.err)
        self.assertEqual(f.run(), (0, "clean\n"))

    def test_other_session_ignored(self):
        f = Fixture()
        os.makedirs(os.path.join(f.proj, "old", "subagents"))
        base = os.path.join(f.proj, "old", "subagents", "agent-x")
        json.dump({"name": "ghost", "teamName": TEAM}, open(base + ".meta.json", "w"))
        open(base + ".jsonl", "w").write(json.dumps(assistant(1, text("x"))) + "\n")
        self.assertEqual(f.run(), (0, "clean\n"))

    def test_cost_counts_each_message_once(self):
        f = Fixture()
        f.agent("a", [assistant(1, text("x"), mid="same"), assistant(1, text("x"), mid="same"),
                      assistant(2, text("y"), mid="other")])
        rc, out = f.run("cost")
        self.assertEqual(rc, 0)
        row = [l for l in out.splitlines() if l.startswith("a ")][0].split()
        self.assertEqual(row[2:4], ["20", "10"])


if __name__ == "__main__":
    unittest.main()
