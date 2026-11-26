#!/usr/bin/env python3
"""Append one event to DATA_DIR/log.json: log-append.py DATA_DIR "what happened" [source].
Locked and atomic, so concurrent writers never lose an event. The time is taken here, never typed."""
import fcntl, json, os, sys, tempfile, time

if len(sys.argv) < 3:
    sys.exit(__doc__)
d, what, src = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None
path = os.path.join(d, "log.json")
with open(os.path.join(d, ".log.lock"), "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    doc = json.load(open(path)) if os.path.exists(path) else {"events": []}
    doc["events"].append({"at": time.strftime("%Y-%m-%d %H:%M"), "what": what, **({"source": src} if src else {})})
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=1)
    os.replace(tmp, path)
