#!/usr/bin/env python3
"""Write plan-out.json: the job-scheduler's `plan --json` and `status --json` for one project adapter.

  scheduler-out.py --scheduler job_scheduler.py --adapter ADAPTER.py --out DATA_DIR/plan-out.json [--now YYYY-MM-DDTHH:MM]

Exit 0 on success; non-zero when the scheduler fails (status exiting 1 means "found something" and is
not a failure). The file is rewritten only when its content changed, so an unchanged plan does not
trigger a rebuild.
"""
import argparse
import json
import os
import subprocess
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--scheduler", required=True)
ap.add_argument("--adapter", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--now")
a = ap.parse_args()


def run(cmd, ok):
    r = subprocess.run([sys.executable, a.scheduler, "--adapter", a.adapter, cmd, "--json"] + (["--now", a.now] if a.now else []),
                       capture_output=True, text=True, timeout=60)
    if r.returncode not in ok:
        sys.exit(f"scheduler {cmd} failed ({r.returncode}): {r.stderr.strip()[-300:]}")
    return json.loads(r.stdout)


doc = run("plan", (0,))
doc["alerts"] = run("status", (0, 1))
text = json.dumps(doc, indent=1)
if not (os.path.exists(a.out) and open(a.out).read() == text):
    tmp = a.out + ".tmp"
    open(tmp, "w").write(text)
    os.replace(tmp, a.out)
