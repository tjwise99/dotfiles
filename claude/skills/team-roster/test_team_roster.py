"""Constructed cases for team_roster: each finding has a case that must raise it and a valid variant that must not."""
import contextlib
import io
import json
import os
import tempfile
import unittest

import team_roster

TEAM, LEAD = "t1", "lead-sess"
NOW = "2026-01-15T12:00:00Z"


def at(minute):
    return f"2026-01-15T{11 + minute // 60:02d}:{minute % 60:02d}:00Z" if minute < 60 else \
        f"2026-01-15T{11 + minute // 60:02d}:{minute % 60:02d}:00Z"


def assistant(minute, *content, mid=None):
    return {"type": "assistant", "timestamp": at(minute),
            "message": {"id": mid or f"m{minute}-{len(content)}", "content": list(content),
                        "usage": {"input_tokens": 10, "output_tokens": 5}}}


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
               "handover": "handover-{name}.md", "retro": "retro-{name}.md", "idle_minutes": 10,
               "close_after_minutes": 30, "handover_stale_minutes": 120}
        cfg.update(extra)
        path = os.path.join(self.dir, "cfg.json")
        json.dump(cfg, open(path, "w"))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = team_roster.main(["--config", path, "--now", NOW, cmd])
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
        self.assertIn("NO-RETRO  a:", out)
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
        _, out = f.run(standing=["a"])
        self.assertNotIn("CLOSE?", out)
        _, out = f.run(hold_open=["a"])
        self.assertNotIn("CLOSE?", out)

    def test_silent_mid_turn(self):
        f = Fixture()
        f.agent("a", [assistant(20, tool("Bash", command="x"))])
        _, out = f.run()
        self.assertIn("SILENT    a:", out)
        f2 = Fixture()
        f2.agent("a", [assistant(55, tool("Bash", command="x"))])
        self.assertEqual(f2.run(), (0, "clean\n"))

    def test_standing_role_handover(self):
        f = Fixture()
        f.agent("a", [assistant(55, text("ok"))])
        _, out = f.run(standing=["a"])
        self.assertIn("HANDOVER  a: standing role with no handover", out)
        f.doc("handover-a.md")
        self.assertEqual(f.run(standing=["a"]), (0, "clean\n"))
        f.doc("handover-b.md")
        os.remove(os.path.join(f.docs, "handover-a.md"))
        _, out = f.run(standing=["a"], handover_aliases={"a": "b"})
        self.assertEqual(out, "clean\n")

    def test_refresh_on_context_size(self):
        f = Fixture()
        row = assistant(55, text("ok"))
        row["message"]["usage"]["cache_read_input_tokens"] = 500000
        f.agent("a", [row])
        f.doc("handover-a.md")
        _, out = f.run(standing=["a"], refresh_context_k=400)
        self.assertIn("REFRESH?  a: context 500k", out)
        self.assertEqual(f.run(standing=["a"], refresh_context_k=600), (0, "clean\n"))
        self.assertEqual(f.run(standing=["a"]), (0, "clean\n"))

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
