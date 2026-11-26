#!/usr/bin/env python3
"""Read a Claude Code agent team's state from disk; no agent is woken.

Sources: the team config (members), each teammate's transcripts (subagents/*.jsonl with
*.meta.json), and the lead's transcripts (its Agent and TaskStop calls). The project supplies a
JSON config (see SKILL.md); nothing here is project-specific.

  team_roster.py --config CFG roster     one row per agent: state, last activity, tokens, docs
  team_roster.py --config CFG check      findings and proposals; exit 1 when there are any
  team_roster.py --config CFG cost       tokens per agent, largest first
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

UTC = dt.timezone.utc
WAKE = re.compile(r'<teammate-message teammate_id="([^"]+)"')


def ts(text):
    return dt.datetime.fromisoformat(text.replace("Z", "+00:00")) if text else None


class Transcript:
    """One teammate transcript: its time span, last turn shape, token use and inbound senders."""

    def __init__(self, path, meta):
        self.path, self.meta = path, meta
        self.first = self.last = None
        self.ends_idle = False
        self.context = 0  # prompt size of the newest model call: how full the context is
        self.tokens = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}
        self.inbound = []  # (time, sender)
        self.sends = []  # (time, recipient)
        seen = set()
        last_kind = None
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
        for line in lines:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            when = ts(row.get("timestamp"))
            if when:
                self.first = self.first or when
                self.last = when
            kind, msg = row.get("type"), row.get("message") or {}
            content = msg.get("content")
            if kind == "assistant":
                mid = msg.get("id")
                usage = msg.get("usage") or {}
                if usage:
                    self.context = sum(usage.get(k, 0) or 0 for k in (
                        "input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
                if mid and mid not in seen:
                    seen.add(mid)
                    self.tokens["input"] += usage.get("input_tokens", 0) or 0
                    self.tokens["output"] += usage.get("output_tokens", 0) or 0
                    self.tokens["cache_read"] += usage.get("cache_read_input_tokens", 0) or 0
                    self.tokens["cache_write"] += usage.get("cache_creation_input_tokens", 0) or 0
                types = [c.get("type") for c in content] if isinstance(content, list) else ["text"]
                if when and isinstance(content, list):
                    self.sends += [(when, c["input"].get("to")) for c in content
                                   if c.get("type") == "tool_use" and c.get("name") == "SendMessage"
                                   and isinstance(c.get("input"), dict)]
                last_kind = "idle" if "tool_use" not in types else "tool"
            elif kind == "user":
                text = content if isinstance(content, str) else " ".join(
                    c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
                found = WAKE.search(text or "")
                if found and when:
                    self.inbound.append((when, found.group(1)))
                last_kind = "tool" if isinstance(content, list) and any(
                    isinstance(c, dict) and c.get("type") == "tool_result" for c in content) else "prompt"
        self.ends_idle = last_kind == "idle"


class Agent:
    def __init__(self, name):
        self.name, self.transcripts, self.stops, self.spawns = name, [], [], []
        self.model = None

    @property
    def current(self):
        return max(self.transcripts, key=lambda t: t.last or dt.datetime.min.replace(tzinfo=UTC), default=None)

    @property
    def last_stop(self):
        return max(self.stops, default=None)

    def tokens(self):
        total = {}
        for t in self.transcripts:
            for k, v in t.tokens.items():
                total[k] = total.get(k, 0) + v
        return total

    def state(self, now, idle_minutes):
        cur = self.current
        if not cur or not cur.last:
            return "unknown"
        stop = self.last_stop
        if stop and stop >= cur.first:
            # A message to a closed in-process teammate resumes it for that one turn only; it is still
            # closed afterwards. WOKEN reports the resume; the state stays stopped.
            return "stopped"
        if cur.ends_idle:
            return "idle"
        age = (now - cur.last).total_seconds() / 60
        return "working" if age < idle_minutes else "silent mid-turn"

    def wakes(self, sent):
        """A message sent to this agent after a stop, which a transcript of it then received.

        `sent` is [(time, sender)] of SendMessage calls addressed to this agent. A message sent before the
        stop and delivered after it is not a wake: the sender could not have known.
        """
        out = []
        for when, who in sent:
            stop = max((s for s in self.stops if s < when), default=None)
            if not stop:
                continue
            got = any(t.first and t.first <= stop and any(w >= when and f == who for w, f in t.inbound)
                      for t in self.transcripts)
            if got:
                out.append((when, who, stop))
        return sorted(set(out))


class Team:
    def __init__(self, cfg):
        self.cfg = cfg
        self.agents = {}
        self._read_teammates()
        self._read_lead()

    def agent(self, name):
        return self.agents.setdefault(name, Agent(name))

    def _read_teammates(self):
        sessions = {os.path.basename(p)[: -len(".jsonl")] for p in self.cfg["lead_transcripts"]}
        for meta_path in glob.glob(os.path.join(self.cfg["projects_dir"], "*", "subagents", "*.meta.json")):
            if meta_path.split(os.sep)[-3] not in sessions:
                continue
            try:
                with open(meta_path) as fh:
                    meta = json.load(fh)
            except ValueError:
                continue
            if meta.get("teamName") != self.cfg["team"] or not meta.get("name"):
                continue
            path = meta_path[: -len(".meta.json")] + ".jsonl"
            if not os.path.exists(path):
                continue
            a = self.agent(meta["name"])
            a.model = meta.get("model") or a.model
            a.transcripts.append(Transcript(path, meta))

    def sent_to(self, name):
        """[(time, sender)] of every SendMessage addressed to `name`, from teammates and the lead."""
        out = [(w, n) for n, a in self.agents.items() for t in a.transcripts for w, to in t.sends if to == name]
        lead = self.cfg.get("lead_name", "team-lead")
        out += [(w, lead) for w, to in self.lead_sends if to == name]
        return out

    def _read_lead(self):
        self.lead_sends = []
        for path in self.cfg["lead_transcripts"]:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
            for line in lines:
                if '"TaskStop"' not in line and '"Agent"' not in line and '"SendMessage"' not in line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                when = ts(row.get("timestamp"))
                content = (row.get("message") or {}).get("content")
                if not when or not isinstance(content, list):
                    continue
                for c in content:
                    if c.get("type") != "tool_use":
                        continue
                    args = c.get("input") or {}
                    if c.get("name") == "TaskStop" and args.get("task_id") in self.agents:
                        self.agents[args["task_id"]].stops.append(when)
                    elif c.get("name") == "Agent" and args.get("name"):
                        self.agent(args["name"]).spawns.append(when)
                    elif c.get("name") == "SendMessage":
                        self.lead_sends.append((when, args.get("to")))

    def doc(self, kind, name):
        pattern = self.cfg.get(kind)
        if not pattern:
            return None
        name = self.cfg.get(kind + "_aliases", {}).get(name, name)
        path = os.path.join(self.cfg["docs_dir"], pattern.format(name=name))
        return path if os.path.exists(path) else None


def hm(when, tz):
    return when.astimezone(tz).strftime("%H:%M") if when else "-"


def mtime(path):
    return dt.datetime.fromtimestamp(os.path.getmtime(path), UTC) if path else None


def findings(team, now, cfg):
    """Each finding is (kind, agent, text). Proposals are for the lead to execute; nothing is sent."""
    out, idle_m, tz = [], cfg.get("idle_minutes", 10), cfg["tz"]
    standing = set(cfg.get("standing", []))
    stale_m = cfg.get("handover_stale_minutes", 120)
    for name, a in sorted(team.agents.items()):
        if name in cfg.get("ignore", []):
            continue
        state = a.state(now, idle_m)
        for when, who, stop in a.wakes(team.sent_to(name)):
            out.append(("WOKEN", name, f"closed at {hm(stop, tz)}, woken by {who} at {hm(when, tz)}"))
        retro, handover = team.doc("retro", name), team.doc("handover", name)
        if state == "stopped" and not retro:
            out.append(("NO-RETRO", name, f"stopped at {hm(a.last_stop, tz)} with no {cfg.get('retro', 'retro')} on disk"))
        if state == "silent mid-turn":
            out.append(("SILENT", name, f"mid-turn and silent since {hm(a.current.last, tz)}: hung, or stopped without a record"))
        if state == "idle" and name not in standing and name not in cfg.get("hold_open", []):
            age = (now - a.current.last).total_seconds() / 60
            if age >= cfg.get("close_after_minutes", 30):
                ask = "propose CLOSE" if retro else "ask for its retro, then propose CLOSE"
                out.append(("CLOSE?", name, f"idle {age:.0f} min, not a standing role: {ask}"))
        limit = cfg.get("refresh_context_k")
        if limit and name in standing and state in ("idle", "working") and a.current.context >= limit * 1000:
            out.append(("REFRESH?", name, f"context {a.current.context / 1e3:.0f}k, at or over {limit}k: propose a fresh one after its handover"))
        if name in standing and state in ("idle", "working"):
            h = mtime(handover)
            if not h:
                out.append(("HANDOVER", name, f"standing role with no {cfg.get('handover')} on disk"))
            elif (now - h).total_seconds() / 60 > stale_m:
                out.append(("HANDOVER", name, f"handover last written {hm(h, tz)}, over {stale_m} min ago"))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", required=True)
    ap.add_argument("--now", help="ISO time, for tests")
    ap.add_argument("cmd", choices=["roster", "check", "cost"])
    args = ap.parse_args(argv)
    with open(args.config) as fh:
        cfg = json.load(fh)
    cfg["tz"] = dt.datetime.now().astimezone().tzinfo
    now = ts(args.now) if args.now else dt.datetime.now(UTC)
    team = Team(cfg)
    if args.cmd == "roster":
        print(f"{'agent':22} {'state':16} {'last':5} {'stop':5} {'model':7} {'Mtok':>6} {'ctx k':>6} handover retro")
        for name, a in sorted(team.agents.items(), key=lambda kv: kv[1].current.last if kv[1].current else dt.datetime.min.replace(tzinfo=UTC), reverse=True):
            if not a.transcripts:
                continue
            t = a.tokens()
            mtok = sum(t.values()) / 1e6
            print(f"{name:22} {a.state(now, cfg.get('idle_minutes', 10)):16} {hm(a.current.last, cfg['tz']):5} "
                  f"{hm(a.last_stop, cfg['tz']):5} {(a.model or '-'):7} {mtok:6.1f} {a.current.context / 1e3:6.0f} "
                  f"{hm(mtime(team.doc('handover', name)), cfg['tz']):8} {'yes' if team.doc('retro', name) else '-'}")
        return 0
    if args.cmd == "cost":
        rows = [(n, a.model, a.tokens()) for n, a in team.agents.items() if a.transcripts]
        rows.sort(key=lambda r: -(r[2]["output"] + r[2]["input"] + r[2]["cache_write"]))
        print(f"{'agent':22} {'model':7} {'in':>9} {'out':>9} {'cache_w':>11} {'cache_r':>13}")
        for n, m, t in rows:
            print(f"{n:22} {(m or '-'):7} {t['input']:9} {t['output']:9} {t['cache_write']:11} {t['cache_read']:13}")
        return 0
    found = findings(team, now, cfg)
    for kind, name, text in found:
        print(f"{kind:9} {name}: {text}")
    if not found:
        print("clean")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
