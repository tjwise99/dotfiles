#!/usr/bin/env python3
"""Build one self-contained status page from a directory of input files.

usage: build.py --data DIR --out FILE [--identity FILE] [--ext DIR] [--title T] [--subtitle S]
Refuses (exit 1, writes nothing) on an identifying string or a failed headless render.
Data defects (a word outside the vocabulary, a missing writer) do not refuse: they are printed as
DEFECT lines and drawn as a banner on the page, and go back to the file's writer.
Input formats: INPUTS.md. Per-project tabs: SKILL.md "Project extensions".
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--data", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--identity", help="file of regexes, one per line, that must not appear in the page")
ap.add_argument("--title", default="Status")
ap.add_argument("--subtitle", default="")
ap.add_argument("--ext", help="project extension directory: NAME.tab.html, NAME.tab.js, optional NAME.tab.css and NAME.json")
a = ap.parse_args()


def load(name):
    p = os.path.join(a.data, name)
    return json.load(open(p)) if os.path.exists(p) else None


def md_tables(path):
    """Every GFM table in a file, as a list of row-lists (header first, rule row dropped)."""
    out, cur = [], None
    for l in open(path).read().splitlines():
        if l.startswith("|"):
            r = [c.strip() for c in l.strip().strip("|").split("|")]
            if not set("".join(r)) <= set("-: "):
                cur = (cur or []) + [r]
        elif cur:
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    return out


data = {"cards": load("results.json") or [], "built_at": time.strftime("%H:%M")}
sched = load("schedule.json")
if sched:
    data["gantt"] = sched
    data["gantt_updated"] = time.strftime("%H:%M", time.localtime(os.path.getmtime(os.path.join(a.data, "schedule.json"))))
data["plan_out"] = load("plan-out.json")
if sched and data["plan_out"]:
    # The scheduler's plan is the chart's source for waiting work: resource -> lane, start and end -> bar. Jobs that
    # have a record (schedule.json) keep it; alerts mark them on the chart's own late and stale marks.
    by_id = {j["id"]: j for j in sched.get("jobs", [])}
    hm = lambda t: str(t)[11:16]
    for r in data["plan_out"].get("running", []):
        # A running job always draws: from its record when it has one, else from the scheduler's start and expected end.
        res = (r.get("resources") or ["no resource"])[0]
        lane = sched.get("resources", {}).get(res, res)
        j = by_id.get(r["job"])
        if j is None:
            j = by_id[r["job"]] = {"id": r["job"], "label": r["job"], "name": r["job"], "state": "running", "lane": lane, "group": lane,
                                   "day": str(r["start"] or r["end"])[:10], "planned": [hm(r["start"] or r["end"]), hm(r["end"] or r["start"])], "actual": [hm(r["start"] or r["end"])]}
            sched["jobs"].append(j)
            if lane not in [l[0] for l in sched.get("lanes", [])]:
                sched.setdefault("lanes", []).append([lane, res])
        elif j.get("state") == "running" and r.get("end"):
            j["planned_end"] = hm(r["end"])
    for r in data["plan_out"].get("plan", []):
        res = (r.get("resources") or ["no resource"])[0]
        lane = sched.get("resources", {}).get(res, res)
        j = by_id.get(r["job"])
        if j is None:
            j = by_id[r["job"]] = {"id": r["job"], "label": r["job"], "name": r["job"], "state": "waiting"}
            sched["jobs"].append(j)
        if j.get("state") in ("waiting", None):
            j.update(lane=lane, group=lane, day=str(r["start"])[:10], planned=[hm(r["start"]), hm(r["end"])])
            if lane not in [l[0] for l in sched.get("lanes", [])]:
                sched.setdefault("lanes", []).append([lane, res])
    for al in data["plan_out"].get("alerts", []):
        j = by_id.get(al.get("text", "").split(":")[0])
        m = re.search(r"(\d\d:\d\d)", al.get("text", ""))
        if not j or not m:
            continue
        if al["kind"] == "LATE":
            j["late_since"] = m.group(1)
        elif al["kind"] == "STALLED":
            j["progress"] = {**(j.get("progress") or {}), "at": m.group(1)}
data["needs_owner"] = load("needs-owner.json")
data["plan"] = load("plan.json")
data["plan_out"] = load("plan-out.json")
data["issue_tracking"] = load("issue-tracking.json")
rp = os.path.join(a.data, "roster.md")
if os.path.exists(rp):
    t = md_tables(rp)
    data["roster"] = t[0] if t else []
data["log"] = load("log.json")
data["decisions"] = load("decisions.json")
cfg = load("page.json") or {}
title, subtitle = cfg.get("title", a.title), cfg.get("subtitle", a.subtitle)
writers = cfg.get("writers", {})

VOCAB = {"passed", "failed", "failed as designed", "void", "stopped", "not proven", "dropped", "cut"}
defects = []


def defect(file, what):
    w = writers.get(file)
    defects.append({"file": file, "writer": w, "what": what})
    print(f"DEFECT {file} (writer: {w or 'not named in page.json'}): {what}")


for j in (sched or {}).get("jobs", []):
    r = (j.get("outcome") or {}).get("result")
    if r and r not in VOCAB:
        defect("schedule.json", f"job {j.get('id')} has result {r!r}, not in the vocabulary")
for c in data["cards"]:
    if c.get("outcome") and c["outcome"] not in VOCAB | {"waiting"}:
        defect("results.json", f"card {c.get('id')} has outcome {c['outcome']!r}, not in the vocabulary")
for r in (data["plan_out"] or {}).get("alerts", []):
    if r.get("kind") not in ("LATE", "STALLED", "IDLE"):
        defect("plan-out.json", f"alert has kind {r.get('kind')!r}")
for r in (data["issue_tracking"] or {}).get("items", []):
    if str(r.get("kind", "")).lower() not in ("issue", "pr"):
        defect("issue-tracking.json", f"item {r.get('number')} has kind {r.get('kind')!r}")
for r in (data["decisions"] or {}).get("rows", []):
    if r.get("status") not in ("open", "ruled", "superseded"):
        defect("decisions.json", f"row {r.get('id')} has status {r.get('status')!r}")
data["defects"] = defects

ext_html, ext_js, ext_css = "", "", ""
data["ext"] = {}
for f in sorted(glob.glob(os.path.join(a.ext, "*.tab.html"))) if a.ext else []:
    name = os.path.basename(f)[: -len(".tab.html")]
    stem = f[: -len(".tab.html")]
    ext_html += open(f).read() + "\n"
    ext_js += open(stem + ".tab.js").read() + "\n" if os.path.exists(stem + ".tab.js") else ""
    ext_css += open(stem + ".tab.css").read() + "\n" if os.path.exists(stem + ".tab.css") else ""
    jp = os.path.join(a.data, name + ".json")
    data["ext"][name] = json.load(open(jp)) if os.path.exists(jp) else None

page = open(f"{HERE}/template.html").read()
for k, v in (("%%GANTTJS%%", open(f"{HERE}/gantt.js").read()), ("%%GANTTCSS%%", open(f"{HERE}/gantt.css").read()),
             ("%%EXTTABS%%", ext_html), ("%%EXTJS%%", ext_js), ("%%EXTCSS%%", ext_css)):
    page = page.replace(k, v)
page = page.replace("%%TITLE%%", title.replace("<", "&lt;")).replace("%%SUBTITLE%%", subtitle.replace("<", "&lt;"))
page = page.replace("%%DATA%%", json.dumps(data).replace("</", "<\\/"))
left = re.findall(r"%%[A-Z]+%%", page)
# Built-in baseline, always on: private addresses, MAC addresses, home-directory paths.
BUILTIN = [r"\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b", r"\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b", r"\b192\.168\.\d{1,3}\.\d{1,3}\b",
           r"\b[0-9a-fA-F]{2}([:-])[0-9a-fA-F]{2}(?:\1[0-9a-fA-F]{2}){4}\b", r"/home/[a-z_][a-z0-9_-]*/", r"/Users/[A-Za-z][A-Za-z0-9_-]*/"]
if a.identity and not os.path.isfile(a.identity):
    sys.exit(f"REFUSING: --identity file {a.identity} does not exist")
extra = [l.strip() for l in open(a.identity).read().splitlines() if l.strip() and not l.startswith("#")] if a.identity else []
leaks = sum(1 for p in BUILTIN + extra if re.search(p, page))
if left or leaks:
    sys.exit(f"REFUSING: unfilled placeholders {left}; {leaks} identifying pattern(s) matched (patterns not printed)")


def chrome():
    for c in [os.environ.get("CHROME")] + sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/*/chrome-headless-shell"))) + [shutil.which(n) for n in ("chromium", "chromium-browser", "google-chrome", "chrome")]:
        if c and os.path.exists(c):
            return c
    sys.exit("REFUSING: no headless Chrome for the render check (install one, or set CHROME to its path)")


def render_check(theme):
    pre = f'<script>document.documentElement.setAttribute("data-theme","{theme}")</script>'
    post = '<script>setTimeout(()=>console.log("THEMEBG "+getComputedStyle(document.body).backgroundColor),2500)</script>'
    fd, tmp = tempfile.mkstemp(suffix=".html")
    os.close(fd)
    open(tmp, "w", encoding="utf-8").write("<!doctype html><html><head>" + pre + "</head><body>" + page + post)
    env = {k: v for k, v in os.environ.items() if k != "LD_LIBRARY_PATH"}
    try:
        for n in (1, 2):
            try:
                r = subprocess.run([chrome(), "--no-sandbox", "--enable-logging=stderr", "--v=0", "--dump-dom", "--virtual-time-budget=5000", "file://" + tmp + "#schedule"], capture_output=True, text=True, env=env, timeout=60)
                break
            except subprocess.TimeoutExpired:
                if n == 2:
                    sys.exit("REFUSING: headless render timed out twice")
    finally:
        os.remove(tmp)
    errs = [l for l in r.stderr.splitlines() if ":CONSOLE" in l and ("Uncaught" in l or "Error" in l)]
    dom, bad = r.stdout, []
    for m in re.finditer(r'<main id="([^"]+)" class="tab" data-name="([^"]*)"[^>]*>(.*?)</main>', dom, re.S):
        text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(3))).strip()
        if len(text) < 40:
            bad.append(f"tab {m.group(2)!r} renders {len(text)} characters")
    if len(re.findall(r'<main id="[^"]+" class="tab"', dom)) != len(re.findall(r'<main id="[^"]+" class="tab"', page)):
        bad.append("tab count differs after render")
    if data.get("gantt"):
        g = re.search(r'<div id="gantt"[^>]*>(.*?)</div>\s*<div id="holds-wrap"', dom, re.S)
        if not g or len(re.sub(r"<[^>]+>", "", g.group(1)).strip()) < 50:
            bad.append("schedule chart is empty")
    mbg = re.search(r"THEMEBG rgb\((\d+), (\d+), (\d+)\)", r.stderr)
    lum = sum(int(x) for x in mbg.groups()) / 765 if mbg else None
    if lum is None or (theme == "dark" and lum > 0.25) or (theme == "light" and lum < 0.75):
        bad.append(f"{theme} theme not applied (luminance {lum})")
    if errs or bad:
        sys.exit(f"REFUSING: render failed in the {theme} theme: " + "; ".join(bad) + " | console: " + " / ".join(e[-160:] for e in errs[:3]))


render_check("light")
render_check("dark")
open(a.out, "w", encoding="utf-8").write(page)
print("written", len(page), "bytes;", len(BUILTIN), "built-in and", len(extra), "project identity patterns checked;", len(defects), "data defects")
