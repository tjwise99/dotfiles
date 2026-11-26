#!/bin/bash
# Timer target: rebuild the served page when a watched input changed.
# Config by environment: DATA_DIR (inputs), SITE_DIR (served dir), IDENTITY (project patterns file, optional),
# EXT_DIR (project extension tabs, optional), WORK_DIR (lock, signature, log; default SITE_DIR/..),
# BUILDER (this directory), SYNC (optional executable run before the signature to fill DATA_DIR from the
# session's own files; a failure keeps the old page), SCHEDULER_ADAPTER (optional: a job-scheduler adapter; when set,
# plan-out.json is written into DATA_DIR from the scheduler's plan and status, after SYNC), SCHEDULER (job_scheduler.py;
# default ~/.claude/skills/job-scheduler/job_scheduler.py).
# Every successful build writes SITE_DIR/version.txt after index.html; the page polls it and reloads when it changes.
# Every tick writes SITE_DIR/status.json; the page polls it and shows a banner on a refusal or a dead timer.
set -euo pipefail
: "${DATA_DIR:?}" "${SITE_DIR:?}"
BUILDER=${BUILDER:-$(dirname "$(readlink -f "$0")")}
WORK_DIR=${WORK_DIR:-$SITE_DIR/..}
LOG=$WORK_DIR/site-rebuild.log
exec 9>"$WORK_DIR/.rebuild.lock"
flock -n 9 || exit 0
log() { echo "$(date +%T) $*" >>"$LOG"; }
# status ok|refused [reason]: atomic write of status.json, which the page reads.
status() {
  python3 -I - "$SITE_DIR" "$WORK_DIR/built.txt" "$1" "${2:-}" <<'PY'
import json, os, sys, time
site, built, state, why = sys.argv[1:5]
b = open(built).read().strip() if os.path.exists(built) else ""
doc = {"state": state, "why": why[:300], "at": time.strftime("%H:%M"), "checked": int(time.time()), "built": b}
tmp = os.path.join(site, ".status.tmp")
open(tmp, "w").write(json.dumps(doc))
os.chmod(tmp, 0o644)
os.replace(tmp, os.path.join(site, "status.json"))
PY
}
refuse() { # refuse <log text> <banner text>
  log "refused, kept old page: $1"
  [ -n "$sig" ] && echo "$sig" >"$WORK_DIR/site.sig"
  echo "refused" >"$WORK_DIR/state"
  echo "$1" >"$WORK_DIR/state.why"
  status refused "$1"
  exit 0
}
sig=""
if [ -n "${SYNC:-}" ] && ! "$SYNC" >"$WORK_DIR/sync.out" 2>&1; then
  refuse "sync failed: $(tail -n 3 "$WORK_DIR/sync.out" | tr '\n' ' ' | cut -c1-250)"
fi
if [ -n "${SCHEDULER_ADAPTER:-}" ] && ! python3 -I "$BUILDER/writers/scheduler-out.py" --adapter "$SCHEDULER_ADAPTER" \
  --scheduler "${SCHEDULER:-$HOME/.claude/skills/job-scheduler/job_scheduler.py}" --out "$DATA_DIR/plan-out.json" >"$WORK_DIR/scheduler.out" 2>&1; then
  refuse "scheduler failed: $(tail -n 3 "$WORK_DIR/scheduler.out" | tr '\n' ' ' | cut -c1-250)"
fi
sig=$(find -L "$DATA_DIR" ${EXT_DIR:+"$EXT_DIR"} -maxdepth 1 -type f -printf '%p %T@\n' | sort | md5sum | cut -d' ' -f1)
if [ -f "$SITE_DIR/index.html" ] && [ "$sig" = "$(cat "$WORK_DIR/site.sig" 2>/dev/null || true)" ]; then
  if [ "$(cat "$WORK_DIR/state" 2>/dev/null || true)" = refused ]; then
    status refused "$(cat "$WORK_DIR/state.why")"
  else
    status ok
  fi
  exit 0
fi
args=(--data "$DATA_DIR" --out "$WORK_DIR/page.html")
[ -n "${IDENTITY:-}" ] && args+=(--identity "$IDENTITY")
[ -n "${EXT_DIR:-}" ] && args+=(--ext "$EXT_DIR")
if ! timeout 110 python3 -I "$BUILDER/build.py" "${args[@]}" >"$WORK_DIR/build.out" 2>&1; then
  refuse "$(tail -n 3 "$WORK_DIR/build.out" | tr '\n' ' ' | cut -c1-250)"
fi
tmp=$(mktemp "$SITE_DIR/.index.XXXXXX")
{
  printf '<!doctype html>\n<html lang="en">\n<head>\n'
  cat "$WORK_DIR/page.html"
} >"$tmp"
chmod 644 "$tmp"
mv "$tmp" "$SITE_DIR/index.html"
date +%s%N >"$SITE_DIR/.version.tmp"
chmod 644 "$SITE_DIR/.version.tmp"
mv "$SITE_DIR/.version.tmp" "$SITE_DIR/version.txt"
echo "$sig" >"$WORK_DIR/site.sig"
date +%H:%M >"$WORK_DIR/built.txt"
echo ok >"$WORK_DIR/state"
status ok
log rebuilt
grep '^DEFECT ' "$WORK_DIR/build.out" | while read -r l; do log "$l"; done || true
