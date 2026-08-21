#!/bin/sh
# Serialised, because two callers start the bar: i3 at session start, and
# theme.sh when a re-render changes config.ini. Both kill polybar, both then
# see it gone, and both start one — so without this the bar can end up doubled.
# The lock lives in the runtime dir, which is a tmpfs.
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"${RUNTIME}/polybar-launch.lock" 2>/dev/null &&
    command -v flock >/dev/null 2>&1 && flock 9

# Quit via polybar's own IPC (enable-ipc=true), not `pkill -x polybar`: on NixOS
# polybar is a wrapped binary whose comm is `.polybar-wrapped`, so a name match
# reaps nothing and every relaunch stacks another bar. IPC is wrapper-agnostic.
# The wait matches the argv `polybar main` (present on every platform) rather
# than the name; this script's own argv is its path, so `-f` does not self-match.
polybar-msg cmd quit >/dev/null 2>&1 || true
while pgrep -f 'polybar main' >/dev/null 2>&1; do sleep 1; done

# polybar exits outright if the pulseaudio module cannot reach the daemon, and
# i3 runs this in the same second pulseaudio.service finishes starting.
n=0
while [ "$n" -lt 30 ] && ! pactl info >/dev/null 2>&1; do
    sleep 0.5
    n=$((n + 1))
done

# The log goes to the runtime tmpfs rather than /tmp: on a root filesystem with
# no space left the redirect fails, and the shell then never execs polybar at
# all — a full disk takes the bar down and nothing says why. 9>&- so the
# backgrounded polybar does not inherit the lock and hold it for its lifetime.
polybar main >"${RUNTIME}/polybar-main.log" 2>&1 9>&- &
