#!/bin/bash
# Timer target: rebuild the served page when a watched input changed.
# Config by environment: DATA_DIR (inputs), SITE_DIR (served dir), IDENTITY (patterns file, optional),
# WORK_DIR (lock, signature, log; default SITE_DIR/..), BUILDER (this directory), SYNC (optional executable
# run before the signature to fill DATA_DIR from the session's own files; a failure keeps the old page).
set -euo pipefail
: "${DATA_DIR:?}" "${SITE_DIR:?}"
BUILDER=${BUILDER:-$(dirname "$(readlink -f "$0")")}
WORK_DIR=${WORK_DIR:-$SITE_DIR/..}
LOG=$WORK_DIR/site-rebuild.log
exec 9>"$WORK_DIR/.rebuild.lock"
flock -n 9 || exit 0
log() { echo "$(date +%T) $*" >>"$LOG"; }
if [ -n "${SYNC:-}" ] && ! "$SYNC" >"$WORK_DIR/sync.out" 2>&1; then
  log "sync failed, kept old page: $(tail -n 3 "$WORK_DIR/sync.out" | tr '\n' ' ' | cut -c1-300)"
  exit 0
fi
sig=$(find -L "$DATA_DIR" -maxdepth 1 -type f -printf '%p %T@\n' | sort | md5sum | cut -d' ' -f1)
if [ -f "$SITE_DIR/index.html" ] && [ "$sig" = "$(cat "$WORK_DIR/site.sig" 2>/dev/null || true)" ]; then exit 0; fi
args=(--data "$DATA_DIR" --out "$WORK_DIR/page.html")
[ -n "${IDENTITY:-}" ] && args+=(--identity "$IDENTITY")
if ! timeout 110 python3 -I "$BUILDER/build.py" "${args[@]}" >"$WORK_DIR/build.out" 2>&1; then
  log "refused, kept old page: $(tail -n 3 "$WORK_DIR/build.out" | tr '\n' ' ' | cut -c1-300)"
  echo "$sig" >"$WORK_DIR/site.sig"
  exit 0
fi
tmp=$(mktemp "$SITE_DIR/.index.XXXXXX")
{
  printf '<!doctype html>\n<html lang="en">\n<head>\n'
  cat "$WORK_DIR/page.html"
} >"$tmp"
chmod 644 "$tmp"
mv "$tmp" "$SITE_DIR/index.html"
echo "$sig" >"$WORK_DIR/site.sig"
log rebuilt
