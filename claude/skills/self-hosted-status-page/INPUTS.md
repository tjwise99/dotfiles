# Input files

`builder/build.py --data DIR` reads these files from one flat directory. Each is optional; a missing file
leaves its tab empty. The `builder/sample/` directory is a complete, valid set. Times are `"HH:MM"` in the
schedule's timezone. Plain GFM and JSON, no frontmatter. The first sentence of each section is the
owner of that fact; the page restates none of it elsewhere.

## page.json
`{"title": "...", "subtitle": "..."}`. Header text.

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

## needs-owner.json (the strip above the tabs and the Needs you tab)
`{"updated","source","note","items":[...],"work":[...],"information":[...]}`
- `items`: what the owner must do. Fields `order` (sort key), `what`, `action`, `deadline`, `why_then`,
  `if_nothing`, `link`. Empty list: the strip reads "Nothing needs you". Nothing else on the page asks the
  owner to act.
- `work`: rows of {"body","pr","ticket","state","waits_on"}.
- `information`: {"what","detail","source"}, drawn as "For your information (nothing to do)".

## issue-tracking.json (Tickets tab)
`{"updated","items":[{"kind":"issue"|"pr","number","name","state","waits_on":[...],"url"}]}`.

## results.json (Results tab)
A list of cards: `{"id","title","outcome","why","record","result"}`. `outcome` uses the same words as a
job's `outcome.result`. A card without `result` reads "Pending."

## roster.md (Team tab)
The first GFM table in the file, header row first. Any columns.

## identity-patterns.txt (not drawn; read with --identity)
One regular expression per line; `#` starts a comment. If any matches the finished page the build refuses.
Keep one per project, outside any published tree: addresses, hostnames, network names, serials, machine
ids, usernames in paths. The builder bakes in no pattern.
