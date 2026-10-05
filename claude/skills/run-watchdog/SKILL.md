---
name: run-watchdog
description: >-
  Recurring watchdog for long unattended work: detached builds, device test chains, and teammate
  agents. Schedules a 30-minute check that verifies progress from files and processes (never from an
  agent's status claim), fixes mechanical stalls, nudges idle teammates, and reports one line per tick.
  Invoke when a session will run builds, soaks, captures or multi-agent work while the user is away, or
  when the user asks to "keep an eye on", "watch", or "babysit" a run.
---

# Run watchdog

The watchdog exists because unattended work stalls quietly. A chain waits forever on a marker nobody
writes, a teammate goes idle believing someone else will act, a disk fills and turns results into
zeros. None of these announce themselves. Each tick checks the *evidence*, not the narrative.

## Set up (once per session)

1. **Write down what to watch** before scheduling. The tick prompt must name it concretely:
   - log/marker directories and the naming convention (`<job>.log` and `<job>.log.done`);
   - the progress line for each job type (for example, a build's task counter), and its failure markers;
   - evidence directories whose mtimes prove a capture or soak is advancing;
   - capture destinations to check for free space, and which of them are RAM-backed (`tmpfs`);
   - invariants that must hold for the whole run (a pipeline paused, a lock held by one job at a time);
   - where stage-transition notes go (a ticket comment).
2. **Schedule it** with `CronCreate`, recurring, on an off-minute pair (for example `13,43 * * * *`).
   Put the whole checklist in the prompt; the tick has no other memory. Tell the user that recurring
   jobs expire after 7 days.
3. **Arm an end-waiter per detached chain** in addition to the tick: a background `until ! kill -0
   <pid>; do sleep 60; done` on the chain's pid, so the end is seen within a minute rather than up to
   30 minutes later. Wait on the **pid**, never on `pgrep -f <name>`: the waiter's own command line
   contains the name and matches itself, so it never exits.

## Each tick

Read only counts, last lines and mtimes. Never dump a log into context.

1. **Jobs.** For each log: last progress line, `grep -c` of failure markers, mtime. A job whose log
   ends in its exit line (for example `BUILD_EXIT=0`) but has no `.done` marker is a **stall**: its
   downstream waits forever.
2. **Processes.** List the running chains with `ps -eo pid,etime,args | grep -E '[o]rchestrate'`: the
   bracket keeps grep from matching its own command line. Better still, `kill -0 <pid>` each known pid.
   Trust this over any agent's account of what is running.
3. **Agents.** `ListAgents`. A teammate idle while its stage is unfinished, or silent for more than 30
   minutes, is a stall. Before nudging, check whether its last idle notice predates your last message:
   messages cross in transit, and one may already be queued.
4. **Space.** `df` every capture destination. A RAM-backed `/tmp` that fills both truncates evidence and
   squeezes the host.
5. **Invariants.** Each one checked by its own command, for example `systemctl --user is-active
   <timer>` printing `inactive` or `failed`.

## Acting on what you find

- **Missing marker:** confirm the job really finished, from its exit line, then `touch` the marker
  yourself and check that the downstream chain moves. Tell the owner of the script to write markers
  from an `EXIT` trap inside each orchestrator, not from an outer wrapper.
- **Idle teammate:** send one specific instruction (what to start, with which id) and ask for a
  one-line confirmation carrying a pid or SHA. Then verify that the artifact exists: `ls` the log or
  `grep` the script. An acknowledgement is not an action.
- **Disk filling:** move *finished* evidence to real disk and leave symlinks so paths still resolve.
  The bytes stay unchanged; only the location moves. Never move a directory still being written. Have
  every capture loop check free space before each batch and abort cleanly below a floor.
- **Results that may have lost data:** any analysis over captured data must report frames found
  against frames expected, and mark a short batch VOID. A lost burst must never read as "0 found".
  Re-check earlier results once that is in place.
- **Agent claims a chain is still running:** check `ps`. Stale status reports are common; correct the
  agent so it does not act on them.
- **Environment problem** (root-owned files, EACCES, odd signals): one diagnostic, then report it and
  stop. Don't build workarounds.

## Reporting

- One short progress note per tick: what is running, and any stall found and what you did about it. A
  quiet tick says so in a line.
- A ticket comment only on a stage transition, never per tick.
- Never ask the user what they saw on a device during the run. If they volunteer a sighting, treat it
  as a lead: note the time and the board state from the logs, then design a measurement that captures
  it.
