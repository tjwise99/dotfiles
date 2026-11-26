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
cp -r <skill-dir>/builder <work>/report      # build.py, template.html, gantt.js, gantt.css, rebuild-site.sh, sample/
mkdir -p <work>/site <work>/data
cp <work>/report/sample/*.json <work>/report/sample/*.md <work>/data/   # then replace with the session's real inputs
python3 -I <work>/report/build.py --data <work>/data --out <work>/page.html \
  --identity <private>/identity-patterns.txt          # exits non-zero on a refusal
```

Input formats are in `INPUTS.md` in this skill directory; `builder/sample/` is a valid set that renders.
Write the inputs (schedule, needs-owner, issue-tracking, results, roster) from whatever the session
produces, in those formats, and the page is the same style every time: Schedule gantt with holds, a
needs-you strip, Results, Tickets, Team, light and dark. Keep `identity-patterns.txt` per project and out
of any published tree. Then set `DATA_DIR`, `SITE_DIR`, `IDENTITY` and run `builder/rebuild-site.sh` from
the timer below. Add a tab by adding a `<main class="tab" data-name="...">` block and its drawing code to
`builder/template.html`; the render check counts tabs itself.

## Build script contract (build.py)

- Reads the data files, fills a template, writes one self-contained HTML file.
- **Refuses to write** (non-zero exit, old page stays) if the output holds an identifying string
  (address, hostname, SSID, MAC, serial, username in a path, secret). Keep the pattern list in the
  script; the page is reachable by anyone who can reach the host.
- **Render check before writing:** load the page in headless Chrome in each theme and fail on a console
  error, an empty section, or a missing expected element count. A build that throws in the page's JS
  otherwise ships a blank page with no visible error.
- Prints the reason on refusal; never offer a bypass flag.

## The skeleton lesson

A hosting service that publishes pages wraps them in a document skeleton for you. Served raw by nginx
the same fragment has none, and it fails in two ways: no `<!doctype html>` puts the browser in quirks
mode, and no `<meta charset="utf-8">` makes it decode UTF-8 as Latin-1, so every check mark, dash and
middle dot in text or inline JS turns into `âœ“`. nginx sends `Content-Type: text/html` with no charset,
so the meta tag is the only source. Prepend the skeleton in the rebuild script, not the template:

```sh
printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
cat built-page.html
```

The meta tags must be within the first 1024 bytes. Closing `</body></html>` may be omitted; browsers
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
`WORK_DIR`); it is `set -euo pipefail` and shellcheck-clean. Steps:

1. `exec 9>"<work>/.rebuild.lock"; flock -n 9 || exit 0`, so runs never overlap.
2. Signature of the watched files: `stat -c '%n %Y' <files> 2>/dev/null | md5sum`. If equal to the
   stored signature and `index.html` exists, exit 0.
3. Run the data sync step (if any) and `timeout 110 python3 build.py`, output to a file.
4. On failure append the last lines of that output to `site-rebuild.log`, keep the old page, store the
   signature (so a refusal is not retried every minute until the data changes), exit 0.
5. On success wrap with the skeleton, `mv` into place, store the signature, log `rebuilt`.

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
3. Seed a refusal (put an identifying string in the data): the log says why, the served page is
   unchanged. Remove the seed.
4. Screenshot with `chrome-headless-shell --screenshot --window-size=1280,900` and again at phone
   width (390 wide); look for garbled glyphs, horizontal scroll and missing fonts.
5. Stop any older copy loop that also writes `index.html`; two writers overwrite each other, and the
   raw one wins half the time.

## Tear down

```sh
systemctl --user disable --now status-page-rebuild.timer
rm ~/.config/systemd/user/status-page-rebuild.{service,timer}; systemctl --user daemon-reload
docker rm -f status-page
```
