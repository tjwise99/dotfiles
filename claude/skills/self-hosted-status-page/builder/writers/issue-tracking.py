#!/usr/bin/env python3
"""Write DATA_DIR/issue-tracking.json from GitHub: issue-tracking.py DATA_DIR [owner/repo].
Open issues and pull requests, newest first. Needs the gh CLI, already authenticated."""
import json, os, subprocess, sys, tempfile, time

if len(sys.argv) < 2:
    sys.exit(__doc__)
d = sys.argv[1]
repo = ["--repo", sys.argv[2]] if len(sys.argv) > 2 else []


def gh(kind):
    out = subprocess.run(["gh", kind, "list", *repo, "--state", "open", "--limit", "200", "--json", "number,title,url,updatedAt"],
                         capture_output=True, text=True, check=True).stdout
    return [{"kind": "pr" if kind == "pr" else "issue", "number": r["number"], "name": r["title"], "state": "open", "url": r["url"], "_u": r["updatedAt"]} for r in json.loads(out)]


items = sorted(gh("pr") + gh("issue"), key=lambda r: r["_u"], reverse=True)
for r in items:
    del r["_u"]
fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump({"updated": time.strftime("%H:%M"), "items": items}, f, indent=1)
os.replace(tmp, os.path.join(d, "issue-tracking.json"))
