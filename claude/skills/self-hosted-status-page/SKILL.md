---
name: self-hosted-status-page
description: >-
  Serve a live status page for a long or unattended session from a local nginx container, rebuilt by a
  systemd user timer whenever the underlying data files change, with no agent in the loop. Invoke when
  people need a page they can open and refresh while work runs, when a hosted-page publish path is
  unavailable, or when the page keeps going stale because an agent has to remember to republish it.
---

# Self-hosted status page

A page that only updates when an agent remembers to publish it goes stale the moment the agent is busy
or gone. Split the job: a **build script** turns data files into one HTML file, a **timer** runs a
small rebuild script, and a **container** serves whatever is in a directory. No agent is in the loop.

## Layout

```
<work>/report/   build.py (data -> page), rebuild-site.sh (timer target), site-rebuild.log
<work>/site/     index.html  (the only file nginx serves)
<data-dir>/      the watched deliverables (json / md)
```

## Start a new session's page

The skill carries a working builder, so a new page starts from copies, not from scratch.

```sh
cp -r <skill-dir>/builder <work>/report      # build.py, template.html, gantt.js, gantt.css, rebuild-site.sh, writers/, sample/
mkdir -p <work>/site <work>/data
cp <work>/report/sample/*.json <work>/report/sample/*.md <work>/data/   # then replace with the session's real inputs
python3 -I <work>/report/build.py --data <work>/data --out <work>/page.html \
  --identity <private>/identity-patterns.txt          # exits non-zero on a refusal
```

Input formats are in `INPUTS.md` in this skill directory; `builder/sample/` is a valid set that renders.
Write the inputs in those formats and the page is the same style every time: Schedule gantt with holds, a
needs-you strip, Results, Plan (the sprint plan reference), Tickets, Team, Log, Decisions, light and dark.
Keep `identity-patterns.txt` per project and out of any published tree; it adds to the built-in baseline
(private addresses, MAC addresses, home-directory paths), which is always on. Then set `DATA_DIR`,
`SITE_DIR`, `IDENTITY` and run `builder/rebuild-site.sh` from
the timer below. When the session's own files are not in these formats, write a small adapter in the
session's work dir (never in the skill) that fills `DATA_DIR`, and point `SYNC` at an executable that runs
it: the rebuild script runs it before computing the signature, and a failure keeps the old page. Symlinks
in `DATA_DIR` count toward the signature.

**Scheduler output.** When the project has a job-scheduler adapter (see the `job-scheduler` skill), set
`SCHEDULER_ADAPTER` to it (and `SCHEDULER` to `job_scheduler.py` if it is not at
`~/.claude/skills/job-scheduler/`). The rebuild's sync stage, after `SYNC`, runs `plan --json` and
`status --json` through `builder/writers/scheduler-out.py` and writes `plan-out.json` into `DATA_DIR`
(INPUTS.md). The build draws the Schedule tab's gantt chart from it: each waiting job's lane and bar come from the
scheduler's plan, and its LATE and STALLED alerts show on the bars with the chart's own marks. A scheduler
failure keeps the old page like a `SYNC` failure. The file is rewritten only when its content changes, but a
plan with a job ready to start moves with the clock, so such a page rebuilds each tick. Running and finished jobs
still come from the records in `schedule.json`. With `SCHEDULER_ADAPTER` unset nothing changes.

## Who writes each input

"No agent in the loop" holds for the page, not for its content: a file nobody writes freezes its tab. Name
the writer of every file in `page.json` under `writers` (`INPUTS.md` has the table and the roles). A script
from records or GitHub writes a file wherever one can (`builder/writers/`); otherwise the role that already
owns that fact writes it, at the moment it learns it, never a separate scribe. A result is shown only once
a reviewer has put their name in the card's `accepted_by`; until then it reads "Pending review.". Whoever
writes a result alone does not decide what the page asserts.

## Refusals and data defects

- A refused or failed rebuild keeps the old page and says so where a person looks: `rebuild-site.sh` writes
  `status.json` beside `index.html` every tick, and the page polls it and shows a red banner ("The last
  rebuild at HH:MM was refused ...", or "The rebuild timer has not run for N minutes"). The same reason
  is in `site-rebuild.log`.
- **Self-refresh.** After each successful build the rebuild writes `version.txt` (a nanosecond timestamp)
  beside `index.html`. The page fetches it every 30 s with `cache: 'no-store'`, and when the value changes
  it reloads, keeping the open tab (the `#hash` the tab buttons already set) and the scroll position
  (`sessionStorage`, in try/catch). Unchanged or a failed fetch: nothing happens and it retries. A page
  open from a file, with no `version.txt` beside it, never reloads.
- A word outside the vocabulary, or an item with the wrong shape, does not refuse the build. It is
  printed as a `DEFECT` line, logged, and drawn as a banner naming the file and its writer from `page.json`.
  Send it back to that writer to fix at the source; never patch the value in the template or the build.

## Project extensions

The core tabs are generic. A project's own topic (a crash investigation, one machine's state, a free-text
brief) is a per-project extension, kept in the project's work dir, never in the skill. An extension is a
directory handed to the build as `EXT_DIR` (or `--ext`), holding for each tab `NAME.tab.html` (one
`<main id="NAME" class="tab" data-name="Name" hidden>` block), `NAME.tab.js` (drawing code; `D`, `el` and
`sv` are in scope and `D.ext.NAME` is the parsed `NAME.json`), optional `NAME.tab.css`, and the input file
`NAME.json` in `DATA_DIR`. The extension's tab must draw a sentence of 40 characters or more when its input
is missing, because the render check refuses an emptier tab. `builder/sample-ext/` and
`sample/notes.json` are a working example. Name the extension input's writer in `page.json` like any other.

## Build script contract (build.py)

- Reads the data files, fills a template, writes one self-contained HTML file.
- **Refuses to write** (non-zero exit, old page stays) if the output holds an identifying string. A
  built-in baseline is always on (private addresses, MAC addresses, home-directory paths); the project's
  `identity-patterns.txt` (hostnames, SSIDs, serials, ids) adds to it, and a named file that is missing
  refuses. The refusal prints a count, never the pattern. The page is reachable by anyone who can reach
  the host.
- **Render check before writing:** load the page in headless Chrome in each theme and fail on a console
  error, an empty section, or a missing expected element count. A build that throws in the page's JS
  otherwise ships a blank page with no visible error.
- Prints the reason on refusal. There is no bypass flag and the message does not suggest one.
- An empty input leaves its tab drawing a sentence saying so; it never fails the render check.

## The skeleton lesson

A hosting service that publishes pages wraps them in a document skeleton for you. Served raw by nginx
the same fragment has none, and it fails in two ways: no `<!doctype html>` puts the browser in quirks
mode, and no `<meta charset="utf-8">` makes it decode UTF-8 as Latin-1, so every check mark, dash and
middle dot in text or inline JS turns into `âœ“`. nginx sends `Content-Type: text/html` with no charset,
so the meta tag is the only source. The split here: `template.html` starts with the charset and viewport
meta tags, and the rebuild script prepends only the doctype, `<html>` and `<head>`:

```sh
printf '<!doctype html>\n<html lang="en">\n<head>\n'
cat built-page.html
```

Do not add a second charset or remove the template's. The meta tags must be within the first 1024 bytes. Closing `</body></html>` may be omitted; browsers
infer them. Web fonts via a stylesheet link work as before; if the host is offline, name a system-font
fallback stack after the web fonts.

## Container

```sh
docker run -d --name status-page --restart unless-stopped \
  -p <port>:80 -v <work>/site:/usr/share/nginx/html:ro nginx:stable-alpine
```

Replace the file atomically (write a temp file in `site/`, `mv` over `index.html`) so a reader never
sees a half-written page.

## Rebuild script (rebuild-site.sh)

`builder/rebuild-site.sh` implements this (config by environment: `DATA_DIR`, `SITE_DIR`, `IDENTITY`,
`WORK_DIR`, `SYNC`); it is `set -euo pipefail` and shellcheck-clean. Steps:

1. `exec 9>"<work>/.rebuild.lock"; flock -n 9 || exit 0`, so runs never overlap.
2. Signature of the watched files: `stat -c '%n %Y' <files> 2>/dev/null | md5sum`. If equal to the
   stored signature and `index.html` exists, exit 0.
3. Run the data sync step (if any) and `timeout 110 python3 build.py`, output to a file.
4. On failure append the last lines of that output to `site-rebuild.log`, keep the old page, store the
   signature (so a refusal is not retried every minute until the data changes), write `status.json` as
   refused (the page's banner), exit 0.
5. On success wrap with the skeleton, `mv` into place, write `version.txt`, store the signature, write `status.json` as ok,
   log `rebuilt` and any `DEFECT` lines.

## Timer (user units, nothing system-wide)

`~/.config/systemd/user/status-page-rebuild.service`:

```ini
[Service]
Type=oneshot
ExecStart=<work>/report/rebuild-site.sh
```

`~/.config/systemd/user/status-page-rebuild.timer`:

```ini
[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=5s
[Install]
WantedBy=timers.target
```

```sh
systemctl --user daemon-reload && systemctl --user enable --now status-page-rebuild.timer
```

If user timers are unavailable (`systemctl --user is-system-running` fails), use a crontab line
`* * * * * <work>/report/rebuild-site.sh`. Timers keep running after logout only with
`loginctl enable-linger`.

## Check it

1. `curl -s localhost:<port> | head -5` shows the doctype and charset lines.
2. `touch` a watched file, wait over a minute: `site-rebuild.log` gains `rebuilt` and the md5 of the
   served page changes.
3. Seed a refusal (put a private address in the data): the log says why, the served page is
   unchanged and, over http, shows the red stale banner within a minute. Remove the seed.
4. Screenshot with `chrome-headless-shell --screenshot --window-size=1280,900` and again at phone
   width (390 wide), in both themes; look for garbled glyphs, horizontal scroll and missing fonts.
5. Stop any older copy loop that also writes `index.html`; two writers overwrite each other, and the
   raw one wins half the time.

## Tear down

```sh
systemctl --user disable --now status-page-rebuild.timer
rm ~/.config/systemd/user/status-page-rebuild.{service,timer}; systemctl --user daemon-reload
docker rm -f status-page
```

## Add a tab

Core tabs go in `builder/template.html` for every project; a project-only tab is an extension (above).
Either way:

- Colours are `:root` tokens only, with the dark value in both dark blocks
  (`@media (prefers-color-scheme:dark)` guarded by `:root:not([data-theme="light"])`, and
  `:root[data-theme="dark"]`). No literal colour in a rule or in JS; use `var(--...)`.
- Outcome states are colour, a word and a mark, never colour alone.
- The tab draws a sentence of 40 characters or more when its input is missing.
- Re-check at 1280 and 390 pixels wide in both themes (step 4 of "Check it"), not only the first time.
