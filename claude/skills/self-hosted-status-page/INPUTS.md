# Input files

`builder/build.py --data DIR` reads these files from one flat directory. Each is optional; a missing file
leaves its tab drawing a sentence that says so. The `builder/sample/` directory is a complete, valid set. Times are `"HH:MM"` in the
schedule's timezone. Plain GFM and JSON, no frontmatter. The first sentence of each section is the
owner of that fact; the page restates none of it elsewhere.

## Who writes each file
A file nobody writes freezes its tab. `page.json` names the writer of each file (`writers`), and a
defect found in a file is reported against that name. Prefer a script reading records; else the role that
already owns the fact writes it when it learns it.

| File | Writer |
|---|---|
| schedule.json | the scheduler (a script reading the job records, else the role that runs the schedule) |
| needs-owner.json | the role that coordinates the work, since it knows what is blocked on the owner |
| issue-tracking.json | `builder/writers/issue-tracking.py` (reads GitHub with `gh`), on a timer or in `SYNC` |
| results.json | the reviewer: the analyst writes the card, the reviewer writes `accepted_by` |
| roster.md | the role that spawns the agents, at the moment it spawns or retires one |
| plan-out.json | `builder/writers/scheduler-out.py`, run by the rebuild when `SCHEDULER_ADAPTER` is set; never typed by hand |
| plan.json | the planner, once |
| log.json | whoever acts, through `builder/writers/log-append.py`; never typed by hand |
| decisions.json | the role that records the owner's rulings |
| NAME.json (extension) | named in `page.json` by the project that adds the tab |

## page.json
`{"title": "...", "subtitle": "...", "writers": {"schedule.json": "role or script", ...}}`. Header text
and the writer of each file.

## schedule.json (Schedule tab: the gantt chart and the Holds list)
Top level:
- `date` ("YYYY-MM-DD") of the first day; `window` ["HH:MM","HH:MM"] the axis range; `window_days`
  optional [first date, last date] when the window crosses midnight; `final_start` "HH:MM" draws a
  "final work" line (default 22:00); `timezone` (IANA name, default UTC) and `tz_label` (text shown
  beside "Now"); `window_note` one sentence shown above the chart.
- `lanes`: [[lane-id, "Lane name"], ...] in display order. A job whose lane is not listed gets its own lane.
- `resources`: {resource-name: lane-id}. Only lanes named here (a machine or person that is used or
  idle) get a machine row showing holds and idle gaps (10 minutes or more with no job).
- `idle_reasons`: [{"resource","from","to","why"}]. A hold: time a resource is kept idle on purpose, with
  the reason. Drawn as a ticked box in the resource's lane and listed under the chart.
- `owner_priorities`, `bodies`, `plan_cases` and other keys: free-form, carried in the data and ignored by
  the chart; put anything a later tab wants here.

Each entry of `jobs`:
- `id` (unique), `label` ("id: sentence"), `name` (plain words, up to 34 characters), `lane` (else `group`),
  `day` ("YYYY-MM-DD" of the start; an end before its start is the next day).
- `state`: waiting | running | done | failed | cut. `planned` and `actual`: ["HH:MM","HH:MM"] (a running
  job's `actual` may have one entry); `waits_on`: [job ids]; `decides`: the question the job answers.
- `outcome`: {"result", "why", "record"}. `result` is one of passed, failed, failed as designed, void,
  stopped, not proven, dropped, cut. A result outside this list is drawn as "Unknown state", never as passed.
- `progress` (running only): {"label","done","total","latest","at"}; `note`; `evidence`.
Late and stale marks are computed from the viewer's clock, never stored.

## plan-out.json (the Schedule tab's gantt chart: the scheduler as its source)
Written by `builder/writers/scheduler-out.py` from the job-scheduler skill's `plan --json` and `status --json`
for one project adapter. Absent when no scheduler is configured; the chart is then drawn from `schedule.json`
alone. `{"running":[row],"next":[row],"plan":[row],"unplaceable":{job: why},"alerts":[{"kind","text"}]}`, a `row` being
{"job","resources":[...],"start","end"} with ISO local times. The build merges it into `schedule.json`'s jobs:
- each `running` row ({"job","resources","start","end"}: the scheduler's start and expected end) keeps a running job
  on the chart: a job with no `schedule.json` entry is added as running from `start` to `end`, one that has an
  entry keeps its record and takes `end` as its expected end (the chart's late mark counts from it).
- each `plan` row of a job that is waiting (or not in `schedule.json`, which adds it) sets the job's lane from its
  first resource (`schedule.json` `resources` maps a resource to a lane, else the resource is its own lane) and
  its planned start and end from `start` and `end`. A job with a record (running, done, failed) keeps it.
- an alert LATE on a job on the chart marks it late from the "planned end HH:MM" in its text; STALLED sets its
  progress time from "since HH:MM", so the chart's own late and no-recent-update marks show. IDLE alerts,
  `next` and `unplaceable` are carried in the data but not drawn; any other alert kind is a data defect.
Not to be confused with `plan.json`, the sprint-plan reference.

## needs-owner.json (the strip above the tabs and the Needs you tab)
`{"updated","source","note","items":[...],"work":[...],"information":[...]}`
- `items`: what the owner must do. Fields `order` (sort key), `what`, `action`, `deadline`, `why_then`,
  `if_nothing`, `link`. Empty list: the strip reads "Nothing needs you". Nothing else on the page asks the
  owner to act.
- `work`: rows of {"body","pr","ticket","state","waits_on"}.
- `information`: {"what","detail","source"}, drawn as "For your information (nothing to do)".

## issue-tracking.json (Tickets tab)
`{"updated","items":[{"kind":"issue"|"pr" (any case),"number","name","state","waits_on":[...],"url"}]}`.

## plan.json (Plan tab: the sprint plan reference)
A reference page that does not change as the day goes on: goals, the findings board, what was ruled out,
where time and bytes go, what runs. Every section is optional; a section with no rows is not drawn. Text is
plain; there is no markup. Each section object takes an optional `title` and `sub` (a one-line note).
- `asof`: one sentence at the top of the tab.
- `goals`: {"rows": [{"label","today","range":[low,high] or null,"unit","note"}]}. A bar scaled to
  `today` with the supported range marked on it; `range` null reads "?".
- `board`: {"legend": [[state,text]], "corner": "Goal", "columns": ["Easy", ...], "rows": [{"goal",
  "cells": [[{"state","name","detail"}, ...] per column]}]}. A chip grid; `state` is ok | test | rule | bad
  (colour, shape and the legend carry the meaning).
- `rejected`: {"rows": [["what was checked","why it was ruled out"], ...]}.
- `charts`: a list of {"title","sub","max","label_width","row_height","foot","notes":[...],"rows":[{"label",
  "total","segs":[{"name","value","cat","text","label"}]}]}. Each row is a stacked horizontal bar on the
  scale 0 to `max`; `cat` picks a colour slot c1 to c5 or cx (grey, fixed); `text` is the hover text;
  `label` is drawn inside the segment (default `name`; false for none, and segments narrower than 60
  pixels get none).
- `stack`: {"legend": [[state,text]], "rows": [{"layer","items":[{"state","name","note"}]}]}. Pills grouped
  by layer, same states as `board`.

## results.json (Results tab)
A list of cards: `{"id","title","outcome","why","record","result","accepted_by"}`. `outcome` uses the same
words as a job's `outcome.result`, or "waiting". `result` is drawn only when `accepted_by` names the
reviewer who accepted it; with `result` but no `accepted_by` the card reads "Pending review.", and with no
`result`, "Pending."

## log.json (Log tab)
`{"events":[{"at":"YYYY-MM-DD HH:MM","what","source"}]}`. Shown newest first. Append with
`builder/writers/log-append.py`.

## decisions.json (Decisions tab)
`{"rows":[{"id","decision","who","status","ruling","source","superseded_by"}]}`. `status` is open |
ruled | superseded; a superseded row is struck through and names `superseded_by`.

## roster.md (Team tab)
The first GFM table in the file, header row first. Any columns.

## identity-patterns.txt (not drawn; read with --identity)
One regular expression per line; `#` starts a comment. If any matches the finished page the build refuses.
Keep one per project, outside any published tree: hostnames, network names, serials, machine ids. It adds
to the built-in baseline, which is always on: private IPv4 addresses, MAC addresses, home-directory
paths. A refusal prints how many patterns matched, never which.
