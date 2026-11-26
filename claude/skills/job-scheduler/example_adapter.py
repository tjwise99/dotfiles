"""An example adapter: a project whose plan is one JSON file, example/plan.json beside this file.

Copy it into the project and change problem() to read the project's own files. job_scheduler.py
calls problem(now) on every `plan` or `status`; nothing else in the core is project-specific.

plan.json:
  resources  {name: null | "YYYY-MM-DDTHH:MM"}   free now, or busy until that time (a hold, a reboot)
  priority   [job id, ...]                       these go first, in this order
  jobs       [{id, needs, minutes, after, state, planned_end, holds, ends, progress_file}]
             needs: [[alternatives], ...]  one resource from each list, held together
             state: waiting | running | done
             progress_file: a running job's log; its last write is the job's last progress
"""
import datetime as dt
import json
import os
import tempfile
from pathlib import Path

import job_scheduler as js

PLAN = Path(__file__).resolve().parent / "example" / "plan.json"
STATE_PATH = os.path.join(tempfile.gettempdir(), "job-scheduler-example-state.json")


def when(text):
    return dt.datetime.fromisoformat(text) if text else None


def progress(path):
    try:
        return dt.datetime.fromtimestamp(os.stat(PLAN.parent / path).st_mtime) if path else None
    except OSError:
        return None


def problem(now):
    doc = json.loads(PLAN.read_text())
    jobs = [js.Job(id=j["id"], needs=j.get("needs", []), minutes=j.get("minutes", 0), after=j.get("after", []),
                   state=j.get("state", "waiting"), planned_end=when(j.get("planned_end")), holds=j.get("holds", []),
                   ends=when(j.get("ends")), last_progress=progress(j.get("progress_file")))
            for j in doc["jobs"]]
    return js.Problem(now=now, resources={r: when(v) for r, v in doc["resources"].items()}, jobs=jobs, priority=doc.get("priority", []))
