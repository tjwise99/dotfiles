#!/usr/bin/env python3
"""Keep a schedule.json (the self-hosted-status-page format) true to the job records, with no agent.

  schedule_keeper.py --schedule S --events E sync    apply job START/END events to S (atomic write)
  schedule_keeper.py --schedule S [--events E] check findings in S, idle gaps included; exit 1 on any

An events file is appended to by whatever runs the jobs, one line per event:

  HH:MM:SS START <job-id> [record=<id>]
  HH:MM:SS END <job-id> <result> [record=<id>] [why=<text to the end of the line>]

<result> is a word from the page's vocabulary (VOCAB). Lines in any other shape are ignored, so
the file can also carry free text for people. Times are the host clock's; the schedule's `date` and
each job's `day` place them.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile

VOCAB = ("passed", "failed", "failed as designed", "void", "stopped", "not proven", "dropped", "cut")
STATE_FOR = {"failed": "failed", "stopped": "failed", "dropped": "cut", "cut": "cut"}
OPEN = ("waiting", "running")
EVENT = re.compile(
    r"^(?P<t>\d\d:\d\d:\d\d) (?P<kind>START|END) (?P<job>[A-Za-z0-9][\w.-]*)"
    r"(?: (?P<result>" + "|".join(re.escape(v) for v in sorted(VOCAB, key=len, reverse=True)) + r"))?"
    r"(?: record=(?P<record>\S+))?(?: why=(?P<why>.*))?$")


class Event:
    def __init__(self, m):
        self.time = m["t"][:5]
        self.kind, self.job, self.result = m["kind"], m["job"], m["result"]
        self.record, self.why = m["record"], m["why"]


def read_events(path):
    out = []
    if path and os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = EVENT.match(line.rstrip("\n"))
                if m and (m["kind"] == "START" or m["result"]):
                    out.append(Event(m))
    return out


class Schedule:
    def __init__(self, path):
        self.path = path
        with open(path, encoding="utf-8") as fh:
            self.doc = json.load(fh)
        self.jobs = {j["id"]: j for j in self.doc.get("jobs", [])}

    def day(self, job, when):
        """The job's date: its own `day`, else the schedule's `date`."""
        return job.get("day") or self.doc.get("date")

    def apply(self, ev, today):
        """Apply one event; return a sentence when the job changed, else None.

        Only an open job (waiting or running) changes: a job someone has already closed by hand
        keeps that person's outcome, and replaying the same file changes nothing.
        """
        job = self.jobs.get(ev.job)
        if not job or job.get("state") not in OPEN:
            return None
        if ev.kind == "START":
            if job["state"] == "running":
                return None
            job["state"] = "running"
            job["actual"] = [ev.time, None]
            job.setdefault("day", today)
            if ev.record:
                job.setdefault("progress", {})["latest"] = f"started, record {ev.record}"
            return f"{ev.job} running from {ev.time}"
        start = (job.get("actual") or [None])[0] or ev.time
        job["actual"] = [start, ev.time]
        job["state"] = STATE_FOR.get(ev.result, "done")
        job["outcome"] = {"result": ev.result, "why": (ev.why or "").strip(), "record": ev.record or ""}
        job.pop("progress", None)
        return f"{ev.job} {job['state']} at {ev.time} ({ev.result})"

    def save(self):
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(self.path)), suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(self.doc, fh, indent=1, ensure_ascii=False)
        os.replace(tmp, self.path)


def window(sched, job_or_hold, start, end):
    day = job_or_hold.get("day") or sched.doc.get("date")
    if not (day and start and end):
        return None
    a = dt.datetime.fromisoformat(f"{day}T{start}")
    b = dt.datetime.fromisoformat(f"{day}T{end}")
    if b < a:
        b += dt.timedelta(days=1)
    return a, b


def resources(job):
    """A job's resources: its `uses` list, else its lane (or group) name."""
    if job.get("uses"):
        return set(job["uses"])
    lane = job.get("lane") or job.get("group")
    return {lane} if lane else set()


def idle_gaps(sched, now, gap_minutes):
    """Gaps of `gap_minutes` or more, between now and `final_start`, when a resource has no open job and no hold."""
    doc, out = sched.doc, []
    fs = doc.get("final_start")
    if not fs:
        return out
    horizon = dt.datetime.combine(now.date(), dt.time.fromisoformat(fs))
    if horizon <= now:
        horizon += dt.timedelta(days=1)
    names = set(doc.get("resources") or {}) or set().union(*(resources(j) for j in sched.jobs.values()))
    for res in sorted(names):
        busy = []
        for j in sched.jobs.values():
            if j.get("state") in OPEN and res in resources(j):
                w = window(sched, j, *(j.get("planned") or [None, None])[:2])
                if w and j.get("state") == "running":
                    w = (w[0], max(w[1], now))
                if w:
                    busy.append(w)
        for h in doc.get("idle_reasons", []):
            if h.get("resource") == res:
                w = window(sched, h, h.get("from"), h.get("to"))
                if w:
                    busy.append(w)
        t = now
        for a, b in sorted(busy):
            if a > t and (min(a, horizon) - t).total_seconds() >= gap_minutes * 60:
                out.append(("IDLE", res, f"{t:%H:%M} to {min(a, horizon):%H:%M} has no open job and no hold"))
            t = max(t, b)
            if t >= horizon:
                break
        if t < horizon and (horizon - t).total_seconds() >= gap_minutes * 60:
            out.append(("IDLE", res, f"{t:%H:%M} to {horizon:%H:%M} has no open job and no hold"))
    return out


def findings(sched, events):
    out = []
    jobs, doc = sched.jobs, sched.doc
    for j in jobs.values():
        res = (j.get("outcome") or {}).get("result")
        if res is not None and res not in VOCAB:
            out.append(("VOCAB", j["id"], f"outcome '{res}' is not a page word; put the detail in why"))
    for p in doc.get("owner_priorities", []):
        if p.get("done"):
            continue
        listed = [jobs[i] for i in p.get("jobs", []) if i in jobs]
        if not any(j.get("state") in OPEN for j in listed) and not p.get("no_job_reason"):
            out.append(("PRIORITY", p.get("id", "?"), f"'{p.get('what', '')[:60]}' has no open job and no no_job_reason"))
    rulings = {r if isinstance(r, str) else str(r) for r in doc.get("rulings_cited", [])}
    for h in doc.get("idle_reasons", []):
        cause = h.get("cause")
        name = f"{h.get('resource')} {h.get('from')} to {h.get('to')}"
        if not cause or (cause not in jobs and not any(cause in r for r in rulings)):
            out.append(("HOLD", name, "no cause naming the job that blocks it, or a ruling in rulings_cited"))
        hw = window(sched, h, h.get("from"), h.get("to"))
        for j in jobs.values():
            if j.get("state") not in OPEN or h.get("resource") not in resources(j):
                continue
            jw = window(sched, j, *(j.get("planned") or [None, None])[:2])
            if hw and jw and jw[0] < hw[1] and hw[0] < jw[1]:
                out.append(("HOLD", name, f"overlaps open job {j['id']} on the same resource"))
    known = set(jobs)
    for e in events:
        if e.job not in known:
            out.append(("EVENT", e.job, f"{e.kind} at {e.time} names no job in the schedule"))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--schedule", required=True)
    ap.add_argument("--events")
    ap.add_argument("--today", help="YYYY-MM-DD, for tests (default: the host's date)")
    ap.add_argument("--now", help="YYYY-MM-DDTHH:MM, for tests (default: the host's clock)")
    ap.add_argument("--gap", type=int, default=10, help="minutes of idle that count (default 10)")
    ap.add_argument("cmd", choices=["sync", "check"])
    args = ap.parse_args(argv)
    sched = Schedule(args.schedule)
    events = read_events(args.events)
    if args.cmd == "sync":
        today = args.today or dt.date.today().isoformat()
        changed = [c for c in (sched.apply(e, today) for e in events) if c]
        if changed:
            sched.save()
        for c in changed:
            print(c)
        return 0
    now = dt.datetime.fromisoformat(args.now) if args.now else dt.datetime.now().replace(second=0, microsecond=0)
    found = findings(sched, events) + idle_gaps(sched, now, args.gap)
    for kind, what, text in found:
        print(f"{kind:8} {what}: {text}")
    if not found:
        print("clean")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
